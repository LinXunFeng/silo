#!/usr/bin/env bash
#
# Cuts a release: versions the workspace with melos, tags it v<version>,
# pushes, and waits for the Release workflow to publish the GitHub release.
#
# The artifacts are built and uploaded by .github/workflows/release.yml, not
# here: the tag push is what triggers it, and the same run bumps the Homebrew
# tap. Building on this Mac would publish binaries the tap never hears about.
#
# Each stage is skipped when it is already done, so a run that stopped part
# way — a failed push, a closed terminal — is resumed by running it again.
#
# Usage: scripts/release.sh [--yes] [--no-check]
#   --yes       skip both confirmations (the version bump and the push)
#   --no-check  skip the local analyze and test run before versioning

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

yes=false
check=true
for arg in "$@"; do
  case "$arg" in
    --yes) yes=true ;;
    --no-check) check=false ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
die() {
  echo "error: $*" >&2
  exit 1
}
confirm() {
  $yes && return 0
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" == [yY]* ]]
}

workspace_version() {
  grep -m1 '^version:' packages/core/pubspec.yaml | cut -d' ' -f2 | cut -d+ -f1
}

# Prints the newest Release workflow run on $tag, giving it 150 seconds to show.
find_run() {
  local id
  for _ in $(seq 1 30); do
    id=$(gh run list --workflow release.yml --branch "$tag" --limit 1 \
      --json databaseId --jq '.[0].databaseId // empty')
    [ -n "$id" ] && break
    sleep 5
  done
  echo "$id"
}

# ── Preflight ────────────────────────────────────────────────────────────────
step 'Preflight'
command -v gh > /dev/null || die 'gh is not installed'
gh auth status > /dev/null 2>&1 || die 'gh is not logged in (gh auth login)'
[ "$(git branch --show-current)" = main ] || die 'releases are cut from main'
[ -z "$(git status --porcelain)" ] || die 'the working tree is not clean'
git fetch --quiet --tags origin
[ -z "$(git rev-list HEAD..origin/main)" ] ||
  die 'main is behind origin/main; pull first'

# ── Version and tag ──────────────────────────────────────────────────────────
# A v* tag on HEAD means an earlier run already versioned this commit.
tag=$(git tag --points-at HEAD --list 'v*' | head -n1)
if [ -n "$tag" ]; then
  echo "HEAD is already tagged $tag; skipping the version bump."
else
  [ -n "$(git log -1 --format=%s | grep '^chore(release)' || true)" ] &&
    die 'HEAD is a release commit without a v* tag; tag it by hand or reset it'

  if $check; then
    step 'Analyze and test'
    dart run melos run analyze
    dart run melos run test
  fi

  step 'Version with melos'
  # melos prints the bump and the changelog, then asks before writing them.
  melos_args=(version --all)
  $yes && melos_args+=(--yes)
  dart run melos "${melos_args[@]}"
  git log -1 --pretty=%s | grep -q '^chore(release)' ||
    die 'melos made no release commit, so there is nothing to tag'

  version=$(workspace_version)
  tag="v$version"
  git tag -a "$tag" -m "Silo v$version"
  echo "Tagged $tag."
fi
version="${tag#v}"
[ "$version" = "$(workspace_version)" ] ||
  die "$tag does not match the workspace version $(workspace_version)"

# ── Push ─────────────────────────────────────────────────────────────────────
if git ls-remote --exit-code --tags origin "refs/tags/$tag" > /dev/null; then
  echo "$tag is already on origin; skipping the push."
else
  step "Push main and $tag"
  git log --oneline origin/main..HEAD
  confirm "Push these commits and $tag to origin? This starts the release." ||
    die "not pushed; run this script again to resume"
  # The package tags (silo_core-v…) go too: melos reads them to find where the
  # next release starts, in every clone, not just this one. They go first and
  # $tag on its own, because GitHub raises no push event for any tag when more
  # than three are pushed at once — and that event is what starts the release.
  # Tag names hold no spaces, so the unquoted expansion splits them cleanly
  # (and macOS's bash 3.2 has no mapfile).
  # shellcheck disable=SC2046
  git push --atomic origin main $(git tag --points-at HEAD | grep -vxF "$tag" |
    sed 's#^#refs/tags/#')
  git push origin "refs/tags/$tag"
fi

# ── Wait for the Release workflow ────────────────────────────────────────────
step "Wait for the Release workflow on $tag"
run_id=$(find_run)
if [ -z "$run_id" ]; then
  # The push raised no event (see above), so start the run on the tag directly;
  # the workflow treats a run on a v* ref as a release either way.
  echo "No run started for $tag; dispatching one."
  gh workflow run release.yml --ref "$tag"
  run_id=$(find_run)
fi
[ -n "$run_id" ] || die "no Release workflow run appeared for $tag"
gh run watch "$run_id" --exit-status --interval 30 ||
  die "the Release workflow failed; once fixed: gh run rerun $run_id --failed"

# ── Verify the release ───────────────────────────────────────────────────────
step "Verify the $tag release"
expected=(
  "silo-$version-macos-arm64.tar.gz"
  "silo-$version-macos-x86_64.tar.gz"
  "Silo-$version-macOS.dmg"
  'SHA256SUMS.txt'
)
assets=$(gh release view "$tag" --json assets --jq '.assets[].name')
for name in "${expected[@]}"; do
  grep -qxF "$name" <<< "$assets" || die "the release is missing $name"
  echo "  $name"
done
gh release view "$tag" --json url --jq '"Released: " + .url'

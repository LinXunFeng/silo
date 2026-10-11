# Agent notes

## Releasing

When asked to "create a tag and release" (创建 tag 和 release, 发版, cut a
release), run:

```bash
dart run melos run release -- --yes
```

That one request is the go-ahead for everything the script does, the push
included; do not stop to ask again. `scripts/release.sh` then:

1. Checks that the tree is clean, on `main` and not behind `origin/main`, and
   that `gh` is logged in.
2. Runs `melos run analyze` and `melos run test`.
3. Runs `melos version --all`. The bump and `CHANGELOG.md` come from the
   conventional commits since the last release, and melos makes the
   `chore(release)` commit and the per-package tags (`silo_core-v…`).
4. Tags that commit `v<version>`.
5. Pushes `main` and the package tags, then `v<version>` on its own. GitHub
   raises no tag event when more than three tags are pushed at once, and
   that event is what starts the release. If no run starts anyway, the
   script dispatches one on the tag.
6. Waits for `.github/workflows/release.yml`. That workflow builds the CLI
   tarballs (arm64 and x86_64) and the DMG, creates the GitHub release with
   them and `SHA256SUMS.txt`, and bumps the Homebrew tap.
7. Checks that the release has all four assets and prints its URL.

Rules:

- Never build or upload artifacts by hand, and never `gh release create`
  locally. The workflow is the only publisher, because it is also what keeps
  the Homebrew tap in step.
- Never pick the version or create the tag by hand. The release workflow refuses a
  `v*` tag that disagrees with the workspace version.
- Commit pending work first, using conventional commits, because the version
  bump and the changelog are read from them. The script refuses a dirty tree.
- If the script stops part way, fix the cause and run the same command again.
  Every stage it already finished is skipped.
- If the workflow fails, read its log (`gh run view <id> --log-failed`), fix
  the cause, then `gh run rerun <id> --failed` and run the script again to
  verify. Do not delete or move a tag that has already been pushed without
  asking first.
- Report the release URL and the version when done.

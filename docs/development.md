# Development

## Architecture

```
Source                    Engine                    Target
──────────────────        ──────────────────        ──────────────────
HuggingFace               range requests            LM Studio / Draw Things
hf-mirror                 parallel chunks           llama.cpp
ModelScope                resume via sidecar        Ollama
(custom endpoints)        SHA-256 verification      ComfyUI / HF cache
                          rate limiting
```

The engine in the middle knows nothing about models. It moves bytes from a URL
into a file. Sources and targets are plugins on either side, so adding a mirror
never means touching a target, and adding a tool never means touching the
downloader.

The library is a content-addressed store. Each file is kept once under its
SHA-256 and hard-linked into every tool that wants it: same inode, no extra
space, and each tool still sees an ordinary file. Both hubs publish the same
digest for the same file, which is what lets a download switch mirrors part
way and still verify.

```
packages/core    engine, sources, store, targets — zero runtime dependencies
packages/cli     the `silo` command
apps/silo        Flutter macOS app
```

`silo_core` deliberately has no package dependencies: `dart:io` and a hand-rolled
streaming SHA-256, pinned against NIST vectors and the system `shasum`.

## Building from source

```bash
dart pub get
dart compile exe packages/cli/bin/silo.dart -o ~/bin/silo
```

`melos run analyze` and `melos run test` are exactly what CI runs, so they are
the two commands worth running before pushing.

## Releasing

Version numbers come out of the commit history, so commits follow
[Conventional Commits](https://conventionalcommits.org). One product, one
number: `silo_core`, `silo_cli` and the app are versioned in lockstep.

```bash
dart run melos run release   # add -- --yes to skip the confirmations
```

`scripts/release.sh` checks the tree, runs analyze and test, runs
`melos version --all` (bump, changelogs, `chore(release)` commit, package tags),
tags the commit `v<version>`, pushes, then waits for the release workflow and
checks its assets. Each stage is skipped when already done, so a run that
stopped part way is resumed by running it again.

```
Local                                    GitHub Actions
─────────────────────────────────        ─────────────────────────────────
conventional commits
        │
        ▼
melos run release
  ├ melos version --all            one version across all three packages,
  │                                dependents' constraints move with it
  ├ CHANGELOG × 4                  one per package, plus the root summary
  ├ chore(release) commit
  ├ git tag v<version>
  └ push main, then the tag ─────▶  on: push tags ['v*']
                                           │
                                       check      analyze + test
                                           │
                                       meta       version read off the tag,
                                           │      checked against the pubspec
                                ┌──────────┴──────────┐
                              cli                    app
                       arm64 + x86_64          flutter build macos
                       → a tar.gz each         → hdiutil → DMG
                                └──────────┬──────────┘
                                        release
                                SHA256SUMS + gh release create
                                           │
                                         tap        checksums →
                                                    LinXunFeng/homebrew-tap,
                                                    which opens its own bump PR
```

The workflow is the only publisher. The two CLI tarballs, the DMG, the
checksums, the release itself and the Homebrew bump all come from it, never
from a local build.

A CLI tarball per architecture rather than one universal binary: `dart compile
exe` appends the AOT snapshot past the end of the Mach-O, and `lipo` copies only
the Mach-O, so a lipo'd `silo` starts up as the bare Dart VM.

The `tap` job needs `TAP_APP_ID` and `TAP_APP_PRIVATE_KEY` — a GitHub App with
contents and pull-request write on the tap. `GITHUB_TOKEN` cannot reach another
repository.

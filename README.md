# Silo

A local model library for macOS. **Download once, link everywhere.**

Running LM Studio, Ollama and llama.cpp side by side means storing the same 7B
model three times — 15 GB to hold 5 GB of weights. Silo keeps one physical copy
in a content-addressed store and hard-links it into each tool's directory. Every
tool sees an ordinary file; the disk gives up the space once.

Downloading fast from China is the reason this started, but it is not what the
project is. Silo is a library manager that happens to have a good downloader.

## Status

Working end to end from both the command line and the macOS app. Only LM Studio
is supported as a destination so far.

| Layer | State |
|---|---|
| Chunked download engine (ranges, resume, verify, throttle) | done |
| Sources: hf-mirror, ModelScope, HuggingFace | done |
| Content-addressed store + hard-link distribution | done |
| Target: LM Studio | done |
| Serial download queue (CLI + app) | done |
| CLI (`silo`) | done |
| macOS app: search, queue, download, link | done |
| Targets: Ollama, llama.cpp, ComfyUI, HF cache | not started |

## Architecture

```
Source                    Engine                    Target
──────────────────        ──────────────────        ──────────────────
HuggingFace               range requests            LM Studio
hf-mirror                 parallel chunks           llama.cpp
ModelScope                resume via sidecar        Ollama
(custom endpoints)        SHA-256 verification      ComfyUI / HF cache
                          rate limiting
```

The engine in the middle knows nothing about models. It moves bytes from a URL
into a file. Sources and targets are plugins on either side, so adding a mirror
never means touching a target, and adding a tool never means touching the
downloader.

```
packages/silo_core   engine, sources, store, targets — zero runtime dependencies
packages/silo_cli    the `silo` command
apps/silo_app        Flutter macOS app
```

`silo_core` deliberately has no package dependencies: `dart:io` and a hand-rolled
streaming SHA-256, pinned against NIST vectors and the system `shasum`.

## Usage

```bash
dart pub get
dart compile exe packages/silo_cli/bin/silo.dart -o ~/bin/silo
```

```bash
# What does this repo offer, and which mirrors carry it?
silo inspect Qwen/Qwen2.5-0.5B-Instruct-GGUF

# Which mirror is actually fastest right now?
silo sources --probe Qwen/Qwen2.5-0.5B-Instruct-GGUF

# Pull it in (defaults to Q4_K_M) and hard-link it into LM Studio.
# Several models queue up and run one at a time.
silo add Qwen/Qwen2.5-0.5B-Instruct-GGUF Qwen/Qwen2.5-1.5B-Instruct-GGUF

# Ctrl-C is safe: the queue and the partial bytes both survive
silo queue --resume

# What is in the library, and what did dedup save?
silo ls

# What do my tools already have?
silo scan

# Take a model out of a tool but keep it in the store
silo unlink Qwen/Qwen2.5-0.5B-Instruct-GGUF --from lmstudio

# Forget a model (unlinks it too), then reclaim the space
silo rm Qwen/Qwen2.5-0.5B-Instruct-GGUF
silo gc
```

The macOS app does the same things with a window: look up a model, pick a
variant, watch the queue, pause and reorder it, and see what each install
actually cost.

Useful global flags: `-j` connections (default 8), `--limit 5M` to throttle,
`--source modelscope` to pin a mirror, `--store` to relocate the library.

## Things that turned out to matter

Notes from building this, because each one is a silent failure rather than an
error message.

- **`X-Linked-Etag` is the file's SHA-256, and it only appears on the 302.**
  Following the redirect automatically throws the digest away — the `ETag` on
  the CDN response is a different hash entirely. The probe walks redirects by
  hand to catch it.
- **ModelScope answers `HEAD` with 404.** Size has to be probed with a `GET` and
  a one-byte range, reading the total out of `Content-Range`.
- **Transparent decompression corrupts ranged downloads,** so the shared client
  runs with `autoUncompress = false` — which then breaks JSON listings, because
  HuggingFace gzips its tree API and ModelScope does not. The source layer
  inflates listing bodies itself.
- **Both hubs publish the same SHA-256** for the same file, which is what makes
  failing over mid-download between mirrors safe.
- **HuggingFace's top-level `oid` is a git SHA-1**, not a content hash. Only
  `lfs.oid` is usable for verification.
- **The fastest mirror is not the one you would guess.** On the machine this was
  built on, ModelScope measured 8× faster than hf-mirror. Silo samples real
  bytes before choosing rather than trusting configuration order.
- **LM Studio's layout is exactly `models/{author}/{repo}/{file}`.** One level
  off and the model does not appear, with nothing logged to say why.
- **Sharded models must be downloaded as a set,** and vision models need their
  `mmproj-*.gguf` companion. Both are grouped into a single selectable variant.
- **`dart:io` has no hard-link API** — `Link` is `symlink(2)`. Silo shells out to
  `ln` and falls back to copying across volumes.
- **Deleting a blob a tool still hard-links frees nothing.** The inode survives
  through the other link and the file keeps working where it was linked, so
  `gc` reports freed and retained bytes separately, and `rm` unlinks first —
  otherwise the space could never actually come back.
- **Downloading two models at once is slower than doing them in turn.** They
  split the same pipe, and mirrors throttle per client. The queue is serial on
  purpose.
- **The App Sandbox hides the real home directory.** A sandboxed `$HOME` points
  into the app's container, so the app can neither see `~/.lmstudio` nor
  hard-link into it. It is off, which rules out the Mac App Store.

## License

Not yet chosen. Intended to be open source.

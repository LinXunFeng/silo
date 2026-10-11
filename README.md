<p align="center">
  <img src="assets/logo.png" alt="Silo" width="160" />
</p>

<h1 align="center">Silo</h1>

<p align="center">
  <b>A local model library for macOS. Download once, link everywhere.</b>
</p>

<p align="center">
  <a href="https://github.com/LinXunFeng/"><img src="https://img.shields.io/badge/author-LinXunFeng-blue.svg?style=flat-square&logo=Iconify" alt="author"></a>
  <a href="https://github.com/LinXunFeng/silo/releases/latest"><img src="https://img.shields.io/github/v/release/LinXunFeng/silo?style=flat-square&logo=github" alt="release"></a>
  <a href="https://github.com/LinXunFeng/silo"><img src="https://img.shields.io/github/stars/LinXunFeng/silo?style=flat-square&logo=github" alt="stars"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey?style=flat-square&logo=apple" alt="platform">
</p>

Language: English | [中文](README-zh.md)

Every local AI app keeps its own folder of models, so the same model ends up on
disk once per app. Silo keeps **one copy** of each model and links it into
every tool that uses it, so a 5 GB model takes 5 GB however many tools use it.

It also makes getting models painless: one search box across HuggingFace and
its mirrors, the fastest mirror picked for you, and downloads that survive a
dropped connection.

## ☕ Support me

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/T6T4JKVRP) [![wechat](https://img.shields.io/static/v1?label=WeChat&message=WeChat&nbsp;Pay&color=brightgreen&style=for-the-badge&logo=WeChat)](https://cdn.jsdelivr.net/gh/FullStackAction/PicBed@resource20220417121922/image/202303181116760.jpeg) [![github](https://img.shields.io/static/v1?label=GitHub&message=Sponsor&color=ea4aaa&style=for-the-badge&logo=githubsponsors)](https://github.com/sponsors/LinXunFeng)

Chat: [Join WeChat group](https://mp.weixin.qq.com/s/JBbMstn0qW6M71hh-BRKzw)

## 📸 Screenshots

<table>
  <tr>
    <td width="33%"><img src="assets/screenshots/discover.png" alt="Discover" /></td>
    <td width="33%"><img src="assets/screenshots/variants.png" alt="Variants" /></td>
    <td width="33%"><img src="assets/screenshots/library.png" alt="Library" /></td>
  </tr>
  <tr>
    <td align="center"><b>Discover</b><br/>Search every source at once</td>
    <td align="center"><b>Variants</b><br/>Every quant of a model, with its size</td>
    <td align="center"><b>Library</b><br/>What you have, where it's linked, space saved</td>
  </tr>
</table>

## ✨ Features

- 💾 **One copy, every tool.** Each model is stored once and shared with every
  tool that uses it. No duplicates, and the tools don't know the difference.
- 🔍 **One search box.** Search HuggingFace and ModelScope at once,
  or paste an exact `author/repo` to see every quant with its size.
- ⚡ **The fastest mirror, measured.** Silo tests the mirrors before
  downloading and moves to another one if a download fails.
- 🔁 **Downloads that don't give up.** Pause, quit or reboot and pick up where
  you left off. Every file is checked when it finishes.
- 🧩 **Models stay whole.** Split weights and the extra files a vision model
  needs show up as one item.
- 🖥 **App and command line.** A native macOS app and a `silo` command that
  share the same library.

## 🎀 Supported

| Download from | Link into |
| --- | --- |
| ✅ HuggingFace | ✅ LM Studio |
| ✅ hf-mirror | ✅ Draw Things |
| ✅ ModelScope | 🚧 Ollama |
| ✅ Custom endpoints | 🚧 llama.cpp |
| | 🚧 ComfyUI |
| | 🚧 HuggingFace cache (transformers / vLLM) |

## 📦 Install

With [Homebrew](https://brew.sh):

```bash
brew tap linxunfeng/tap
brew install --cask linxunfeng/tap/silo   # the app
brew install linxunfeng/tap/silo          # the command line
```

<details>
<summary>Manual download</summary>

Get the `.dmg` (app) or the `.tar.gz` for your architecture (command line,
`uname -m` tells you which) from
[Releases](https://github.com/LinXunFeng/silo/releases/latest).

The builds are not notarised, so macOS blocks the first launch. Clear the
quarantine flag once:

```bash
# App: drag Silo into Applications first
xattr -dr com.apple.quarantine /Applications/Silo.app

# Command line
tar -xzf silo-*-macos-$(uname -m).tar.gz
xattr -d com.apple.quarantine silo 2>/dev/null || true
mv silo ~/bin/silo   # or anywhere on your PATH
```

Homebrew does this for you.

</details>

## 🚀 Quick start

**The app:** switch on the tools you use under Targets, then search for a
model by keyword or `author/repo`, pick a variant and download. It is linked
into those tools as soon as it lands.

**The command line:**

```bash
silo search qwen3 coder                      # find a model
silo add Qwen/Qwen2.5-0.5B-Instruct-GGUF     # download it and link it into LM Studio
silo ls                                      # see your library and the space saved
```

<details>
<summary>More commands</summary>

```bash
silo inspect <author/repo>              # list the variants a repo offers
silo inspect <author/repo> --files      # list every file in it, with its size
silo add <repo> --file <path>           # download just one file, e.g. one checkpoint
silo sources --probe <author/repo>      # see which mirror is fastest right now
silo add <repo> <repo> ...              # queue several, downloaded one at a time
silo queue --resume                     # carry on after Ctrl-C
silo add <repo> --to drawthings         # send an image model or LoRA to Draw Things
silo scan                               # list the models your tools already have
silo unlink <repo> --from lmstudio      # remove from a tool, keep it in the library
silo rm <repo>                          # remove from the library
silo gc                                 # free the space
```

Global flags: `-j 8` connections, `--limit 5M` speed cap, `--source modelscope`
to pin a mirror, `--store <dir>` to move the library. Run `silo help` for the
full list.

</details>

## 🛠 Development

Architecture, building from source and releasing:
[docs/development.md](docs/development.md).

## 📄 License

[Apache License 2.0](LICENSE) © 2026 LinXunFeng

## 🖨 About Me

- GitHub: [https://github.com/LinXunFeng](https://github.com/LinXunFeng)
- Email: [linxunfeng@yeah.net](mailto:linxunfeng@yeah.net)
- Blogs: 
  - 全栈行动: [https://fullstackaction.com](https://fullstackaction.com)
  - 掘金: [https://juejin.cn/user/1820446984512392](https://juejin.cn/user/1820446984512392) 

<img height="267.5" width="481.5" src="https://github.com/LinXunFeng/LinXunFeng/raw/master/static/img/FSAQR.png"/>

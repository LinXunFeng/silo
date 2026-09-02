<p align="center">
  <img src="assets/logo.png" alt="Silo" width="160" />
</p>

<h1 align="center">Silo</h1>

<p align="center">
  <a href="https://github.com/LinXunFeng/"><img src="https://img.shields.io/badge/author-LinXunFeng-blue.svg?style=flat-square&logo=Iconify" alt="author"></a>
  <a href="https://github.com/LinXunFeng/silo/releases/latest"><img src="https://img.shields.io/github/v/release/LinXunFeng/silo?style=flat-square&logo=github" alt="release"></a>
  <a href="https://github.com/LinXunFeng/silo"><img src="https://img.shields.io/github/stars/LinXunFeng/silo?style=flat-square&logo=github" alt="stars"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey?style=flat-square&logo=apple" alt="platform">
</p>

语言: 中文 | [English](README.md)

macOS 上的本地模型库。**下载一次，处处链接。**

LM Studio、Ollama、llama.cpp 装在同一台机器上，同一个 7B 模型就得存三份——15 GB
的空间装 5 GB 的权重。Silo 把实体只留一份在内容寻址的仓库里，再硬链接进各个工具
的目录。每个工具看到的都是一个普通文件，而磁盘只付一次钱。

这个项目是因为在国内下载慢才动手的，但它不是一个下载器。Silo 是一个模型库管理器，
只是顺带把下载做好了。

## 📸 截图

<table>
  <tr>
    <td width="33%"><img src="assets/screenshots/discover.png" alt="发现 —— 一个搜索框搜遍所有源" /></td>
    <td width="33%"><img src="assets/screenshots/variants.png" alt="变体 —— 一个仓库的所有量化版本" /></td>
    <td width="33%"><img src="assets/screenshots/library.png" alt="模型库 —— 只存一份，硬链接进每个工具" /></td>
  </tr>
  <tr>
    <td align="center">一个搜索框一次搜遍所有源，GGUF 和 MLX 构建捞到前面，而不是埋在底下。</td>
    <td align="center">粘贴精确的 <code>author/repo</code>，所有量化版本连同体积一并列出，分片会归成一个。</td>
    <td align="center">磁盘上有什么、被链接进了哪些工具、去重又省下了多少。</td>
  </tr>
</table>

## ☕ 请我喝一杯咖啡

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/T6T4JKVRP) [![wechat](https://img.shields.io/static/v1?label=WeChat&message=WeChat&nbsp;Pay&color=brightgreen&style=for-the-badge&logo=WeChat)](https://cdn.jsdelivr.net/gh/FullStackAction/PicBed@resource20220417121922/image/202303181116760.jpeg)

## 🔨 功能点

- [x] **磁盘上只存一份。** 内容寻址的仓库存下实体，再硬链接进每个需要它的工具——
      同一个 inode，不占额外空间，各工具读到的仍然是普通文件。
- [x] **为慢网络写的下载器。** Range 分片并发、重启和关机后都能续传、SHA-256
      校验、限速。
- [x] **镜像之间能故障转移。** 同一个文件在两个 hub 上公布的摘要是一致的，所以
      下载中途换镜像仍然校验得过。
- [x] **实测出最快的镜像。** 不是按配置顺序猜，而是先采样真实字节再决定。
- [x] **一个搜索框搜遍所有源。** 关键字一次搜全部源，并把 GGUF 和 MLX 构建捞到
      前面，而不是埋在底下。
- [x] **分片模型不会被拆散。** 多分片权重和视觉模型需要的 `mmproj-*.gguf` 会归成
      一个可选条目。
- [x] **串行队列。** 同时下两个模型比一个个下更慢，所以队列一次只跑一个——而且
      Ctrl-C 之后还在。
- [x] **窗口和终端都有。** macOS 应用和 `silo` 命令共用同一套引擎、同一个库。

## 🎀 支持

**源**

- [x] HuggingFace
- [x] hf-mirror
- [x] ModelScope
- [x] 自定义端点

**落盘目标**

- [x] LM Studio
- [ ] Ollama
- [ ] llama.cpp
- [ ] ComfyUI
- [ ] HuggingFace 缓存 (transformers / vLLM)

## 📦 安装

### 应用

到 [Releases](https://github.com/LinXunFeng/silo/releases/latest) 下载 `.dmg`，
把 Silo 拖进「应用程序」。

产物没有签名也没有公证，首次打开会被 Gatekeeper 拦下，去掉隔离属性即可：

```bash
xattr -dr com.apple.quarantine /Applications/Silo.app
```

### 命令行

在同一个 release 里下载 `silo-<version>-macos-universal.tar.gz`：

```bash
tar -xzf silo-*-macos-universal.tar.gz
xattr -d com.apple.quarantine silo 2>/dev/null || true
mv silo ~/bin/silo
```

或者从源码编译：

```bash
dart pub get
dart compile exe packages/cli/bin/silo.dart -o ~/bin/silo
```

## 🚀 使用

下面这些事，应用用窗口也都能做。它只有一个搜索框，关键字和精确的 `author/repo`
都收——前者给你一列可以点进去的结果，后者直接进变体列表。

```bash
# 不知道准确的 id？一次搜遍所有源。
# 默认只显示 GGUF 和 MLX 仓库，要看其余的加 --all。
silo search qwen3 coder

# 这个仓库有哪些东西，哪些镜像有它？
silo inspect Qwen/Qwen2.5-0.5B-Instruct-GGUF

# 此刻哪个镜像真的最快？
silo sources --probe Qwen/Qwen2.5-0.5B-Instruct-GGUF

# 拉进库（默认 Q4_K_M）并硬链接进 LM Studio。
# 可以一次给多个，它们会排队，一次跑一个。
silo add Qwen/Qwen2.5-0.5B-Instruct-GGUF Qwen/Qwen2.5-1.5B-Instruct-GGUF

# Ctrl-C 是安全的：队列和已下载的字节都还在
silo queue --resume

# 库里有什么，去重省下了多少？
silo ls

# 我的工具里已经有哪些模型了？
silo scan

# 把模型从某个工具里撤掉，但仍留在库里
silo unlink Qwen/Qwen2.5-0.5B-Instruct-GGUF --from lmstudio

# 从库里移除（同时解除链接），再回收空间
silo rm Qwen/Qwen2.5-0.5B-Instruct-GGUF
silo gc
```

常用全局参数：`-j` 连接数（默认 8）、`--limit 5M` 限速、`--source modelscope`
指定镜像、`--store` 换个位置放库。

## 🧱 架构

```
源 (Source)               引擎 (Engine)             目标 (Target)
──────────────────        ──────────────────        ──────────────────
HuggingFace               Range 请求                LM Studio
hf-mirror                 并发分片                  llama.cpp
ModelScope                旁车文件续传              Ollama
(自定义端点)               SHA-256 校验              ComfyUI / HF 缓存
                          限速
```

中间的引擎对模型一无所知，它只负责把字节从一个 URL 搬进一个文件。源和目标都是它
两侧的插件，所以加一个镜像不用碰任何目标，加一个工具也不用碰下载器。

```
packages/core    引擎、源、仓库、目标 —— 零运行时依赖
packages/cli     silo 命令
apps/silo        Flutter macOS 应用
```

`silo_core` 刻意不带任何包依赖：只用 `dart:io`，SHA-256 是手写的流式实现，拿
NIST 测试向量和系统的 `shasum` 对过。

## 🚢 发版

版本号是从提交历史算出来的，所以提交遵循
[Conventional Commits](https://conventionalcommits.org)。一个产品一个号：
`silo_core`、`silo_cli` 和应用同步版本。

```bash
dart run melos run release   # 升版本、写 changelog、打 v<version> 标签
git push --follow-tags       # 标签才是构建 DMG 和发布的触发点
```

```
本地                                     GitHub Actions
─────────────────────────────────        ─────────────────────────────────
写 conventional commits
        │
        ▼
melos run release
  ├ melos version --all            三个包同步到同一个版本号，
  │                                依赖方的约束跟着改
  ├ CHANGELOG × 4                  每包一份，外加根目录的汇总
  ├ chore(release) commit
  └ git tag v0.1.1
        │
        ▼
git push --follow-tags ──────────▶  on: push tags ['v*']
                                           │
                                       check      analyze + test
                                           │
                                       meta       从 tag 取版本号，
                                           │      再和 pubspec 核对
                                ┌──────────┴──────────┐
                              cli                    app
                       arm64 + x86_64          flutter build macos
                       → lipo → tar.gz         → hdiutil → DMG
                                └──────────┬──────────┘
                                        release
                                SHA256SUMS + gh release create
```

melos 到打出 tag 为止就收工了。之后的事——通用二进制、DMG、校验和、发布本身
——全归 workflow。

`melos run analyze` 和 `melos run test` 就是 CI 跑的那两条，推之前值得先跑一遍。

## 📄 开源协议

尚未选定，计划开源。

## 🖨 关于我

- GitHub: [https://github.com/LinXunFeng](https://github.com/LinXunFeng)
- Email: [linxunfeng@yeah.net](mailto:linxunfeng@yeah.net)
- 博客: 
  - 全栈行动: [https://fullstackaction.com](https://fullstackaction.com)
  - 掘金: [https://juejin.cn/user/1820446984512392](https://juejin.cn/user/1820446984512392) 

<img height="267.5" width="481.5" src="https://github.com/LinXunFeng/LinXunFeng/raw/master/static/img/FSAQR.png"/>

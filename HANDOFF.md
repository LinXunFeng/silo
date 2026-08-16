# Silo — 上下文移交

> 本文件是项目立项前的讨论记录，由上一个会话整理移交。代码尚未开始写。

## 一、起因

LM Studio 从 `huggingface.co` 下载模型在国内极慢。现有的绕行办法：

1. 手动用 `hf-mirror` / ModelScope / `aria2c -x 16` 下载 GGUF，再按 `~/.lmstudio/models/{author}/{repo}/{file}` 两级目录丢进去
2. 从终端带 `HTTPS_PROXY` 环境变量启动 LM Studio，让应用内下载走代理
3. LM Studio 设置里的 HuggingFace 代理开关（不同版本叫法不一，效果不稳定）

这些都是绕行，不是解决。于是有了做成 App 的想法。

## 二、产品定位

**不是「LM Studio 下载加速器」，是「本地模型管理器」。**

LM Studio 只是众多落盘目标中的一个。一台机器上同时装 LM Studio、Ollama、llama.cpp 是常态，同一个 7B 模型存三份就是 15G 起——去重才是真正的价值点。

## 三、三层架构

```
源 (Source)          →  下载引擎 (Core)      →  落盘目标 (Target)
─────────────────       ─────────────────       ─────────────────
HuggingFace 官方         文件树解析              LM Studio
hf-mirror 镜像           分片 Range 下载         Ollama
ModelScope 魔搭          断点续传                llama.cpp / 任意路径
自定义镜像/代理           并发调度                ComfyUI / SD WebUI
                        sha256 校验             HF 缓存 (transformers/vLLM)
```

中间的下载引擎是纯粹的多线程下载器，与模型、与工具都无关。**Source 和 Target 都是插件，从第一天就要分开写。**

```dart
abstract class DownloadTarget {
  Future<void> install(File file, ModelMeta meta);
}
```

先只实现 LM Studio 一个 target 跑通，后面加 target 是纯增量的事，不用返工。

## 四、源接口

```
# HuggingFace 文件树
GET https://hf-mirror.com/api/models/{repo}/tree/main?recursive=true
# 下载
GET https://hf-mirror.com/{repo}/resolve/main/{file}

# ModelScope 文件树
GET https://www.modelscope.cn/api/v1/models/{repo}/repo/files
# 下载
GET https://www.modelscope.cn/api/v1/models/{repo}/repo?FilePath={file}&Revision=master
```

两个源文件名基本一致，可以做成「同一个模型对象 + 多个下载源」，哪个快用哪个，失败自动切换。

## 五、落盘规则

| 目标 | 规则 | 复杂度 |
|---|---|---|
| LM Studio | `~/.lmstudio/models/{author}/{repo}/{file}` | 直接复制 |
| llama.cpp | 任意路径，`-m` 指过去 | 直接复制 |
| ComfyUI | `ComfyUI/models/{checkpoints,loras,vae,unet,clip}/` | 按类型分目录 |
| SD WebUI | `models/{Stable-diffusion,Lora,VAE}/` | 同上 |
| Ollama | blob 存储，不认裸 GGUF | 需生成 Modelfile 后 `ollama create` |
| transformers / vLLM | `~/.cache/huggingface/hub/models--{org}--{name}/` | 需还原 blobs/snapshots/refs 结构 |

**Ollama** 用 `~/.ollama/models/blobs/sha256-xxx` + manifests，导入方式：

```bash
echo "FROM ./qwen2.5-7b-instruct-q4_k_m.gguf" > Modelfile
ollama create qwen2.5-7b -f Modelfile
```

App 自动生成 Modelfile 并执行即可。

**HF 缓存**结构：`blobs/` 存实体、`snapshots/{commit}/` 放软链接、`refs/main` 记 commit hash。写对了 transformers / vLLM 直接 `from_pretrained` 命中缓存，错一点就会重下。

## 六、核心差异化：统一模型库 + 硬链接分发

文件只存一份在自己的仓库目录，往各工具目录建硬链接（同分区零成本、零额外空间，各工具当普通文件读）：

```
~/Silo/blobs/qwen2.5-7b-q4_k_m.gguf   ← 唯一实体
   ├─ hardlink → ~/.lmstudio/models/Qwen/Qwen2.5-7B-Instruct-GGUF/...
   └─ hardlink → ~/llama.cpp/models/...
```

Ollama 因为是 blob 机制没法直接链，但它内部本来就做了去重。

## 七、技术选型

**Flutter macOS 桌面端**：

- 下载核心用 Dart 自己写：`HttpClient` + `Range` 头分片，`RandomAccessFile.setPositionSync` 按偏移写入同一文件。**不引 aria2c**，省掉打包二进制和 RPC 那一层
- 进度、限速、暂停恢复都是自己可控的状态，GetX 管理
- 分片状态存 `.part.json` 旁车文件，重启后能续

## 八、必须处理的坑

- **多分片模型**：大模型拆成 `xxx-00001-of-00003.gguf`，必须整组下完，UI 上合并成一个条目，别让用户只勾一个
- **mmproj 文件**：视觉模型需要额外的 `mmproj-*.gguf`，漏了加载不了，要自动带上
- **目录层级**：LM Studio 必须是 `models/{author}/{repo}/{file}`，少一级多一级都扫不到
- **校验**：HF 响应头带 `X-Linked-Etag`（文件 sha256），下完比对，避免半损文件让加载崩溃
- **限速**：hf-mirror 并发 >16 容易被限流反而更慢，默认 8～16
- **别并发下多个模型**：会互相抢带宽，串行更快

## 九、可以更进一步

- 扫描已有的 `~/.lmstudio/models`，标记「已下载」，避免重复
- 按机器显存/内存推荐合适的量化等级（日常 Q4_K_M，体积约为 F16 的 1/4）
- 接管 LM Studio 自己的下载队列（记录在 `~/.lmstudio` 下）

## 十、命名

候选过 Trove / Silo / Ferry / Hoard / Yard，避开了 `modelhub`（撞 HF Model Hub）、带 `gguf` 的（会被锁死在 GGUF，后面要支持 safetensors）、`depot` 和 `quay`（已被现有产品占用）。

**最终定名 Silo**——筒仓、存储，语义落在「库房」而非「下载器」，4 个字母好敲。

CLI 动词建议贴合「一份实体多处引用」的机制：

```bash
silo add Qwen/Qwen2.5-7B-Instruct-GGUF     # 拉进库
silo link qwen2.5-7b --to lmstudio,ollama  # 分发（硬链接）
silo ls                                     # 看库存
silo gc                                     # 清理没人引用的 blob
```

## 十一、建议的第一步

先写**纯 Dart 的下载核心 + LM Studio target**，命令行跑通分片、续传、校验、落盘，验证通过再套 Flutter 界面。风险最低的部分先落地。

尚未与用户确认的：是否先做 CLI、Flutter 版本与依赖、是否要开源、界面形态。**动手前先确认。**

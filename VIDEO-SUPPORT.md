# OpenCode 视频多模态支持改造

> 让 AI 编程助手原生支持视频文件输入，使多模态大模型能够直接"看到"并理解视频内容。

## 背景

OpenCode 原生支持图片（jpeg/png/gif/webp）和 PDF 作为文件附件传给多模态模型，但**不支持视频文件**。视频文件在 `read` 工具中被判定为 binary 而报错。

然而，越来越多的多模态模型（如 Xiaomi MiMo、Google Gemini）已经原生支持视频理解。本改造打通了从"读取本地视频文件"到"发送给多模态模型 API"的完整链路。

## 改造内容

### 改动的文件（4个）

| 文件 | 改动说明 |
|------|---------|
| `packages/opencode/src/util/media.ts` | 新增 `isVideoAttachment()` 函数 + 视频 magic bytes 检测（mp4/webm/mov/avi/mkv） |
| `packages/opencode/src/tool/read.ts` | `read` 工具识别视频文件，转 base64 附件返回（50MB 上限） |
| `packages/llm/src/protocols/openai-chat.ts` | 协议层新增 `video_url` 内容类型，`lowerMedia` 函数将视频转为 `video_url` |
| `packages/opencode/src/session/llm/native-runtime.ts` | 门卫放行 OpenAI-compatible provider（如 MiMo）使用 native runtime |

### 数据流

```
用户让 agent 读取视频文件
  ↓
read.ts: sniffAttachmentMime() 识别为 video/mp4
  ↓ isVideoAttachment() → true
  ↓ 读取文件 → base64 data URL → 返回附件
  ↓
transform.ts: unsupportedParts() 检查 model.capabilities.input["video"]
  ↓ (需在配置中声明 modalities)
  ↓
Native Runtime 路径:
  ↓ ProviderTransform.message() 处理消息
  ↓ openai-chat.ts: lowerMedia() → { type: "video_url", video_url: { url: "data:video/mp4;base64,..." } }
  ↓
HTTP 请求 → MiMo / Gemini 等支持 video_url 的 API
  ↓
模型返回视频理解结果
```

### 为什么 opencode 原本不支持视频

opencode 内部其实已有视频的"半成品"基础设施：
- `shared.ts` 中定义了 `VIDEO_MIMES = ["video/mp4", "video/webm", "video/quicktime"]`
- `transform.ts` 的 `mimeToModality()` 已能返回 `"video"`

但从未连通：
1. `read.ts` 不读视频文件（只认 image/PDF）
2. AI SDK（Vercel）的 `@ai-sdk/openai-compatible` 只转 `image_url`，无 `video_url`
3. Claude/GPT 的 API 本身没有 `video_url` 内容类型

本改造连通了第 1 和第 3 点（通过 Native Runtime 绕过第 2 点）。

## 如何使用

### 前置条件
- 支持视频输入的多模态模型（如 Xiaomi MiMo `mimo-v2-omni`、Google Gemini）
- 不会被 Claude/GPT 支持（它们的 API 没有 `video_url`）

### 启用步骤

1. **开启 Native Runtime**（绕过 AI SDK 的 image-only 限制）：
   ```bash
   export OPENCODE_EXPERIMENTAL_NATIVE_LLM=true
   ```

2. **声明模型支持 video 模态**（在 `opencode.json` 中）：
   ```jsonc
   {
     "provider": {
       "xiaomi-token-plan-cn": {
         "models": {
           "mimo-v2-omni": {
             "modalities": {
               "input": ["text", "image", "video"],
               "output": ["text"]
             }
           }
         }
       }
     }
   }
   ```

3. **从源码运行**：
   ```bash
   bun install
   OPENCODE_EXPERIMENTAL_NATIVE_LLM=true bun run --cwd packages/opencode src/index.ts run "分析视频文件 path/to/video.mp4" --model xiaomi-token-plan-cn/mimo-v2-omni
   ```

### 限制
- 视频文件上限：50MB（base64 编码后）
- 支持格式：mp4、webm、mov、avi、mkv、mpeg
- 仅在 Native Runtime 路径下有效（AI SDK 路径的 `@ai-sdk/openai-compatible` 尚未 patch）
- TUI 模式在 Windows 上可能因 Bun 的 `opentui.dll` bug 崩溃，CLI 模式正常

## 已完成

- [x] `media.ts`：视频 MIME 类型识别 + magic bytes 检测
- [x] `read.ts`：视频文件读取 → base64 附件
- [x] `openai-chat.ts`：协议层 `video_url` 转换
- [x] `native-runtime.ts`：门卫放行 OpenAI-compatible provider
- [x] CLI 模式端到端测试通过（MiMo mimo-v2-omni + test_video.mp4）

## 进行中

- [ ] TUI 模式 Windows 崩溃修复（Bun `opentui.dll` segfault）
- [ ] 模型 modalities 配置标准化
- [ ] `read.txt` 工具描述更新（加入视频说明）

## 未来计划

- [ ] **AI SDK 路径 patch**：给 `@ai-sdk/openai-compatible` 打补丁，让默认运行时也支持 `video_url`，无需开启 experimental native runtime
- [ ] **音频支持**：同样的改造模式扩展到音频文件（`shared.ts` 已定义 `AUDIO_MIMES`）
- [ ] **视频压缩预处理**：超 50MB 的视频自动用 ffmpeg 压缩/截取后再发送
- [ ] **批量视频分析管线**：结合 ffmpeg 镜头切分 + 并发 API 调用，实现自动视频剪辑
- [ ] **多模态主导架构**：当多模态模型推理能力成熟后，直接用多模态模型作为主模型（而非文字模型 + 视觉辅助）
- [ ] **向 opencode 上游提交 PR**

## 架构思考

### 三种视频处理架构对比

| 架构 | 导演是谁 | 能看到画面 | 信息损失 |
|------|---------|-----------|---------|
| 文字模型主导 + 视觉辅助 | 文字模型（"盲"） | 多模态（当眼睛） | 高（文字描述有损） |
| 工具调用（如 Hermes video_analyze） | 主模型 | 独立 vision 调用 | 中（仍需文字中转） |
| **原生多模态主导**（本改造方向） | 多模态模型自己 | 自己直接看 | **无** |

本改造的核心理念：**让视频成为模型上下文的一等公民**，与文字、图片平级。当多模态模型推理能力足够强时，直接用多模态模型作为主模型，无需任何中间的文字翻译。

## 上游仓库

- [anomalyco/opencode](https://github.com/anomalyco/opencode) - 原始仓库
- [XiaomiMiMo/MiMo-Code](https://github.com/XiaomiMiMo/MiMo-Code) - 小米 fork（配套改造）
- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) - 有原生 `video_analyze` 工具的参考实现

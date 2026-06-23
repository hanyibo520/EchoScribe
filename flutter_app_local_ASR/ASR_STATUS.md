# ASR 当前状态记录

日期：2026-06-23

## 当前稳定模型

当前本地 ASR 稳定链路使用 Sherpa-ONNX SenseVoice 标准模型：

- Profile：`sensevoice_standard`
- 模型文件：`assets/models/asr/sensevoice/model.int8.onnx`
- Tokens：`assets/models/asr/sensevoice/tokens.txt`
- VAD 模型：`assets/models/asr/silero_vad.onnx`
- 推理 Provider：CPU
- 上传音频预处理：`preprocessMode=none`

代码已经支持可选的上传音频 fast profile：`sensevoice_fast`，但当前 fast 模型文件尚未放入项目：

- `assets/models/asr/sensevoice_fast/model.int8.onnx`
- `assets/models/asr/sensevoice_fast/tokens.txt`

在 fast 模型文件提供并校验通过之前，上传音频继续使用 `sensevoice_standard` 作为稳定 ASR 模型。

## 切片策略

上传音频使用固定窗口切片识别：

- 固定 ASR 窗口：`30s`
- 重叠时长：`2s`
- 实际步进：`28s`
- VAD fallback 窗口：`25s`

示例：

- 第 1 段：`0s-30s`
- 第 2 段：`28s-58s`
- 第 3 段：`56s-86s`

2 秒 overlap 会在文本合并时做去重，用于减少切片边界处的漏字风险。

对于超长音频，仍然保持 30 秒切片，但会使用流式串行路径，避免一次性在内存中生成全部 Float32 chunk。

## 当前稳定基线耗时

目前继续使用 `sensevoice_standard` 作为稳定版本。

已观测稳定基线：

- 13 分钟音频样本：
  - 音频时长：约 `813s` / `13分33秒`
  - 导入 + ASR 总耗时：约 `65s`
  - ASR fixed decode 耗时：约 `61s`
  - Workers：`3`
  - 质量评分正常：`lowQuality=false`

- 2小时44分音频样本：
  - 音频时长：约 `9866s` / `2小时44分26秒`
  - 音频解码耗时：约 `31s`
  - ASR fixed decode 耗时：约 `22分钟`
  - Workers：`1`，使用长音频内存安全模式
  - 质量评分正常：`lowQuality=false`

结论：当前 standard 本地 ASR 链路稳定可用。它比云端 ASR 慢，主要原因是本地运行在 iPhone CPU 上，而云端通常使用 GPU 或服务端大规模并行推理。

## Moonshine Tiny Streaming 接入状态

英文实时 ASR 已新增 Moonshine Tiny Streaming 作为 live fallback 链路第一优先级：

- 模型目录：`assets/models/asr/moonshine_tiny_streaming_en/`
- 需要文件：
  - `adapter.ort`
  - `cross_kv.ort`
  - `decoder_kv.ort`
  - `decoder_kv_with_attention.ort`
  - `encoder.ort`
  - `frontend.ort`
  - `streaming_config.json`
  - `tokenizer.bin`
- Android runtime：`ai.moonshine:moonshine-voice:0.0.62`
- 当前 Android 限制：Moonshine AAR 声明 `minSdk=35`，项目仍保持 `minSdk=26`；低于 Android 15 / API 35 时 Moonshine 会返回不可用并回退到 SenseVoice。
- iOS runtime：Runner 已接入 SwiftPM `https://github.com/moonshine-ai/moonshine-swift.git`，product 为 `MoonshineVoice`，版本固定 `0.0.62`；`AppDelegate.swift` 已调用 `MicTranscriber(modelArch: .tinyStreaming)`。当前命令环境无法解析 GitHub 依赖时，需要在 Xcode 中完成 package resolve，或提供 `moonshine-swift` 本地源码包。

通过以下命令获取 Moonshine 真正权重文件：

```sh
dart run tool/download_moonshine_tiny_streaming.dart
```

`dart run tool/verify_offline_bundle.dart` 会检查这些文件是否齐全；缺失时只以 warning 形式提示，不阻塞现有离线包。

## 后续 Fast 模型 Benchmark 目标

当拿到兼容的 `sensevoice_fast` 模型后：

1. 将文件放入 `assets/models/asr/sensevoice_fast/`。
2. 运行 `dart run tool/verify_offline_bundle.dart`。
3. 导入同一段 13 分钟音频样本。
4. 对比以下日志指标：
   - `asrProfile`
   - `fixedDecode`
   - `workers`
   - `fixedCandidate lowQuality`
   - `chars`

目标：

- 将 13 分钟样本从当前约 `65s` 总耗时压到约 `30s-40s`。
- 如果 fast 结果为空或质量较低，应用会自动回退到 `sensevoice_standard`。

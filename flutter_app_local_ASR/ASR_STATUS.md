# ASR 当前状态记录

日期：2026-06-23

## 当前主 ASR 选择

模型 Tab 已支持在两个本地主 ASR 模型之间切换：

- `Moonshine`
- `Sherpa`

选择会同时影响两条路径：

- 本地实时录音 ASR：只启用当前选中的 live engine。
- 导入音频 ASR：只使用当前选中的文件转写链路。

也就是说，模型页选 `Moonshine` 时，录音和导入都走 Moonshine；选 `Sherpa` 时，录音和导入都走 Sherpa/SenseVoice。当前不再让 UI 选中一个模型、实际转写却自动跑另一个主模型。

## Moonshine Tiny Streaming

定位：速度优先、英文优先的本地 ASR。

当前接入状态：

- 模型目录：`assets/models/asr/moonshine_tiny_streaming_en/`
- iOS runtime：SwiftPM `moonshine-swift`，product `MoonshineVoice`，版本 `0.0.62`
- live 录音：`MicTranscriber(modelArch: .tinyStreaming)`
- 导入音频：iOS 原生 `Transcriber(modelArch: .tinyStreaming)`，完整音频单次识别

必需文件：

- `adapter.ort`
- `cross_kv.ort`
- `decoder_kv.ort`
- `decoder_kv_with_attention.ort`
- `encoder.ort`
- `frontend.ort`
- `streaming_config.json`
- `tokenizer.bin`

已观测导入音频表现：

- 13 分钟样本，约 `813s`
- 完整识别耗时：约 `53s`
- 输出规模：约 `100` 段 / `4313` 字符
- RTF：约 `0.066`

加速实验结论：

- `speedFactor=1.3` 可降到约 `30s`，但结果降到约 `51` 段 / `1737` 字符，漏字过多，不适合作为默认。
- `speedFactor=1.1` 会触发 fallback 双跑，总耗时约 `96s`，不划算。
- 切片并行虽然可到约 `12s`，但只输出 `1` 段，破坏分段/VAD 上下文，已放弃。

当前结论：

- Moonshine 默认使用完整音频单次识别，优先保证结果完整。
- 适合英文较多、速度优先的对外本地 ASR。
- 对中文会议内容可用性需要继续实测，不能只看耗时。

## Sherpa-ONNX SenseVoice

定位：稳定优先、中文会议内容更稳的本地 ASR。

当前接入状态：

- live 录音：`SherpaSenseVoiceAsrService`
- 导入音频：`SenseVoiceFileTranscriber`
- 标准模型目录：`assets/models/asr/sensevoice/`
- fast 模型目录：`assets/models/asr/sensevoice_fast/`
- VAD 模型：`assets/models/asr/silero_vad.onnx`
- 推理 Provider：CPU

标准模型文件：

- `assets/models/asr/sensevoice/model.int8.onnx`
- `assets/models/asr/sensevoice/tokens.txt`

fast 模型文件：

- `assets/models/asr/sensevoice_fast/model.int8.onnx`
- `assets/models/asr/sensevoice_fast/tokens.txt`

导入音频策略：

- 优先使用可用的 SenseVoice file transcription profile。
- 支持 fast 与 standard profile。
- 使用 Sherpa/SenseVoice 路径时，导入音频会先解码为 `16k PCM16`，再进入本地识别。

历史稳定基线：

- 13 分钟样本：
  - 总耗时曾约 `65s`
  - 质量评分正常：`lowQuality=false`
- 2小时44分样本：
  - 音频解码约 `31s`
  - ASR fixed decode 约 `22分钟`
  - 长音频走内存安全模式

当前结论：

- Sherpa/SenseVoice 是更稳的中文会议转写选择。
- 速度不一定优于 Moonshine，但结果完整性更可控。
- 适合准确率和中文内容完整度优先的场景。

## Sherpa-ONNX Speaker Processing

定位：在 ASR 之外补充人声分离与声纹向量能力。

当前接入状态：

- 人声分离服务：`SherpaSpeakerService.diarizePcm16Audio`
- 声纹向量服务：`SherpaSpeakerService.computeEmbeddingFromPcm16Audio`
- 首页/模型中心：已显示人声分离与声纹 embedding 状态，并支持添加打包模型
- 输入音频：`16k mono PCM16`

模型文件：

- `assets/models/speaker/diarization/pyannote_segmentation_3_0/model.onnx`
- `assets/models/speaker/embedding/3dspeaker_zh_cn_16k/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx`

说明：

- diarization 会输出 `speaker + start/end seconds`，用于判断谁在什么时候说话。
- speaker embedding 会输出 `Float32List` 向量，用于后续身份匹配或验证。
- 目前首页只负责模型状态与安装入口，录音/导入转写仍保持原 ASR 流程。

## 选择建议

推荐默认策略：

- 英文较多、速度优先：选 `Moonshine`
- 中文会议、准确率优先：选 `Sherpa`
- 对外演示或交付：优先看 `segments` 和 `chars`，不能只看 `totalMs`

关键日志：

```text
[ASR timing] native engine=Moonshine ...
flutter: [ASR timing] import engine=Moonshine ...
flutter: [ASR timing] import engine=SenseVoice ...
```

判断标准：

- `engine=Moonshine`：当前导入走 Moonshine。
- `engine=SenseVoice`：当前导入走 Sherpa/SenseVoice。
- `segments` 和 `chars` 明显偏低时，即使耗时很短，也视为结果不合格。

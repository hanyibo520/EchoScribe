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

This app uses an offline bundle mode: put already-downloaded model files here
before building the app. At first launch, the app copies these bundled files into
Application Support so ASR and LLM paths are available without network access.

Expected paths:

- assets/models/asr/sensevoice/model.int8.onnx
- assets/models/asr/sensevoice/tokens.txt
- assets/models/asr/sensevoice_fast/model.int8.onnx (optional faster file-import profile)
- assets/models/asr/sensevoice_fast/tokens.txt (optional faster file-import profile)
- assets/models/asr/moonshine_tiny_streaming_en/adapter.ort (optional preferred live English ASR)
- assets/models/asr/moonshine_tiny_streaming_en/cross_kv.ort
- assets/models/asr/moonshine_tiny_streaming_en/decoder_kv.ort
- assets/models/asr/moonshine_tiny_streaming_en/decoder_kv_with_attention.ort
- assets/models/asr/moonshine_tiny_streaming_en/encoder.ort
- assets/models/asr/moonshine_tiny_streaming_en/frontend.ort
- assets/models/asr/moonshine_tiny_streaming_en/streaming_config.json
- assets/models/asr/moonshine_tiny_streaming_en/tokenizer.bin
- assets/models/asr/silero_vad.onnx
- assets/models/speaker/diarization/pyannote_segmentation_3_0/model.onnx
- assets/models/speaker/embedding/3dspeaker_zh_cn_16k/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx
- assets/models/asr/whisper/ggml-base.bin
- assets/models/llm/qwen3-0.6b-q4.gguf

Before building, run:

```sh
dart run tool/download_moonshine_tiny_streaming.dart
dart run tool/verify_offline_bundle.dart
```

Runtime notes:

- Sherpa-ONNX native runtime is provided by the `sherpa_onnx` Flutter package.
- Sherpa speaker diarization uses a pyannote segmentation ONNX model plus the
  3D-Speaker embedding ONNX model. The embedding model is also reused for
  standalone speaker-vector extraction and identity matching.
- Moonshine Tiny Streaming is used as the preferred live English ASR when the
  optional `moonshine_tiny_streaming_en` files and native runtime are present.
  Use `dart run tool/download_moonshine_tiny_streaming.dart` to download these
  files from Moonshine's official model CDN. Do not use Git LFS pointer files as
  model assets; the verifier will report those as too small.
- C++ source files are not needed on device at runtime; compiled native libraries
  are needed instead.
- whisper.cpp and llama.cpp currently still require native bridge integration.
  Bundling their model files makes the model paths available, but execution will
  remain "bridge pending" until those native bridges are linked.

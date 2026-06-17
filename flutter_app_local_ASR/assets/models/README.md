This app uses an offline bundle mode: put already-downloaded model files here
before building the app. At first launch, the app copies these bundled files into
Application Support so ASR and LLM paths are available without network access.

Expected paths:

- assets/models/asr/sensevoice/model.int8.onnx
- assets/models/asr/sensevoice/tokens.txt
- assets/models/asr/sensevoice_fast/model.int8.onnx (optional faster file-import profile)
- assets/models/asr/sensevoice_fast/tokens.txt (optional faster file-import profile)
- assets/models/asr/silero_vad.onnx
- assets/models/asr/whisper/ggml-base.bin
- assets/models/llm/qwen3-0.6b-q4.gguf

Before building, run:

```sh
dart run tool/verify_offline_bundle.dart
```

Runtime notes:

- Sherpa-ONNX native runtime is provided by the `sherpa_onnx` Flutter package.
- C++ source files are not needed on device at runtime; compiled native libraries
  are needed instead.
- whisper.cpp and llama.cpp currently still require native bridge integration.
  Bundling their model files makes the model paths available, but execution will
  remain "bridge pending" until those native bridges are linked.

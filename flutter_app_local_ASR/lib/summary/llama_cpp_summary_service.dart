import 'dart:ffi';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../asr/model_store.dart';
import '../native/local_native_bridge.dart';
import 'meeting_summary_service.dart';
import 'qwen_summary_codec.dart';

class LlamaCppSummaryService implements MeetingSummaryService {
  LlamaCppSummaryService({
    required ModelStore modelStore,
    LocalNativeBridge? nativeBridge,
  }) : _modelStore = modelStore,
       _nativeBridge = nativeBridge ?? LocalNativeBridge.instance;

  final ModelStore _modelStore;
  final LocalNativeBridge _nativeBridge;
  LlamaEngine? _engine;

  @override
  String get name => 'llama.cpp Qwen GGUF';

  @override
  Future<SummaryAvailability> checkAvailability() async {
    final check = await _modelStore.inspect();
    if (!check.isLlamaModelReady) {
      return SummaryAvailability.unavailable(
        'Missing GGUF model: ${check.llamaModelPath}',
      );
    }

    if (Platform.isAndroid) {
      try {
        DynamicLibrary.open('libllama.so');
      } on ArgumentError catch (error) {
        return SummaryAvailability.unavailable(
          'llama.cpp Android runtime is not available: $error',
        );
      }
    } else {
      final bridge = await _nativeBridge.checkLlamaCpp(
        modelPath: check.llamaModelPath,
      );
      if (!bridge.isAvailable) {
        return SummaryAvailability.unavailable(bridge.reason);
      }
    }

    return const SummaryAvailability.available();
  }

  @override
  Future<MeetingSummary> summarize(
    String transcript, {
    required SummaryLanguage language,
    required SummaryTemplate summaryTemplate,
  }) async {
    final check = await _modelStore.inspect();
    final engine = await _ensureEngine(check.llamaModelPath);
    final session = await engine.createSession();
    final prompt = await buildQwenSummaryPrompt(
      transcript,
      language,
      summaryTemplate,
    );
    final buffer = StringBuffer();

    try {
      await for (final event in session.generate(
        prompt: prompt,
        addSpecial: true,
        parseSpecial: true,
        sampler: const SamplerParams(
          temperature: 0.2,
          topK: 20,
          topP: 0.8,
          repeatPenalty: 1.08,
        ),
        maxTokens: language == SummaryLanguage.zh ? 1800 : 520,
      )) {
        switch (event) {
          case TokenEvent():
            buffer.write(event.text);
          case DoneEvent():
            buffer.write(event.trailingText);
          case ShiftEvent():
            break;
        }
      }

      return parseQwenSummary(buffer.toString(), language, engineName: name);
    } finally {
      await session.dispose();
    }
  }

  Future<LlamaEngine> _ensureEngine(String modelPath) async {
    final current = _engine;
    if (current != null) {
      return current;
    }

    final modelParams = ModelParams(
      path: modelPath,
      gpuLayers: Platform.isAndroid ? 0 : 99,
    );
    final contextParams = const ContextParams(
      nCtx: 4096,
      nBatch: 512,
      nUbatch: 512,
    );
    final engine = Platform.isAndroid
        ? await LlamaEngine.spawn(
            libraryPath: 'libllama.so',
            modelParams: modelParams,
            contextParams: contextParams,
          )
        : await LlamaEngine.spawnFromProcess(
            modelParams: modelParams,
            contextParams: contextParams,
          );
    _engine = engine;
    return engine;
  }
}

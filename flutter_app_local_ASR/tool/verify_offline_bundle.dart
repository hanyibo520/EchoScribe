import 'dart:io';

const requiredModelFiles = <_RequiredModelFile>[
  _RequiredModelFile(
    label: 'SenseVoice ONNX model',
    path: 'assets/models/asr/sensevoice/model.int8.onnx',
    minBytes: 1024 * 1024,
  ),
  _RequiredModelFile(
    label: 'SenseVoice tokens',
    path: 'assets/models/asr/sensevoice/tokens.txt',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'Silero VAD ONNX model',
    path: 'assets/models/asr/silero_vad.onnx',
    minBytes: 512 * 1024,
  ),
  _RequiredModelFile(
    label: 'Whisper base model',
    path: 'assets/models/asr/whisper/ggml-base.bin',
    minBytes: 10 * 1024 * 1024,
  ),
  _RequiredModelFile(
    label: 'Qwen3 0.6B GGUF model',
    path: 'assets/models/llm/qwen3-0.6b-q4.gguf',
    minBytes: 10 * 1024 * 1024,
  ),
];

const optionalModelFiles = <_RequiredModelFile>[
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming adapter',
    path: 'assets/models/asr/moonshine_tiny_streaming_en/adapter.ort',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming cross KV',
    path: 'assets/models/asr/moonshine_tiny_streaming_en/cross_kv.ort',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming decoder KV',
    path: 'assets/models/asr/moonshine_tiny_streaming_en/decoder_kv.ort',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming decoder KV with attention',
    path:
        'assets/models/asr/moonshine_tiny_streaming_en/decoder_kv_with_attention.ort',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming encoder',
    path: 'assets/models/asr/moonshine_tiny_streaming_en/encoder.ort',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming frontend',
    path: 'assets/models/asr/moonshine_tiny_streaming_en/frontend.ort',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming config',
    path: 'assets/models/asr/moonshine_tiny_streaming_en/streaming_config.json',
    minBytes: 64,
  ),
  _RequiredModelFile(
    label: 'Moonshine Tiny Streaming tokenizer',
    path: 'assets/models/asr/moonshine_tiny_streaming_en/tokenizer.bin',
    minBytes: 1024,
  ),
  _RequiredModelFile(
    label: 'SenseVoice fast ONNX model',
    path: 'assets/models/asr/sensevoice_fast/model.int8.onnx',
    minBytes: 1024 * 1024,
  ),
  _RequiredModelFile(
    label: 'SenseVoice fast tokens',
    path: 'assets/models/asr/sensevoice_fast/tokens.txt',
    minBytes: 1024,
  ),
];

void main() {
  final problems = <String>[];
  final warnings = <String>[];

  for (final model in requiredModelFiles) {
    final problem = _verifyModelFile(model);
    if (problem != null) {
      problems.add(problem);
    }
  }

  for (final model in optionalModelFiles) {
    final problem = _verifyModelFile(model);
    if (problem != null) {
      warnings.add(problem);
    }
  }

  for (final warning in warnings) {
    stdout.writeln('WARN $warning');
  }
  if (_hasMoonshineWarnings(warnings)) {
    stdout.writeln(
      'Run `dart run tool/download_moonshine_tiny_streaming.dart` '
      'to download the optional Moonshine Tiny Streaming model files.',
    );
  }

  if (problems.isEmpty) {
    stdout.writeln('Offline model bundle is ready.');
    return;
  }

  stderr.writeln('Offline model bundle is incomplete:');
  for (final problem in problems) {
    stderr.writeln('- $problem');
  }
  exitCode = 1;
}

bool _hasMoonshineWarnings(List<String> warnings) {
  return warnings.any(
    (warning) => warning.contains('Moonshine Tiny Streaming'),
  );
}

String? _verifyModelFile(_RequiredModelFile model) {
  final file = File(model.path);
  if (!file.existsSync()) {
    return 'Missing ${model.label}: ${model.path}';
  }

  final bytes = file.lengthSync();
  if (bytes < model.minBytes) {
    return '${model.label} looks too small: ${model.path} '
        '(${_formatBytes(bytes)}, expected at least '
        '${_formatBytes(model.minBytes)})';
  }

  stdout.writeln('OK ${model.label}: ${model.path} (${_formatBytes(bytes)})');
  return null;
}

String _formatBytes(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  final precision = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

class _RequiredModelFile {
  const _RequiredModelFile({
    required this.label,
    required this.path,
    required this.minBytes,
  });

  final String label;
  final String path;
  final int minBytes;
}

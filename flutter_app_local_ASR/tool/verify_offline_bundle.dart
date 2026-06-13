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

void main() {
  final problems = <String>[];

  for (final model in requiredModelFiles) {
    final file = File(model.path);
    if (!file.existsSync()) {
      problems.add('Missing ${model.label}: ${model.path}');
      continue;
    }

    final bytes = file.lengthSync();
    if (bytes < model.minBytes) {
      problems.add(
        '${model.label} looks too small: ${model.path} '
        '(${_formatBytes(bytes)}, expected at least '
        '${_formatBytes(model.minBytes)})',
      );
      continue;
    }

    stdout.writeln('OK ${model.label}: ${model.path} (${_formatBytes(bytes)})');
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

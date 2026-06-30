import 'dart:async';
import 'dart:io';

const String _segmentationArchiveUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';
const String _embeddingModelUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';

const String _segmentationDirectory =
    'assets/models/speaker/diarization/pyannote_segmentation_3_0';
const String _embeddingDirectory =
    'assets/models/speaker/embedding/3dspeaker_zh_cn_16k';
const String _segmentationModelFile = 'model.onnx';
const String _embeddingModelFile =
    '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';
const int _minimumModelBytes = 1024 * 1024;
const Duration _downloadTimeout = Duration(minutes: 5);

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    await _ensureSegmentationModel(client, force: force);
    await _ensureEmbeddingModel(client, force: force);
  } finally {
    client.close(force: true);
  }

  stdout.writeln('Sherpa speaker diarization and embedding models are ready.');
}

Future<void> _ensureSegmentationModel(
  HttpClient client, {
  required bool force,
}) async {
  final destinationDirectory = Directory(_segmentationDirectory);
  final destination = File(
    '${destinationDirectory.path}/$_segmentationModelFile',
  );
  await destinationDirectory.create(recursive: true);
  if (!force && await _isUsable(destination, minBytes: _minimumModelBytes)) {
    stdout.writeln('OK $_segmentationModelFile already exists');
    return;
  }

  final workDirectory = await Directory.systemTemp.createTemp(
    'sherpa_speaker_segmentation_',
  );
  final archive = File('${workDirectory.path}/segmentation.tar.bz2');
  try {
    stdout.writeln('Downloading pyannote segmentation model archive');
    await _download(
      client,
      Uri.parse(_segmentationArchiveUrl),
      archive,
      minBytes: _minimumModelBytes,
    );

    final extractResult = await Process.run('tar', <String>[
      'xjf',
      archive.path,
      '-C',
      workDirectory.path,
    ]);
    if (extractResult.exitCode != 0) {
      throw StateError(
        'Failed to extract segmentation model archive: '
        '${extractResult.stderr}',
      );
    }

    final source = File(
      '${workDirectory.path}/sherpa-onnx-pyannote-segmentation-3-0/model.onnx',
    );
    if (!await _isUsable(source, minBytes: _minimumModelBytes)) {
      throw StateError('Extracted segmentation model is missing or too small');
    }

    await _replaceFile(source, destination);
    stdout.writeln(
      'OK ${destination.path} (${_formatBytes(await destination.length())})',
    );
  } finally {
    if (await workDirectory.exists()) {
      await workDirectory.delete(recursive: true);
    }
  }
}

Future<void> _ensureEmbeddingModel(
  HttpClient client, {
  required bool force,
}) async {
  final destinationDirectory = Directory(_embeddingDirectory);
  final destination = File('${destinationDirectory.path}/$_embeddingModelFile');
  await destinationDirectory.create(recursive: true);
  if (!force && await _isUsable(destination, minBytes: _minimumModelBytes)) {
    stdout.writeln('OK $_embeddingModelFile already exists');
    return;
  }

  stdout.writeln('Downloading 3D-Speaker embedding model');
  await _download(
    client,
    Uri.parse(_embeddingModelUrl),
    destination,
    minBytes: _minimumModelBytes,
  );
}

Future<void> _download(
  HttpClient client,
  Uri url,
  File destination, {
  required int minBytes,
}) async {
  final temp = File(
    '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.download',
  );
  if (await temp.exists()) {
    await temp.delete();
  }

  final request = await client.getUrl(url).timeout(_downloadTimeout);
  final response = await request.close().timeout(_downloadTimeout);
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('Failed to download $url: HTTP ${response.statusCode}');
  }

  final sink = temp.openWrite();
  try {
    await response.pipe(sink).timeout(_downloadTimeout);
  } finally {
    await sink.close();
  }

  final bytes = await temp.length();
  if (bytes < minBytes) {
    await temp.delete();
    throw StateError(
      '${destination.path} looks too small after download: $bytes bytes',
    );
  }

  await _replaceFile(temp, destination);
  stdout.writeln('OK ${destination.path} (${_formatBytes(bytes)})');
}

Future<void> _replaceFile(File source, File destination) async {
  if (await destination.exists()) {
    await destination.delete();
  }
  await source.copy(destination.path);
  await source.delete();
}

Future<bool> _isUsable(File file, {required int minBytes}) async {
  if (!await file.exists()) {
    return false;
  }
  return file.lengthSync() >= minBytes;
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

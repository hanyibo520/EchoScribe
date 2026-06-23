import 'dart:async';
import 'dart:io';

const String _baseUrl =
    'https://download.moonshine.ai/model/tiny-streaming-en/quantized';
const String _destinationDirectory =
    'assets/models/asr/moonshine_tiny_streaming_en';

const Map<String, int> _files = <String, int>{
  'adapter.ort': 1024,
  'cross_kv.ort': 1024,
  'decoder_kv.ort': 1024,
  'decoder_kv_with_attention.ort': 1024,
  'encoder.ort': 1024,
  'frontend.ort': 1024,
  'streaming_config.json': 64,
  'tokenizer.bin': 1024,
};

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final destination = Directory(_destinationDirectory);
  await destination.create(recursive: true);

  final client = HttpClient();
  try {
    for (final entry in _files.entries) {
      final file = File('${destination.path}/${entry.key}');
      if (!force && await _isUsable(file, minBytes: entry.value)) {
        stdout.writeln('OK ${entry.key} already exists');
        continue;
      }

      final url = Uri.parse('$_baseUrl/${entry.key}');
      stdout.writeln('Downloading ${entry.key}');
      await _download(client, url, file, minBytes: entry.value);
    }
  } finally {
    client.close(force: true);
  }

  stdout.writeln('Moonshine Tiny Streaming model files are ready.');
}

Future<void> _download(
  HttpClient client,
  Uri url,
  File destination, {
  required int minBytes,
}) async {
  final temp = File('${destination.path}.download');
  if (await temp.exists()) {
    await temp.delete();
  }

  final request = await client.getUrl(url);
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('Failed to download $url: HTTP ${response.statusCode}');
  }

  final sink = temp.openWrite();
  try {
    await response.pipe(sink);
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

  if (await destination.exists()) {
    await destination.delete();
  }
  await temp.rename(destination.path);
  stdout.writeln('OK ${destination.path} (${_formatBytes(bytes)})');
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

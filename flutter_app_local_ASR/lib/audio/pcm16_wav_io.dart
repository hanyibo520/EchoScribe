import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class Pcm16AudioFile {
  const Pcm16AudioFile({
    required this.path,
    required this.sampleRate,
    required this.durationMs,
    required this.byteLength,
  });

  final String path;
  final int sampleRate;
  final int durationMs;
  final int byteLength;
}

class Pcm16AudioData {
  const Pcm16AudioData({
    required this.pcm16Audio,
    required this.sampleRate,
    required this.durationMs,
  });

  final Uint8List pcm16Audio;
  final int sampleRate;
  final int durationMs;
}

class Pcm16WavFileWriter {
  Pcm16WavFileWriter._({
    required this.file,
    required RandomAccessFile handle,
    required this.sampleRate,
  }) : _handle = handle;

  static Future<Pcm16WavFileWriter> create({
    required String path,
    required int sampleRate,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final handle = file.openSync(mode: FileMode.write);
    handle.writeFromSync(_wavHeader(sampleRate: sampleRate, dataBytes: 0));
    return Pcm16WavFileWriter._(
      file: file,
      handle: handle,
      sampleRate: sampleRate,
    );
  }

  final File file;
  final int sampleRate;
  RandomAccessFile? _handle;
  int _dataBytes = 0;

  int get dataBytes => _dataBytes;
  int get durationMs => pcm16DurationMs(_dataBytes, sampleRate);

  void append(Uint8List pcm16Bytes) {
    if (pcm16Bytes.isEmpty) {
      return;
    }
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final evenLength = pcm16Bytes.length - (pcm16Bytes.length % 2);
    if (evenLength == 0) {
      return;
    }
    handle.writeFromSync(pcm16Bytes, 0, evenLength);
    _dataBytes += evenLength;
  }

  Future<Pcm16AudioFile?> close() async {
    final handle = _handle;
    if (handle == null) {
      return null;
    }
    _handle = null;
    handle.setPositionSync(0);
    handle.writeFromSync(
      _wavHeader(sampleRate: sampleRate, dataBytes: _dataBytes),
    );
    await handle.close();
    if (_dataBytes == 0) {
      await file.delete();
      return null;
    }
    return Pcm16AudioFile(
      path: file.path,
      sampleRate: sampleRate,
      durationMs: durationMs,
      byteLength: _dataBytes,
    );
  }
}

Future<Pcm16AudioFile> savePcm16WavFile({
  required String path,
  required Uint8List pcm16Audio,
  required int sampleRate,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final evenLength = pcm16Audio.length - (pcm16Audio.length % 2);
  final dataBytes = evenLength < 0 ? 0 : evenLength;
  final sink = file.openWrite();
  try {
    sink.add(_wavHeader(sampleRate: sampleRate, dataBytes: dataBytes));
    if (dataBytes > 0) {
      sink.add(Uint8List.sublistView(pcm16Audio, 0, dataBytes));
    }
  } finally {
    await sink.close();
  }

  return Pcm16AudioFile(
    path: path,
    sampleRate: sampleRate,
    durationMs: pcm16DurationMs(dataBytes, sampleRate),
    byteLength: dataBytes,
  );
}

Future<Pcm16AudioData> readPcm16WavFile(String path) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.length < 44) {
    throw StateError('WAV file is too small: $path');
  }
  final data = ByteData.sublistView(bytes);
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final wave = String.fromCharCodes(bytes.sublist(8, 12));
  if (riff != 'RIFF' || wave != 'WAVE') {
    throw StateError('Unsupported WAV file: $path');
  }
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  if (channels != 1 || bitsPerSample != 16) {
    throw StateError('Expected mono PCM16 WAV: $path');
  }

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final dataStart = offset + 8;
    final dataEnd = math.min(dataStart + chunkSize, bytes.length);
    if (chunkId == 'data') {
      final pcm = Uint8List.sublistView(bytes, dataStart, dataEnd);
      return Pcm16AudioData(
        pcm16Audio: pcm,
        sampleRate: sampleRate,
        durationMs: pcm16DurationMs(pcm.length, sampleRate),
      );
    }
    offset = dataStart + chunkSize + (chunkSize % 2);
  }
  throw StateError('WAV data chunk was not found: $path');
}

Uint8List slicePcm16Audio({
  required Uint8List pcm16Audio,
  required int sampleRate,
  required int startMs,
  required int endMs,
}) {
  final startSample = (startMs * sampleRate / 1000).floor();
  final endSample = (endMs * sampleRate / 1000).ceil();
  final startByte = (startSample * 2).clamp(0, pcm16Audio.length);
  final endByte = (endSample * 2).clamp(startByte, pcm16Audio.length);
  return Uint8List.sublistView(pcm16Audio, startByte, endByte);
}

Uint8List concatPcm16Audio(Iterable<Uint8List> chunks) {
  final builder = BytesBuilder(copy: false);
  for (final chunk in chunks) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

int pcm16DurationMs(int byteLength, int sampleRate) {
  if (sampleRate <= 0 || byteLength <= 0) {
    return 0;
  }
  return (byteLength / 2 / sampleRate * 1000).round();
}

Uint8List _wavHeader({required int sampleRate, required int dataBytes}) {
  final header = Uint8List(44);
  final data = ByteData.sublistView(header);
  _writeAscii(header, 0, 'RIFF');
  data.setUint32(4, 36 + dataBytes, Endian.little);
  _writeAscii(header, 8, 'WAVE');
  _writeAscii(header, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  _writeAscii(header, 36, 'data');
  data.setUint32(40, dataBytes, Endian.little);
  return header;
}

void _writeAscii(Uint8List buffer, int offset, String value) {
  for (var i = 0; i < value.length; i += 1) {
    buffer[offset + i] = value.codeUnitAt(i);
  }
}

import 'dart:typed_data';

Float32List pcm16BytesToFloat32(
  Uint8List bytes, [
  Endian endian = Endian.little,
]) {
  final values = Float32List(bytes.length ~/ 2);
  final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);

  for (var i = 0; i < bytes.length; i += 2) {
    values[i ~/ 2] = data.getInt16(i, endian) / 32768.0;
  }

  return values;
}

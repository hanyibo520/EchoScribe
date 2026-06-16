import 'dart:math' as math;
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

class Float32RingBuffer {
  Float32RingBuffer({required int capacity})
    : assert(capacity > 0),
      _values = Float32List(capacity);

  final Float32List _values;
  int _start = 0;
  int _length = 0;

  int get capacity => _values.length;
  int get length => _length;

  void clear() {
    _start = 0;
    _length = 0;
  }

  void push(Float32List samples) {
    if (samples.isEmpty) {
      return;
    }

    if (samples.length >= capacity) {
      _values.setRange(0, capacity, samples, samples.length - capacity);
      _start = 0;
      _length = capacity;
      return;
    }

    final overflow = _length + samples.length - capacity;
    if (overflow > 0) {
      _start = (_start + overflow) % capacity;
      _length -= overflow;
    }

    final writeIndex = (_start + _length) % capacity;
    final firstCount = math.min(samples.length, capacity - writeIndex);
    _values.setRange(writeIndex, writeIndex + firstCount, samples);

    final remaining = samples.length - firstCount;
    if (remaining > 0) {
      _values.setRange(0, remaining, samples, firstCount);
    }

    _length += samples.length;
  }

  Float32List toFloat32List() {
    final result = Float32List(_length);
    if (_length == 0) {
      return result;
    }

    final firstCount = math.min(_length, capacity - _start);
    result.setRange(0, firstCount, _values, _start);

    final remaining = _length - firstCount;
    if (remaining > 0) {
      result.setRange(firstCount, _length, _values);
    }

    return result;
  }
}

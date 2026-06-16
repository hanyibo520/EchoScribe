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

Float32List conditionSpeechSamples(
  Float32List samples, {
  required int sampleRate,
  double targetPeak = 0.92,
  double maxGain = 6.0,
}) {
  if (samples.isEmpty) {
    return samples;
  }

  final conditioned = _removeDcOffset(samples);
  _applyHighPassFilter(conditioned, sampleRate: sampleRate);
  _attenuateLowEnergyNoise(conditioned, sampleRate: sampleRate);
  return _normalizePeak(conditioned, targetPeak: targetPeak, maxGain: maxGain);
}

Float32List _removeDcOffset(Float32List samples) {
  var sum = 0.0;
  for (final sample in samples) {
    sum += sample;
  }

  final mean = sum / samples.length;
  if (mean.abs() < 0.0001) {
    return Float32List.fromList(samples);
  }

  final output = Float32List(samples.length);
  for (var i = 0; i < samples.length; i += 1) {
    output[i] = (samples[i] - mean).clamp(-1.0, 1.0).toDouble();
  }
  return output;
}

void _applyHighPassFilter(Float32List samples, {required int sampleRate}) {
  if (samples.length < 2 || sampleRate <= 0) {
    return;
  }

  const cutoffHz = 80.0;
  final rc = 1.0 / (2.0 * math.pi * cutoffHz);
  final dt = 1.0 / sampleRate;
  final alpha = rc / (rc + dt);
  var previousInput = samples.first;
  var previousOutput = 0.0;

  for (var i = 1; i < samples.length; i += 1) {
    final currentInput = samples[i];
    final output = alpha * (previousOutput + currentInput - previousInput);
    samples[i] = output.clamp(-1.0, 1.0).toDouble();
    previousInput = currentInput;
    previousOutput = output;
  }
  samples[0] = 0.0;
}

void _attenuateLowEnergyNoise(Float32List samples, {required int sampleRate}) {
  final frameSize = math.max(160, sampleRate ~/ 50);
  if (samples.length < frameSize * 5) {
    return;
  }

  final frameRms = <double>[];
  for (var start = 0; start < samples.length; start += frameSize) {
    final end = math.min(start + frameSize, samples.length);
    var energy = 0.0;
    for (var i = start; i < end; i += 1) {
      energy += samples[i] * samples[i];
    }
    frameRms.add(math.sqrt(energy / (end - start)));
  }

  final nonSilent = frameRms.where((rms) => rms > 0.0001).toList()..sort();
  if (nonSilent.length < 3) {
    return;
  }

  final noiseFloor = nonSilent[(nonSilent.length * 0.2).floor()];
  if (noiseFloor < 0.001) {
    return;
  }

  final threshold = math.max(noiseFloor * 1.8, 0.004);
  for (var frame = 0; frame < frameRms.length; frame += 1) {
    final rms = frameRms[frame];
    if (rms >= threshold) {
      continue;
    }

    final ratio = (rms / threshold).clamp(0.0, 1.0).toDouble();
    final gain = 0.45 + ratio * 0.55;
    final start = frame * frameSize;
    final end = math.min(start + frameSize, samples.length);
    for (var i = start; i < end; i += 1) {
      samples[i] *= gain;
    }
  }
}

Float32List _normalizePeak(
  Float32List samples, {
  required double targetPeak,
  required double maxGain,
}) {
  var peak = 0.0;
  for (final sample in samples) {
    peak = math.max(peak, sample.abs());
  }
  if (peak <= 0.0) {
    return samples;
  }

  final gain = math.min(targetPeak / peak, maxGain);
  if (gain <= 1.0) {
    return samples;
  }

  final normalized = Float32List(samples.length);
  for (var i = 0; i < samples.length; i += 1) {
    normalized[i] = (samples[i] * gain).clamp(-1.0, 1.0).toDouble();
  }
  return normalized;
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

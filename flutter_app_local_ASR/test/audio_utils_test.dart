import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/asr/audio_utils.dart';

void main() {
  test('Float32RingBuffer keeps samples in append order before capacity', () {
    final buffer = Float32RingBuffer(capacity: 5);

    buffer.push(Float32List.fromList(<double>[1, 2]));
    buffer.push(Float32List.fromList(<double>[3]));

    expect(buffer.length, 3);
    expect(buffer.toFloat32List(), <double>[1, 2, 3]);
  });

  test('Float32RingBuffer drops oldest samples when capacity is exceeded', () {
    final buffer = Float32RingBuffer(capacity: 4);

    buffer.push(Float32List.fromList(<double>[1, 2, 3]));
    buffer.push(Float32List.fromList(<double>[4, 5, 6]));

    expect(buffer.length, 4);
    expect(buffer.toFloat32List(), <double>[3, 4, 5, 6]);
  });

  test('Float32RingBuffer handles wrapped writes', () {
    final buffer = Float32RingBuffer(capacity: 5);

    buffer.push(Float32List.fromList(<double>[1, 2, 3, 4]));
    buffer.push(Float32List.fromList(<double>[5, 6]));
    buffer.push(Float32List.fromList(<double>[7]));

    expect(buffer.toFloat32List(), <double>[3, 4, 5, 6, 7]);
  });

  test('conditionSpeechSamples removes DC offset', () {
    final samples = Float32List.fromList(
      List<double>.generate(1600, (index) => index.isEven ? 0.25 : 0.15),
    );

    final conditioned = conditionSpeechSamples(samples, sampleRate: 16000);

    expect(_mean(conditioned).abs(), lessThan(0.01));
  });

  test('conditionSpeechSamples attenuates low-energy noise conservatively', () {
    final samples = Float32List(16000);
    for (var i = 0; i < 8000; i += 1) {
      samples[i] = 0.015;
    }
    for (var i = 8000; i < samples.length; i += 1) {
      samples[i] = math.sin(i / 16.0) * 0.25;
    }

    final beforeNoise = _rms(samples, 0, 8000);
    final beforeSpeech = _rms(samples, 8000, samples.length);
    final conditioned = conditionSpeechSamples(
      samples,
      sampleRate: 16000,
      targetPeak: 0.25,
      maxGain: 1,
    );

    expect(_rms(conditioned, 0, 8000), lessThan(beforeNoise));
    expect(
      _rms(conditioned, 8000, conditioned.length),
      greaterThan(beforeSpeech * 0.5),
    );
  });
}

double _mean(Float32List samples) {
  var sum = 0.0;
  for (final sample in samples) {
    sum += sample;
  }
  return sum / samples.length;
}

double _rms(Float32List samples, int start, int end) {
  var energy = 0.0;
  for (var i = start; i < end; i += 1) {
    energy += samples[i] * samples[i];
  }
  return math.sqrt(energy / (end - start));
}

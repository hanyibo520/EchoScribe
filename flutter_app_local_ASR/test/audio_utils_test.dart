import 'dart:typed_data';

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
}

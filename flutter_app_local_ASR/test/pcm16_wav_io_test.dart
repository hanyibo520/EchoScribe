import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/audio/pcm16_wav_io.dart';

void main() {
  test('savePcm16WavFile writes a readable mono PCM16 wav', () async {
    final directory = await Directory.systemTemp.createTemp('pcm16_wav_test_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final pcm = Uint8List.fromList(<int>[
      0x00,
      0x00,
      0x01,
      0x00,
      0xff,
      0x7f,
      0x00,
      0x80,
    ]);
    final saved = await savePcm16WavFile(
      path: '${directory.path}/sample.wav',
      pcm16Audio: pcm,
      sampleRate: 16000,
    );

    final decoded = await readPcm16WavFile(saved.path);

    expect(saved.byteLength, pcm.length);
    expect(saved.durationMs, 0);
    expect(decoded.sampleRate, 16000);
    expect(decoded.pcm16Audio, pcm);
  });

  test('slicePcm16Audio and concatPcm16Audio preserve sample boundaries', () {
    final pcm = Uint8List.fromList(List<int>.generate(20, (index) => index));

    final first = slicePcm16Audio(
      pcm16Audio: pcm,
      sampleRate: 1000,
      startMs: 1,
      endMs: 4,
    );
    final second = slicePcm16Audio(
      pcm16Audio: pcm,
      sampleRate: 1000,
      startMs: 4,
      endMs: 6,
    );
    final joined = concatPcm16Audio(<Uint8List>[first, second]);

    expect(first, Uint8List.fromList(<int>[2, 3, 4, 5, 6, 7]));
    expect(second, Uint8List.fromList(<int>[8, 9, 10, 11]));
    expect(joined, Uint8List.fromList(<int>[2, 3, 4, 5, 6, 7, 8, 9, 10, 11]));
  });
}

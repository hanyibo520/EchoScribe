import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/asr/sense_voice_file_transcriber.dart';

void main() {
  test('fixedOverlapChunks keeps a two second overlap between windows', () {
    const sampleRate = 16000;
    final samples = Float32List.fromList(
      List<double>.generate(sampleRate * 60, (index) => index.toDouble()),
    );

    final chunks = fixedOverlapChunks(samples);

    expect(chunks, hasLength(3));
    expect(chunks[0].length, sampleRate * 30);
    expect(chunks[1].length, sampleRate * 30);
    expect(chunks[2].length, sampleRate * 4);
    expect(chunks[0][sampleRate * 28], chunks[1].first);
    expect(chunks[0].last, chunks[1][sampleRate * 2 - 1]);
  });

  test('trimRepeatedPrefix removes duplicated overlap text', () {
    final trimmed = trimRepeatedPrefix(
      previous: '我们先讨论预算部分希望他尽快出方案',
      current: '尽快出方案然后正式移到那边去',
    );

    expect(trimmed, '然后正式移到那边去');
  });

  test(
    'mergeIndexedTranscripts restores order and trims worker boundary overlap',
    () {
      final texts = mergeIndexedTranscripts(const <IndexedTranscript>[
        IndexedTranscript(index: 2, text: '我们继续讨论下一项'),
        IndexedTranscript(index: 0, text: '我们先讨论预算部分希望他尽快出方案'),
        IndexedTranscript(index: 1, text: '尽快出方案然后正式移到那边去'),
      ], trimOverlaps: true);

      expect(texts, const <String>[
        '我们先讨论预算部分希望他尽快出方案',
        '然后正式移到那边去',
        '我们继续讨论下一项',
      ]);
    },
  );

  test('selectFixedDecodeWorkerCount keeps short and non-iOS files serial', () {
    expect(
      selectFixedDecodeWorkerCount(
        chunkCount: 5,
        processorCount: 8,
        isIOS: true,
      ),
      1,
    );
    expect(
      selectFixedDecodeWorkerCount(
        chunkCount: 6,
        processorCount: 8,
        isIOS: false,
      ),
      1,
    );
  });

  test(
    'selectFixedDecodeWorkerCount enables two workers for long iOS files',
    () {
      expect(
        selectFixedDecodeWorkerCount(
          chunkCount: 6,
          processorCount: 4,
          isIOS: true,
        ),
        2,
      );
      expect(
        selectFixedDecodeWorkerCount(
          chunkCount: 6,
          processorCount: 3,
          isIOS: true,
        ),
        1,
      );
    },
  );

  test('selectFixedDecodeProvider prefers CoreML only on iOS', () {
    expect(selectFixedDecodeProvider(isIOS: true), 'coreml');
    expect(selectFixedDecodeProvider(isIOS: false), 'cpu');
  });

  test('IndexedAudioChunk payload can cross isolate boundaries', () async {
    final chunks = <IndexedAudioChunk>[
      IndexedAudioChunk(
        index: 7,
        samples: Float32List.fromList(<double>[0.1, -0.1]),
      ),
    ];

    final indexes = await Isolate.run(
      () => chunks.map((chunk) => chunk.index).toList(),
    );

    expect(indexes, const <int>[7]);
  });

  test('decodableFixedOverlapChunks skips only digital silence chunks', () {
    const sampleRate = 16000;
    final rawSamples = Float32List(sampleRate * 60);
    final samples = Float32List(sampleRate * 60);
    for (var i = sampleRate * 32; i < sampleRate * 45; i += 1) {
      rawSamples[i] = 0.01;
      samples[i] = 0.01;
    }

    final chunks = decodableFixedOverlapChunks(
      samples: samples,
      rawSamples: rawSamples,
    );

    expect(chunks, hasLength(1));
    expect(chunks.single.index, 1);
  });

  test('isNearlyDigitalSilence does not skip low-volume waveform', () {
    final samples = Float32List.fromList(
      List<double>.generate(16000, (index) => index.isEven ? 0.0002 : -0.0002),
    );

    expect(isNearlyDigitalSilence(Float32List(16000)), isTrue);
    expect(isNearlyDigitalSilence(samples), isFalse);
  });

  test('scoreTranscript marks single-character fragments as low quality', () {
    final score = scoreTranscript(const <String>[
      '。',
      '是。',
      '你。',
      '有。',
      '。',
      '是。',
      '嗯。',
      '好。',
    ], sampleCount: 16000 * 90);

    expect(score.isLowQuality, isTrue);
    expect(shouldRunVadFallback(score), isTrue);
  });

  test('scoreTranscript accepts dense meeting text', () {
    final score = scoreTranscript(const <String>[
      '这个支付标准的新增本来就不是我们这边管，只是我们要追踪那边的进度。',
      '这个会议正式移到医疗局共同会议那边去，希望针对征收相关的支付标准尽快出方案。',
    ], sampleCount: 16000 * 60);

    expect(score.isLowQuality, isFalse);
    expect(shouldRunVadFallback(score), isFalse);
    expect(score.score, greaterThan(0));
  });

  test('chooseTranscriptCandidate picks the higher quality score', () {
    const fixed = TranscriptScore(
      texts: <String>['是。', '有。'],
      score: -20,
      isLowQuality: true,
    );
    const vad = TranscriptScore(
      texts: <String>['会议正式移到医疗局共同会议那边去'],
      score: 40,
      isLowQuality: false,
    );

    expect(
      chooseTranscriptCandidate(fixedCandidate: fixed, vadCandidate: vad),
      same(vad),
    );
  });
}

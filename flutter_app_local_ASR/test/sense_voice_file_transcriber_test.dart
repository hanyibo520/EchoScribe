import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/asr/model_store.dart';
import 'package:flutter_app/asr/sense_voice_file_transcriber.dart';

void main() {
  test('preprocessFileAudioSamples leaves samples untouched in none mode', () {
    final samples = Float32List.fromList(<double>[0.25, 0.125, -0.5, 0.0625]);

    final prepared = preprocessFileAudioSamples(
      samples,
      preprocessingMode: FileAudioPreprocessingMode.none,
    );

    expect(prepared, same(samples));
    expect(prepared, <double>[0.25, 0.125, -0.5, 0.0625]);
  });

  test(
    'preprocessFileAudioSamples applies speech conditioning when requested',
    () {
      final samples = Float32List.fromList(
        List<double>.generate(1600, (index) => index.isEven ? 0.25 : 0.15),
      );

      final prepared = preprocessFileAudioSamples(
        samples,
        preprocessingMode: FileAudioPreprocessingMode.speechConditioning,
      );

      expect(prepared, isNot(same(samples)));
      expect(prepared, isNot(samples));
    },
  );

  test('imported audio path explicitly skips file preprocessing', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains(
        'modelProfiles: currentCheck.fileTranscriptionSenseVoiceProfiles',
      ),
    );
    expect(source, contains('scope: ModelInstallScope.fastAsr'));
    expect(
      source,
      contains('preprocessingMode: FileAudioPreprocessingMode.none'),
    );
  });

  test('file transcription profiles prefer fast SenseVoice when ready', () {
    final check = _modelCheck();

    expect(
      check.fileTranscriptionSenseVoiceProfiles.map((profile) => profile.id),
      const <String>[
        SenseVoiceModelProfile.fastId,
        SenseVoiceModelProfile.standardId,
      ],
    );
  });

  test(
    'file transcription profiles fall back to standard when fast is missing',
    () {
      final check = _modelCheck(
        missingFastSenseVoiceFiles: const <String>['fast-model'],
      );

      expect(
        check.fileTranscriptionSenseVoiceProfiles.map((profile) => profile.id),
        const <String>[SenseVoiceModelProfile.standardId],
      );
    },
  );

  test('live SenseVoice profile still points at the standard model files', () {
    final check = _modelCheck();

    expect(check.senseVoiceFiles.model, 'standard-model');
    expect(check.fastSenseVoiceFiles.model, 'fast-model');
  });

  test(
    'Sherpa speaker processing requires diarization and embedding models',
    () {
      expect(_modelCheck().isSherpaSpeakerProcessingReady, isTrue);
      expect(
        _modelCheck(
          missingSpeakerDiarizationFiles: const <String>[
            'speaker-segmentation',
          ],
        ).isSherpaSpeakerProcessingReady,
        isFalse,
      );
      expect(
        _modelCheck(
          missingSpeakerEmbeddingFiles: const <String>['speaker-embedding'],
        ).isSherpaSpeakerProcessingReady,
        isFalse,
      );
    },
  );

  test('live ASR can use Moonshine or SenseVoice as primary fallback', () {
    expect(_modelCheck().isLiveAsrReady, isTrue);
    expect(
      _modelCheck(
        missingMoonshineTinyStreamingFiles: const <String>['moonshine-model'],
      ).isLiveAsrReady,
      isTrue,
    );
    expect(
      _modelCheck(
        missingSenseVoiceFiles: const <String>['standard-model'],
        missingMoonshineTinyStreamingFiles: const <String>['moonshine-model'],
      ).isLiveAsrReady,
      isFalse,
    );
  });

  test('file ASR fast profile falls back on empty or low quality result', () {
    expect(
      fileAsrProfileFallbackReason(
        profileId: SenseVoiceModelProfile.fastId,
        hasNextProfile: true,
        hasText: false,
        isLowQuality: true,
      ),
      'empty_result',
    );
    expect(
      fileAsrProfileFallbackReason(
        profileId: SenseVoiceModelProfile.fastId,
        hasNextProfile: true,
        hasText: true,
        isLowQuality: true,
      ),
      'low_quality',
    );
    expect(
      fileAsrProfileFallbackReason(
        profileId: SenseVoiceModelProfile.fastId,
        hasNextProfile: true,
        hasText: true,
        isLowQuality: false,
      ),
      isNull,
    );
  });

  test('file ASR standard profile is the final quality fallback', () {
    expect(
      fileAsrProfileFallbackReason(
        profileId: SenseVoiceModelProfile.standardId,
        hasNextProfile: false,
        hasText: true,
        isLowQuality: true,
      ),
      isNull,
    );
    expect(
      fileAsrProfileFallbackReason(
        profileId: SenseVoiceModelProfile.standardId,
        hasNextProfile: false,
        hasText: false,
        isLowQuality: true,
      ),
      isNull,
    );
  });

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

  test('selectFixedDecodeWorkerCount scales workers for long iOS files', () {
    expect(
      selectFixedDecodeWorkerCount(
        chunkCount: 6,
        processorCount: 6,
        isIOS: true,
      ),
      3,
    );
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
  });

  test(
    'selectFixedDecodeWorkerCount caps very long iOS imports for memory',
    () {
      expect(
        selectFixedDecodeWorkerCount(
          chunkCount: 30,
          processorCount: 6,
          isIOS: true,
          sampleCount: 16000 * 13 * 60,
        ),
        3,
      );
      expect(
        selectFixedDecodeWorkerCount(
          chunkCount: 40,
          processorCount: 6,
          isIOS: true,
          sampleCount: 16000 * 20 * 60,
        ),
        2,
      );
      expect(
        selectFixedDecodeWorkerCount(
          chunkCount: 60,
          processorCount: 6,
          isIOS: true,
          sampleCount: 16000 * 30 * 60,
        ),
        1,
      );
    },
  );

  test('selectFixedDecodeProvider defaults to CPU on all platforms', () {
    expect(selectFixedDecodeProvider(isIOS: true), 'cpu');
    expect(selectFixedDecodeProvider(isIOS: false), 'cpu');
  });

  test('very long unprocessed file ASR uses streaming PCM16 path', () {
    expect(
      shouldUseStreamingPcm16Transcription(
        preprocessingMode: FileAudioPreprocessingMode.none,
        sampleCount: 16000 * 30 * 60,
      ),
      isTrue,
    );
    expect(
      shouldUseStreamingPcm16Transcription(
        preprocessingMode: FileAudioPreprocessingMode.none,
        sampleCount: 16000 * 13 * 60,
      ),
      isFalse,
    );
    expect(
      shouldUseStreamingPcm16Transcription(
        preprocessingMode: FileAudioPreprocessingMode.speechConditioning,
        sampleCount: 16000 * 30 * 60,
      ),
      isFalse,
    );
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

  test(
    'FileAudioPreprocessingMode payload can cross isolate boundaries',
    () async {
      const mode = FileAudioPreprocessingMode.none;

      final name = await Isolate.run(() => mode.name);

      expect(name, 'none');
    },
  );

  test('FixedDecodeProfile summarizes workers and chunk timings', () {
    const profile = FixedDecodeProfile(
      workers: <FixedWorkerDecodeProfile>[
        FixedWorkerDecodeProfile(
          workerIndex: 0,
          recognizerInitMs: 12,
          totalMs: 110,
          chunks: <FixedChunkDecodeProfile>[
            FixedChunkDecodeProfile(
              workerIndex: 0,
              chunkIndex: 0,
              decodeMs: 50,
              sampleCount: 16000,
              charCount: 12,
            ),
            FixedChunkDecodeProfile(
              workerIndex: 0,
              chunkIndex: 2,
              decodeMs: 60,
              sampleCount: 16000,
              charCount: 14,
            ),
          ],
        ),
        FixedWorkerDecodeProfile(
          workerIndex: 1,
          recognizerInitMs: 20,
          totalMs: 130,
          chunks: <FixedChunkDecodeProfile>[
            FixedChunkDecodeProfile(
              workerIndex: 1,
              chunkIndex: 1,
              decodeMs: 120,
              sampleCount: 16000,
              charCount: 20,
            ),
          ],
        ),
      ],
    );

    expect(profile.recognizerInitMs, 20);
    expect(profile.recognizerInitSumMs, 32);
    expect(profile.slowestChunk?.chunkIndex, 1);
    expect(profile.workerSummary, contains('#0:chunks=2 indexes=0,2'));
    expect(profile.workerSummary, contains('#1:chunks=1 indexes=1'));
    expect(profile.chunkTimingLines(entriesPerLine: 2), hasLength(2));
    expect(
      profile.chunkTimingLines(entriesPerLine: 2).first,
      contains('#0:50ms'),
    );
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

  test('decodableFixedOverlapChunksFromPcm16 converts chunks directly', () {
    final pcm = _pcm16Bytes(const <int>[
      0,
      16384,
      -16384,
      32767,
      8192,
      -8192,
      4096,
      -4096,
      2048,
      -2048,
    ]);

    final chunks = decodableFixedOverlapChunksFromPcm16(pcm);

    expect(chunks, hasLength(1));
    expect(chunks.single.index, 0);
    expect(chunks.single.samples, hasLength(10));
    expect(chunks.single.samples[0], 0);
    expect(chunks.single.samples[1], closeTo(0.5, 0.00001));
    expect(chunks.single.samples[2], closeTo(-0.5, 0.00001));
    expect(fixedOverlapChunkCount(16000 * 60), 3);
  });

  test('splitFixedDecodeBatches can avoid copying owned chunk samples', () {
    final samples = Float32List.fromList(<double>[0.1, -0.1]);
    final chunks = <IndexedAudioChunk>[
      IndexedAudioChunk(index: 0, samples: samples),
    ];

    final borrowed = splitFixedDecodeBatches(chunks, 1, copySamples: false);
    final copied = splitFixedDecodeBatches(chunks, 1);

    expect(borrowed.single.single.samples, same(samples));
    expect(copied.single.single.samples, isNot(same(samples)));
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

Uint8List _pcm16Bytes(List<int> values) {
  final bytes = Uint8List(values.length * 2);
  final data = ByteData.view(bytes.buffer);
  for (var i = 0; i < values.length; i += 1) {
    data.setInt16(i * 2, values[i], Endian.little);
  }
  return bytes;
}

ModelCheckResult _modelCheck({
  List<String> missingSenseVoiceFiles = const <String>[],
  List<String> missingFastSenseVoiceFiles = const <String>[],
  List<String> missingMoonshineTinyStreamingFiles = const <String>[],
  List<String> missingSpeakerDiarizationFiles = const <String>[],
  List<String> missingSpeakerEmbeddingFiles = const <String>[],
}) {
  return ModelCheckResult(
    asrRootPath: 'asr-root',
    senseVoiceFiles: const SenseVoiceModelFiles(
      model: 'standard-model',
      tokens: 'standard-tokens',
      vad: 'vad',
    ),
    missingSenseVoiceFiles: missingSenseVoiceFiles,
    fastSenseVoiceFiles: const SenseVoiceModelFiles(
      model: 'fast-model',
      tokens: 'fast-tokens',
      vad: 'vad',
    ),
    missingFastSenseVoiceFiles: missingFastSenseVoiceFiles,
    moonshineTinyStreamingFiles: const MoonshineModelFiles(
      directory: 'moonshine-root',
      files: <String, String>{
        'adapter.ort': 'adapter',
        'cross_kv.ort': 'cross-kv',
        'decoder_kv.ort': 'decoder-kv',
        'decoder_kv_with_attention.ort': 'decoder-kv-with-attention',
        'encoder.ort': 'encoder',
        'frontend.ort': 'frontend',
        'streaming_config.json': 'streaming-config',
        'tokenizer.bin': 'tokenizer',
      },
    ),
    missingMoonshineTinyStreamingFiles: missingMoonshineTinyStreamingFiles,
    speakerDiarizationFiles: const SpeakerDiarizationModelFiles(
      segmentation: 'speaker-segmentation',
      embedding: 'speaker-embedding',
    ),
    missingSpeakerDiarizationFiles: missingSpeakerDiarizationFiles,
    speakerEmbeddingFiles: const SpeakerEmbeddingModelFiles(
      model: 'speaker-embedding',
    ),
    missingSpeakerEmbeddingFiles: missingSpeakerEmbeddingFiles,
    whisperModelPath: 'whisper',
    isWhisperModelReady: true,
    llamaModelPath: 'llama',
    isLlamaModelReady: true,
  );
}

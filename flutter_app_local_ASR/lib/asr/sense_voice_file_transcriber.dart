import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'asr_engine.dart';
import 'audio_utils.dart';
import 'model_store.dart';

const int _sampleRate = 16000;
const int _recognizerThreads = 4;
const double _targetPeak = 0.92;
const double _maxGain = 6.0;
const double _vadBufferSeconds = 35;
const int _vadBlockSamples = _sampleRate * 30;
const int _fixedChunkSamples = _sampleRate * 30;
const int _vadFallbackChunkSamples = _sampleRate * 25;
const int _fileChunkOverlapSamples = _sampleRate * 2;
const int _parallelDecodeMinChunks = 6;
const int _parallelDecodeWorkers = 3;
const int _parallelRecognizerThreads = 2;
const int _iosTwoWorkerSampleLimit = _sampleRate * 15 * 60;
const int _iosSerialSampleLimit = _sampleRate * 25 * 60;
const double _digitalSilencePeak = 2.0 / 32768.0;
const int _digitalSilenceMaxLoudSamples = 8;
const String _cpuProvider = 'cpu';
const String _coreMlProvider = 'coreml';

enum FileAudioPreprocessingMode { none, speechConditioning }

class SenseVoiceFileTranscriber {
  SenseVoiceFileTranscriber({required ModelStore modelStore})
    : _modelStore = modelStore;

  final ModelStore _modelStore;

  Future<AsrAvailability> checkAvailability() async {
    final check = await _modelStore.inspect();
    if (check.isSenseVoiceReady) {
      return const AsrAvailability.available();
    }

    return AsrAvailability.unavailable(
      'Missing SenseVoice files: ${check.missingSenseVoiceFiles.join(', ')}',
    );
  }

  Future<List<AsrSegment>> transcribePcm16Audio({
    required Uint8List pcm16Audio,
    required String sourceName,
    SenseVoiceModelFiles? modelFiles,
    List<SenseVoiceModelProfile>? modelProfiles,
    FileAudioPreprocessingMode preprocessingMode =
        FileAudioPreprocessingMode.speechConditioning,
  }) async {
    if (pcm16Audio.isEmpty) {
      return const <AsrSegment>[];
    }

    final profiles =
        modelProfiles ??
        <SenseVoiceModelProfile>[
          SenseVoiceModelProfile.standard(
            modelFiles ?? await _senseVoiceModelFiles(),
          ),
        ];
    if (profiles.isEmpty) {
      return const <AsrSegment>[];
    }

    final errors = <String>[];
    var sawEmptyResult = false;
    for (
      var profileIndex = 0;
      profileIndex < profiles.length;
      profileIndex += 1
    ) {
      final profile = profiles[profileIndex];
      final hasNextProfile = profileIndex < profiles.length - 1;
      try {
        final result = await Isolate.run(
          () => _transcribeSenseVoiceTextSegments(
            asrProfileId: profile.id,
            pcm16Audio: pcm16Audio,
            modelPath: profile.files.model,
            tokensPath: profile.files.tokens,
            vadPath: profile.files.vad,
            preprocessingMode: preprocessingMode,
          ),
        );
        for (final line in result.debugLines(sourceName)) {
          debugPrint(line);
        }

        final fallbackReason = fileAsrProfileFallbackReason(
          profileId: profile.id,
          hasNextProfile: hasNextProfile,
          hasText: result.texts.isNotEmpty,
          isLowQuality: result.selectedCandidate.isLowQuality,
        );
        if (fallbackReason != null) {
          if (fallbackReason == 'empty_result') {
            sawEmptyResult = true;
          }
          debugPrint(
            '[ASR import] asrProfile=${profile.id} fallbackToNext '
            'reason=$fallbackReason',
          );
          continue;
        }

        final segments = <AsrSegment>[];
        for (final text in result.texts) {
          segments.add(
            AsrSegment(
              index: segments.length + 1,
              text: text,
              createdAt: DateTime.now(),
              engineName: 'Sherpa-ONNX ${profile.id} file: $sourceName',
            ),
          );
        }
        return segments;
      } catch (error) {
        final message = '${profile.id}: $error';
        errors.add(message);
        debugPrint('[ASR import] asrProfile=${profile.id} failed $error');
      }
    }

    if (sawEmptyResult) {
      return const <AsrSegment>[];
    }
    throw StateError(
      'SenseVoice file transcription failed for all profiles.\n'
      '${errors.join('\n')}',
    );
  }

  Future<SenseVoiceModelFiles> _senseVoiceModelFiles() async {
    final check = await _modelStore.inspect();
    if (check.isSenseVoiceReady) {
      return check.senseVoiceFiles;
    }

    throw StateError(
      'Missing SenseVoice files: ${check.missingSenseVoiceFiles.join(', ')}',
    );
  }
}

@visibleForTesting
String? fileAsrProfileFallbackReason({
  required String profileId,
  required bool hasNextProfile,
  required bool hasText,
  required bool isLowQuality,
}) {
  if (!hasNextProfile) {
    return null;
  }
  if (!hasText) {
    return 'empty_result';
  }
  if (profileId != SenseVoiceModelProfile.standardId && isLowQuality) {
    return 'low_quality';
  }
  return null;
}

@visibleForTesting
bool shouldUseStreamingPcm16Transcription({
  required FileAudioPreprocessingMode preprocessingMode,
  required int sampleCount,
}) {
  return preprocessingMode == FileAudioPreprocessingMode.none &&
      sampleCount >= _iosSerialSampleLimit;
}

Future<_FileTranscriptionResult> _transcribeSenseVoiceTextSegments({
  required String asrProfileId,
  required Uint8List pcm16Audio,
  required String modelPath,
  required String tokensPath,
  required String vadPath,
  required FileAudioPreprocessingMode preprocessingMode,
}) async {
  sherpa.initBindings();

  final totalWatch = Stopwatch()..start();
  final pcmWatch = Stopwatch()..start();
  late final int sampleCount;
  late final List<IndexedAudioChunk> fixedChunks;
  late final int totalFixedChunkCount;
  late final bool fixedChunksOwnSamples;
  Float32List? vadSamples;
  if (preprocessingMode == FileAudioPreprocessingMode.none) {
    sampleCount = pcm16Audio.length ~/ 2;
    totalFixedChunkCount = fixedOverlapChunkCount(sampleCount);
    if (shouldUseStreamingPcm16Transcription(
      preprocessingMode: preprocessingMode,
      sampleCount: sampleCount,
    )) {
      pcmWatch.stop();
      final preprocessWatch = Stopwatch()..start();
      preprocessWatch.stop();
      return _runStreamingPcm16SenseVoiceTranscription(
        asrProfileId: asrProfileId,
        pcm16Audio: pcm16Audio,
        totalFixedChunkCount: totalFixedChunkCount,
        sampleCount: sampleCount,
        modelPath: modelPath,
        tokensPath: tokensPath,
        vadPath: vadPath,
        preprocessingMode: preprocessingMode,
        totalWatch: totalWatch,
        pcmWatch: pcmWatch,
        preprocessWatch: preprocessWatch,
      );
    }
    fixedChunks = decodableFixedOverlapChunksFromPcm16(pcm16Audio);
    fixedChunksOwnSamples = true;
  } else {
    final rawSamples = pcm16BytesToFloat32(pcm16Audio);
    pcmWatch.stop();

    final preprocessWatch = Stopwatch()..start();
    vadSamples = preprocessFileAudioSamples(
      rawSamples,
      preprocessingMode: preprocessingMode,
    );
    preprocessWatch.stop();

    sampleCount = vadSamples.length;
    fixedChunks = decodableFixedOverlapChunks(
      samples: vadSamples,
      rawSamples: rawSamples,
    );
    totalFixedChunkCount = fixedOverlapChunkCount(sampleCount);
    fixedChunksOwnSamples = false;
    return _runPreparedSenseVoiceTranscription(
      asrProfileId: asrProfileId,
      fixedChunks: fixedChunks,
      fixedChunksOwnSamples: fixedChunksOwnSamples,
      totalFixedChunkCount: totalFixedChunkCount,
      sampleCount: sampleCount,
      modelPath: modelPath,
      tokensPath: tokensPath,
      vadPath: vadPath,
      preprocessingMode: preprocessingMode,
      initialVadSamples: vadSamples,
      totalWatch: totalWatch,
      pcmWatch: pcmWatch,
      preprocessWatch: preprocessWatch,
    );
  }
  pcmWatch.stop();

  final preprocessWatch = Stopwatch()..start();
  preprocessWatch.stop();

  return _runPreparedSenseVoiceTranscription(
    asrProfileId: asrProfileId,
    fixedChunks: fixedChunks,
    fixedChunksOwnSamples: fixedChunksOwnSamples,
    totalFixedChunkCount: totalFixedChunkCount,
    sampleCount: sampleCount,
    modelPath: modelPath,
    tokensPath: tokensPath,
    vadPath: vadPath,
    preprocessingMode: preprocessingMode,
    initialVadSamples: vadSamples,
    pcm16Audio: pcm16Audio,
    totalWatch: totalWatch,
    pcmWatch: pcmWatch,
    preprocessWatch: preprocessWatch,
  );
}

Future<_FileTranscriptionResult> _runStreamingPcm16SenseVoiceTranscription({
  required String asrProfileId,
  required Uint8List pcm16Audio,
  required int totalFixedChunkCount,
  required int sampleCount,
  required String modelPath,
  required String tokensPath,
  required String vadPath,
  required FileAudioPreprocessingMode preprocessingMode,
  required Stopwatch totalWatch,
  required Stopwatch pcmWatch,
  required Stopwatch preprocessWatch,
}) async {
  final processorCount = Platform.numberOfProcessors;
  final isIOS = Platform.isIOS;
  final fixedWatch = Stopwatch()..start();
  final fixedRun = _decodePcm16FixedChunksSerial(
    pcm16Audio: pcm16Audio,
    totalFixedChunkCount: totalFixedChunkCount,
    asrProfileId: asrProfileId,
    modelPath: modelPath,
    tokensPath: tokensPath,
    provider: selectFixedDecodeProvider(isIOS: isIOS),
  );
  fixedWatch.stop();

  return _completeSenseVoiceTranscription(
    asrProfileId: asrProfileId,
    fixedDecodeResult: _FixedDecodeResult(
      texts: fixedRun.texts,
      profile: fixedRun.profile,
      requestedProvider: _cpuProvider,
      provider: _cpuProvider,
      fallbackReason: null,
      qualityRetry: false,
    ),
    fixedChunkCount: fixedRun.profile.chunks.length,
    totalFixedChunkCount: totalFixedChunkCount,
    workerCount: 1,
    processorCount: processorCount,
    isIOS: isIOS,
    sampleCount: sampleCount,
    modelPath: modelPath,
    tokensPath: tokensPath,
    vadPath: vadPath,
    preprocessingMode: preprocessingMode,
    initialVadSamples: null,
    pcm16Audio: pcm16Audio,
    totalWatch: totalWatch,
    pcmWatch: pcmWatch,
    preprocessWatch: preprocessWatch,
    fixedWatch: fixedWatch,
  );
}

Future<_FileTranscriptionResult> _runPreparedSenseVoiceTranscription({
  required String asrProfileId,
  required List<IndexedAudioChunk> fixedChunks,
  required bool fixedChunksOwnSamples,
  required int totalFixedChunkCount,
  required int sampleCount,
  required String modelPath,
  required String tokensPath,
  required String vadPath,
  required FileAudioPreprocessingMode preprocessingMode,
  required Float32List? initialVadSamples,
  required Stopwatch totalWatch,
  required Stopwatch pcmWatch,
  required Stopwatch preprocessWatch,
  Uint8List? pcm16Audio,
}) async {
  final processorCount = Platform.numberOfProcessors;
  final isIOS = Platform.isIOS;
  final preferredFixedProvider = selectFixedDecodeProvider(isIOS: isIOS);
  final workerCount = selectFixedDecodeWorkerCount(
    chunkCount: fixedChunks.length,
    processorCount: processorCount,
    isIOS: isIOS,
    sampleCount: sampleCount,
  );
  final fixedWatch = Stopwatch()..start();
  var fixedDecodeResult = await _decodeFixedChunksWithProviderFallback(
    chunks: fixedChunks,
    chunksOwnSamples: fixedChunksOwnSamples,
    modelPath: modelPath,
    tokensPath: tokensPath,
    workerCount: workerCount,
    preferredProvider: preferredFixedProvider,
  );

  final fixedCandidate = scoreTranscript(
    fixedDecodeResult.texts,
    sampleCount: sampleCount,
  );
  if (fixedDecodeResult.provider == _coreMlProvider &&
      fixedCandidate.isLowQuality) {
    final cpuRun = await _decodeFixedChunks(
      chunks: fixedChunks,
      chunksOwnSamples: fixedChunksOwnSamples,
      modelPath: modelPath,
      tokensPath: tokensPath,
      workerCount: workerCount,
      provider: _cpuProvider,
    );
    final cpuCandidate = scoreTranscript(
      cpuRun.texts,
      sampleCount: sampleCount,
    );
    fixedDecodeResult = fixedDecodeResult.withQualityRetry(
      selectedProvider: cpuCandidate.score >= fixedCandidate.score
          ? _cpuProvider
          : fixedDecodeResult.provider,
      selectedTexts: cpuCandidate.score >= fixedCandidate.score
          ? cpuRun.texts
          : fixedDecodeResult.texts,
      selectedProfile: cpuCandidate.score >= fixedCandidate.score
          ? cpuRun.profile
          : fixedDecodeResult.profile,
      fallbackReason: cpuCandidate.score >= fixedCandidate.score
          ? 'coreml_low_quality_cpu_selected'
          : 'coreml_low_quality_cpu_rejected',
    );
  }
  fixedWatch.stop();

  return _completeSenseVoiceTranscription(
    asrProfileId: asrProfileId,
    fixedDecodeResult: fixedDecodeResult,
    fixedChunkCount: fixedChunks.length,
    totalFixedChunkCount: totalFixedChunkCount,
    workerCount: workerCount,
    processorCount: processorCount,
    isIOS: isIOS,
    sampleCount: sampleCount,
    modelPath: modelPath,
    tokensPath: tokensPath,
    vadPath: vadPath,
    preprocessingMode: preprocessingMode,
    initialVadSamples: initialVadSamples,
    pcm16Audio: pcm16Audio,
    totalWatch: totalWatch,
    pcmWatch: pcmWatch,
    preprocessWatch: preprocessWatch,
    fixedWatch: fixedWatch,
  );
}

Future<_FileTranscriptionResult> _completeSenseVoiceTranscription({
  required String asrProfileId,
  required _FixedDecodeResult fixedDecodeResult,
  required int fixedChunkCount,
  required int totalFixedChunkCount,
  required int workerCount,
  required int processorCount,
  required bool isIOS,
  required int sampleCount,
  required String modelPath,
  required String tokensPath,
  required String vadPath,
  required FileAudioPreprocessingMode preprocessingMode,
  required Float32List? initialVadSamples,
  required Stopwatch totalWatch,
  required Stopwatch pcmWatch,
  required Stopwatch preprocessWatch,
  required Stopwatch fixedWatch,
  Uint8List? pcm16Audio,
}) async {
  final fixedCandidate = scoreTranscript(
    fixedDecodeResult.texts,
    sampleCount: sampleCount,
  );
  final skippedSilentChunkCount = totalFixedChunkCount - fixedChunkCount;

  if (!shouldRunVadFallback(fixedCandidate)) {
    totalWatch.stop();
    return _FileTranscriptionResult(
      texts: fixedCandidate.texts,
      strategy: workerCount > 1
          ? 'fixed_parallel_${workerCount}w'
          : 'fixed_serial',
      fixedChunkCount: fixedChunkCount,
      totalFixedChunkCount: totalFixedChunkCount,
      skippedSilentChunkCount: skippedSilentChunkCount,
      workerCount: workerCount,
      processorCount: processorCount,
      isIOS: isIOS,
      requestedFixedProvider: fixedDecodeResult.requestedProvider,
      fixedProvider: fixedDecodeResult.provider,
      fixedProviderFallbackReason: fixedDecodeResult.fallbackReason,
      fixedProviderQualityRetry: fixedDecodeResult.qualityRetry,
      asrProfileId: asrProfileId,
      preprocessingMode: preprocessingMode,
      sampleCount: sampleCount,
      fixedCandidate: fixedCandidate,
      fixedDecodeProfile: fixedDecodeResult.profile,
      vadCandidate: null,
      vadSpeechSegmentCount: 0,
      vadFallbackRun: false,
      vadFallbackSelected: false,
      timings: _AsrTimings(
        pcmToFloatMs: pcmWatch.elapsedMilliseconds,
        preprocessMs: preprocessWatch.elapsedMilliseconds,
        fixedDecodeMs: fixedWatch.elapsedMilliseconds,
        vadDecodeMs: 0,
        totalMs: totalWatch.elapsedMilliseconds,
      ),
    );
  }

  final vadWatch = Stopwatch()..start();
  late final TranscriptScore vadCandidate;
  var vadSpeechSegmentCount = 0;
  var samples = initialVadSamples;
  if (samples == null) {
    final audio = pcm16Audio;
    if (audio == null) {
      throw StateError('Missing PCM audio for VAD fallback');
    }
    pcmWatch.start();
    samples = pcm16BytesToFloat32(audio);
    pcmWatch.stop();
  }
  final vadInputSamples = samples;
  final vad = sherpa.VoiceActivityDetector(
    config: sherpa.VadModelConfig(
      sileroVad: sherpa.SileroVadModelConfig(
        model: vadPath,
        threshold: 0.35,
        minSilenceDuration: 0.8,
        minSpeechDuration: 0.2,
        maxSpeechDuration: 25.0,
      ),
      sampleRate: _sampleRate,
      numThreads: 1,
      debug: false,
    ),
    bufferSizeInSeconds: _vadBufferSeconds,
  );

  try {
    final speechSegments = _detectSpeechSegments(vadInputSamples, vad);
    vadSpeechSegmentCount = speechSegments.length;
    if (speechSegments.isEmpty) {
      vadWatch.stop();
      totalWatch.stop();
      return _FileTranscriptionResult(
        texts: fixedCandidate.texts,
        strategy: 'fixed_low_quality_no_vad_speech',
        fixedChunkCount: fixedChunkCount,
        totalFixedChunkCount: totalFixedChunkCount,
        skippedSilentChunkCount: skippedSilentChunkCount,
        workerCount: workerCount,
        processorCount: processorCount,
        isIOS: isIOS,
        requestedFixedProvider: fixedDecodeResult.requestedProvider,
        fixedProvider: fixedDecodeResult.provider,
        fixedProviderFallbackReason: fixedDecodeResult.fallbackReason,
        fixedProviderQualityRetry: fixedDecodeResult.qualityRetry,
        asrProfileId: asrProfileId,
        preprocessingMode: preprocessingMode,
        sampleCount: sampleCount,
        fixedCandidate: fixedCandidate,
        fixedDecodeProfile: fixedDecodeResult.profile,
        vadCandidate: null,
        vadSpeechSegmentCount: vadSpeechSegmentCount,
        vadFallbackRun: true,
        vadFallbackSelected: false,
        timings: _AsrTimings(
          pcmToFloatMs: pcmWatch.elapsedMilliseconds,
          preprocessMs: preprocessWatch.elapsedMilliseconds,
          fixedDecodeMs: fixedWatch.elapsedMilliseconds,
          vadDecodeMs: vadWatch.elapsedMilliseconds,
          totalMs: totalWatch.elapsedMilliseconds,
        ),
      );
    }

    final recognizer = _createSenseVoiceRecognizer(
      modelPath: modelPath,
      tokensPath: tokensPath,
      numThreads: _recognizerThreads,
      provider: _cpuProvider,
    );
    try {
      vadCandidate = scoreTranscript(
        _decodeSegments(
          recognizer,
          chunkSpeechSegments(speechSegments),
          trimOverlaps: false,
        ),
        sampleCount: sampleCount,
      );
    } finally {
      recognizer.free();
    }
  } finally {
    vad.free();
  }
  vadWatch.stop();

  final selected = chooseTranscriptCandidate(
    fixedCandidate: fixedCandidate,
    vadCandidate: vadCandidate,
  );
  final vadSelected = identical(selected, vadCandidate);
  totalWatch.stop();
  return _FileTranscriptionResult(
    texts: selected.texts,
    strategy: vadSelected
        ? 'vad_fallback_selected'
        : 'fixed_selected_after_vad',
    fixedChunkCount: fixedChunkCount,
    totalFixedChunkCount: totalFixedChunkCount,
    skippedSilentChunkCount: skippedSilentChunkCount,
    workerCount: workerCount,
    processorCount: processorCount,
    isIOS: isIOS,
    requestedFixedProvider: fixedDecodeResult.requestedProvider,
    fixedProvider: fixedDecodeResult.provider,
    fixedProviderFallbackReason: fixedDecodeResult.fallbackReason,
    fixedProviderQualityRetry: fixedDecodeResult.qualityRetry,
    asrProfileId: asrProfileId,
    preprocessingMode: preprocessingMode,
    sampleCount: sampleCount,
    fixedCandidate: fixedCandidate,
    fixedDecodeProfile: fixedDecodeResult.profile,
    vadCandidate: vadCandidate,
    vadSpeechSegmentCount: vadSpeechSegmentCount,
    vadFallbackRun: true,
    vadFallbackSelected: vadSelected,
    timings: _AsrTimings(
      pcmToFloatMs: pcmWatch.elapsedMilliseconds,
      preprocessMs: preprocessWatch.elapsedMilliseconds,
      fixedDecodeMs: fixedWatch.elapsedMilliseconds,
      vadDecodeMs: vadWatch.elapsedMilliseconds,
      totalMs: totalWatch.elapsedMilliseconds,
    ),
  );
}

@visibleForTesting
Float32List preprocessFileAudioSamples(
  Float32List rawSamples, {
  required FileAudioPreprocessingMode preprocessingMode,
}) {
  return switch (preprocessingMode) {
    FileAudioPreprocessingMode.none => rawSamples,
    FileAudioPreprocessingMode.speechConditioning => conditionSpeechSamples(
      rawSamples,
      sampleRate: _sampleRate,
      targetPeak: _targetPeak,
      maxGain: _maxGain,
    ),
  };
}

List<Float32List> _detectSpeechSegments(
  Float32List samples,
  sherpa.VoiceActivityDetector vad,
) {
  final segments = <Float32List>[];

  for (
    var blockStart = 0;
    blockStart < samples.length;
    blockStart += _vadBlockSamples
  ) {
    final blockEnd = math.min(blockStart + _vadBlockSamples, samples.length);
    vad.acceptWaveform(Float32List.sublistView(samples, blockStart, blockEnd));
    _drainVad(vad, segments);

    vad.flush();
    _drainVad(vad, segments);
    vad.reset();
  }
  return segments;
}

void _drainVad(sherpa.VoiceActivityDetector vad, List<Float32List> segments) {
  while (!vad.isEmpty()) {
    final segment = vad.front();
    vad.pop();
    if (segment.samples.isNotEmpty) {
      segments.add(segment.samples);
    }
  }
}

List<Float32List> fixedOverlapChunks(Float32List samples) {
  if (samples.isEmpty) {
    return const <Float32List>[];
  }

  final chunks = <Float32List>[];
  final step = _fixedChunkSamples - _fileChunkOverlapSamples;
  for (var start = 0; start < samples.length; start += step) {
    final end = math.min(start + _fixedChunkSamples, samples.length);
    chunks.add(Float32List.sublistView(samples, start, end));
    if (end == samples.length) {
      break;
    }
  }
  return chunks;
}

int fixedOverlapChunkCount(int sampleCount) {
  if (sampleCount <= 0) {
    return 0;
  }

  final step = _fixedChunkSamples - _fileChunkOverlapSamples;
  var count = 0;
  for (var start = 0; start < sampleCount; start += step) {
    count += 1;
    if (math.min(start + _fixedChunkSamples, sampleCount) == sampleCount) {
      break;
    }
  }
  return count;
}

List<IndexedAudioChunk> decodableFixedOverlapChunks({
  required Float32List samples,
  required Float32List rawSamples,
}) {
  if (samples.isEmpty) {
    return const <IndexedAudioChunk>[];
  }

  final chunks = <IndexedAudioChunk>[];
  final step = _fixedChunkSamples - _fileChunkOverlapSamples;
  var index = 0;
  for (var start = 0; start < samples.length; start += step) {
    final end = math.min(start + _fixedChunkSamples, samples.length);
    final rawEnd = math.min(end, rawSamples.length);
    final rawChunk = rawEnd > start
        ? Float32List.sublistView(rawSamples, start, rawEnd)
        : Float32List(0);
    if (!isNearlyDigitalSilence(rawChunk)) {
      chunks.add(
        IndexedAudioChunk(
          index: index,
          samples: Float32List.sublistView(samples, start, end),
        ),
      );
    }
    index += 1;
    if (end == samples.length) {
      break;
    }
  }
  return chunks;
}

List<IndexedAudioChunk> decodableFixedOverlapChunksFromPcm16(
  Uint8List pcm16Audio,
) {
  final sampleCount = pcm16Audio.length ~/ 2;
  if (sampleCount == 0) {
    return const <IndexedAudioChunk>[];
  }

  final chunks = <IndexedAudioChunk>[];
  final data = ByteData.view(
    pcm16Audio.buffer,
    pcm16Audio.offsetInBytes,
    sampleCount * 2,
  );
  final step = _fixedChunkSamples - _fileChunkOverlapSamples;
  var index = 0;
  for (var start = 0; start < sampleCount; start += step) {
    final end = math.min(start + _fixedChunkSamples, sampleCount);
    if (!isNearlyDigitalSilencePcm16(
      data,
      startSample: start,
      endSample: end,
    )) {
      chunks.add(
        IndexedAudioChunk(
          index: index,
          samples: _pcm16ChunkToFloat32(
            data,
            startSample: start,
            endSample: end,
          ),
        ),
      );
    }
    index += 1;
    if (end == sampleCount) {
      break;
    }
  }
  return chunks;
}

bool isNearlyDigitalSilence(Float32List samples) {
  if (samples.isEmpty) {
    return true;
  }

  var loudSamples = 0;
  for (final sample in samples) {
    if (sample.abs() > _digitalSilencePeak) {
      loudSamples += 1;
      if (loudSamples > _digitalSilenceMaxLoudSamples) {
        return false;
      }
    }
  }
  return true;
}

bool isNearlyDigitalSilencePcm16(
  ByteData data, {
  required int startSample,
  required int endSample,
}) {
  if (endSample <= startSample) {
    return true;
  }

  var loudSamples = 0;
  for (
    var sampleIndex = startSample;
    sampleIndex < endSample;
    sampleIndex += 1
  ) {
    final value = data.getInt16(sampleIndex * 2, Endian.little).abs();
    if (value > 2) {
      loudSamples += 1;
      if (loudSamples > _digitalSilenceMaxLoudSamples) {
        return false;
      }
    }
  }
  return true;
}

Float32List _pcm16ChunkToFloat32(
  ByteData data, {
  required int startSample,
  required int endSample,
}) {
  final samples = Float32List(endSample - startSample);
  for (
    var sampleIndex = startSample;
    sampleIndex < endSample;
    sampleIndex += 1
  ) {
    samples[sampleIndex - startSample] =
        data.getInt16(sampleIndex * 2, Endian.little) / 32768.0;
  }
  return samples;
}

int selectFixedDecodeWorkerCount({
  required int chunkCount,
  required int processorCount,
  required bool isIOS,
  int sampleCount = 0,
}) {
  if (!isIOS || chunkCount < _parallelDecodeMinChunks) {
    return 1;
  }
  final availableWorkers = processorCount ~/ _parallelRecognizerThreads;
  if (availableWorkers < 2) {
    return 1;
  }
  if (sampleCount >= _iosSerialSampleLimit) {
    return 1;
  }
  if (sampleCount >= _iosTwoWorkerSampleLimit) {
    return math.min(2, availableWorkers);
  }
  return math.min(_parallelDecodeWorkers, availableWorkers);
}

String selectFixedDecodeProvider({required bool isIOS}) {
  return _cpuProvider;
}

List<Float32List> chunkSpeechSegments(List<Float32List> segments) {
  final chunks = <Float32List>[];
  final current = <Float32List>[];
  var currentLength = 0;

  void flush() {
    if (currentLength == 0) {
      return;
    }
    chunks.add(_concatChunks(current, currentLength));
    current.clear();
    currentLength = 0;
  }

  for (final segment in segments) {
    var offset = 0;
    while (offset < segment.length) {
      if (currentLength == _vadFallbackChunkSamples) {
        flush();
      }

      final available = _vadFallbackChunkSamples - currentLength;
      final take = math.min(available, segment.length - offset);
      current.add(Float32List.sublistView(segment, offset, offset + take));
      currentLength += take;
      offset += take;
    }
  }

  flush();
  return chunks;
}

Float32List _concatChunks(List<Float32List> chunks, int totalLength) {
  final combined = Float32List(totalLength);
  var offset = 0;
  for (final chunk in chunks) {
    combined.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return combined;
}

_FixedDecodeRun _decodePcm16FixedChunksSerial({
  required Uint8List pcm16Audio,
  required int totalFixedChunkCount,
  required String asrProfileId,
  required String modelPath,
  required String tokensPath,
  required String provider,
}) {
  final sampleCount = pcm16Audio.length ~/ 2;
  final data = ByteData.view(
    pcm16Audio.buffer,
    pcm16Audio.offsetInBytes,
    sampleCount * 2,
  );
  final totalWatch = Stopwatch()..start();
  final initWatch = Stopwatch()..start();
  final recognizer = _createSenseVoiceRecognizer(
    modelPath: modelPath,
    tokensPath: tokensPath,
    numThreads: _recognizerThreads,
    provider: provider,
  );
  initWatch.stop();

  try {
    final transcripts = <IndexedTranscript>[];
    final chunkProfiles = <FixedChunkDecodeProfile>[];
    final step = _fixedChunkSamples - _fileChunkOverlapSamples;
    var decodedCount = 0;
    var index = 0;
    for (var start = 0; start < sampleCount; start += step) {
      final end = math.min(start + _fixedChunkSamples, sampleCount);
      if (!isNearlyDigitalSilencePcm16(
        data,
        startSample: start,
        endSample: end,
      )) {
        final chunkWatch = Stopwatch()..start();
        final text = _decodeSegment(
          recognizer,
          _pcm16ChunkToFloat32(data, startSample: start, endSample: end),
        );
        chunkWatch.stop();
        decodedCount += 1;
        chunkProfiles.add(
          FixedChunkDecodeProfile(
            workerIndex: 0,
            chunkIndex: index,
            decodeMs: chunkWatch.elapsedMilliseconds,
            sampleCount: end - start,
            charCount: _meaningfulCharacterCount(text),
          ),
        );
        if (text.isNotEmpty) {
          transcripts.add(IndexedTranscript(index: index, text: text));
        }
      }

      final processedCount = index + 1;
      if (processedCount % 12 == 0 || processedCount == totalFixedChunkCount) {
        debugPrint(
          '[ASR import] streamingProgress asrProfile=$asrProfileId '
          'chunk=$processedCount/$totalFixedChunkCount decoded=$decodedCount',
        );
      }
      index += 1;
      if (end == sampleCount) {
        break;
      }
    }

    totalWatch.stop();
    return _FixedDecodeRun(
      texts: mergeIndexedTranscripts(transcripts, trimOverlaps: true),
      profile: FixedDecodeProfile(
        workers: <FixedWorkerDecodeProfile>[
          FixedWorkerDecodeProfile(
            workerIndex: 0,
            recognizerInitMs: initWatch.elapsedMilliseconds,
            totalMs: totalWatch.elapsedMilliseconds,
            chunks: chunkProfiles,
          ),
        ],
      ),
    );
  } finally {
    recognizer.free();
  }
}

Future<_FixedDecodeResult> _decodeFixedChunksWithProviderFallback({
  required List<IndexedAudioChunk> chunks,
  required bool chunksOwnSamples,
  required String modelPath,
  required String tokensPath,
  required int workerCount,
  required String preferredProvider,
}) async {
  if (preferredProvider == _cpuProvider) {
    final run = await _decodeFixedChunks(
      chunks: chunks,
      chunksOwnSamples: chunksOwnSamples,
      modelPath: modelPath,
      tokensPath: tokensPath,
      workerCount: workerCount,
      provider: _cpuProvider,
    );
    return _FixedDecodeResult(
      texts: run.texts,
      profile: run.profile,
      requestedProvider: _cpuProvider,
      provider: _cpuProvider,
      fallbackReason: null,
      qualityRetry: false,
    );
  }

  try {
    final run = await _decodeFixedChunks(
      chunks: chunks,
      chunksOwnSamples: chunksOwnSamples,
      modelPath: modelPath,
      tokensPath: tokensPath,
      workerCount: workerCount,
      provider: preferredProvider,
    );
    return _FixedDecodeResult(
      texts: run.texts,
      profile: run.profile,
      requestedProvider: preferredProvider,
      provider: preferredProvider,
      fallbackReason: null,
      qualityRetry: false,
    );
  } catch (error) {
    final run = await _decodeFixedChunks(
      chunks: chunks,
      chunksOwnSamples: chunksOwnSamples,
      modelPath: modelPath,
      tokensPath: tokensPath,
      workerCount: workerCount,
      provider: _cpuProvider,
    );
    return _FixedDecodeResult(
      texts: run.texts,
      profile: run.profile,
      requestedProvider: preferredProvider,
      provider: _cpuProvider,
      fallbackReason: _compactError(error),
      qualityRetry: false,
    );
  }
}

Future<_FixedDecodeRun> _decodeFixedChunks({
  required List<IndexedAudioChunk> chunks,
  required bool chunksOwnSamples,
  required String modelPath,
  required String tokensPath,
  required int workerCount,
  required String provider,
}) async {
  if (chunks.isEmpty) {
    return const _FixedDecodeRun(
      texts: <String>[],
      profile: FixedDecodeProfile(workers: <FixedWorkerDecodeProfile>[]),
    );
  }

  if (workerCount <= 1) {
    final totalWatch = Stopwatch()..start();
    final initWatch = Stopwatch()..start();
    final recognizer = _createSenseVoiceRecognizer(
      modelPath: modelPath,
      tokensPath: tokensPath,
      numThreads: _recognizerThreads,
      provider: provider,
    );
    initWatch.stop();
    try {
      final batch = _decodeIndexedAudioChunks(
        recognizer,
        chunks,
        workerIndex: 0,
      );
      totalWatch.stop();
      return _FixedDecodeRun(
        texts: mergeIndexedTranscripts(batch.transcripts, trimOverlaps: true),
        profile: FixedDecodeProfile(
          workers: <FixedWorkerDecodeProfile>[
            FixedWorkerDecodeProfile(
              workerIndex: 0,
              recognizerInitMs: initWatch.elapsedMilliseconds,
              totalMs: totalWatch.elapsedMilliseconds,
              chunks: batch.chunkProfiles,
            ),
          ],
        ),
      );
    } finally {
      recognizer.free();
    }
  }

  final batches = splitFixedDecodeBatches(
    chunks,
    workerCount,
    copySamples: !chunksOwnSamples,
  );
  final results = await Future.wait(<Future<_FixedChunkBatchResult>>[
    for (var workerIndex = 0; workerIndex < batches.length; workerIndex += 1)
      Isolate.run(
        () => _decodeFixedChunkBatch(
          _FixedChunkBatchPayload(
            workerIndex: workerIndex,
            modelPath: modelPath,
            tokensPath: tokensPath,
            provider: provider,
            chunks: batches[workerIndex],
          ),
        ),
      ),
  ]);

  return _FixedDecodeRun(
    texts: mergeIndexedTranscripts(
      results.expand((batch) => batch.transcripts).toList(),
      trimOverlaps: true,
    ),
    profile: FixedDecodeProfile(
      workers: results.map((batch) => batch.workerProfile).toList()
        ..sort((left, right) => left.workerIndex.compareTo(right.workerIndex)),
    ),
  );
}

List<List<IndexedAudioChunk>> splitFixedDecodeBatches(
  List<IndexedAudioChunk> chunks,
  int workerCount, {
  bool copySamples = true,
}) {
  final batchCount = math.min(workerCount, chunks.length);
  final batches = List<List<IndexedAudioChunk>>.generate(
    batchCount,
    (_) => <IndexedAudioChunk>[],
  );
  for (var i = 0; i < chunks.length; i += 1) {
    final chunk = chunks[i];
    batches[i % batchCount].add(
      IndexedAudioChunk(
        index: chunk.index,
        samples: copySamples
            ? Float32List.fromList(chunk.samples)
            : chunk.samples,
      ),
    );
  }
  return batches.where((batch) => batch.isNotEmpty).toList();
}

_FixedChunkBatchResult _decodeFixedChunkBatch(_FixedChunkBatchPayload payload) {
  sherpa.initBindings();
  final totalWatch = Stopwatch()..start();
  final initWatch = Stopwatch()..start();
  final recognizer = _createSenseVoiceRecognizer(
    modelPath: payload.modelPath,
    tokensPath: payload.tokensPath,
    numThreads: _parallelRecognizerThreads,
    provider: payload.provider,
  );
  initWatch.stop();
  try {
    final batch = _decodeIndexedAudioChunks(
      recognizer,
      payload.chunks,
      workerIndex: payload.workerIndex,
    );
    totalWatch.stop();
    return _FixedChunkBatchResult(
      transcripts: batch.transcripts,
      workerProfile: FixedWorkerDecodeProfile(
        workerIndex: payload.workerIndex,
        recognizerInitMs: initWatch.elapsedMilliseconds,
        totalMs: totalWatch.elapsedMilliseconds,
        chunks: batch.chunkProfiles,
      ),
    );
  } finally {
    recognizer.free();
  }
}

_IndexedDecodeResult _decodeIndexedAudioChunks(
  sherpa.OfflineRecognizer recognizer,
  List<IndexedAudioChunk> chunks, {
  required int workerIndex,
}) {
  final transcripts = <IndexedTranscript>[];
  final chunkProfiles = <FixedChunkDecodeProfile>[];
  for (final chunk in chunks) {
    final watch = Stopwatch()..start();
    final text = _decodeSegment(recognizer, chunk.samples);
    watch.stop();
    chunkProfiles.add(
      FixedChunkDecodeProfile(
        workerIndex: workerIndex,
        chunkIndex: chunk.index,
        decodeMs: watch.elapsedMilliseconds,
        sampleCount: chunk.samples.length,
        charCount: _meaningfulCharacterCount(text),
      ),
    );
    if (text.isNotEmpty) {
      transcripts.add(IndexedTranscript(index: chunk.index, text: text));
    }
  }
  return _IndexedDecodeResult(
    transcripts: transcripts,
    chunkProfiles: chunkProfiles,
  );
}

List<String> mergeIndexedTranscripts(
  List<IndexedTranscript> transcripts, {
  required bool trimOverlaps,
}) {
  final sorted = transcripts.where((item) => item.text.isNotEmpty).toList()
    ..sort((left, right) => left.index.compareTo(right.index));

  final texts = <String>[];
  for (final transcript in sorted) {
    final deduped = trimOverlaps && texts.isNotEmpty
        ? trimRepeatedPrefix(previous: texts.last, current: transcript.text)
        : transcript.text;
    if (deduped.isNotEmpty) {
      texts.add(deduped);
    }
  }
  return texts;
}

List<String> _decodeSegments(
  sherpa.OfflineRecognizer recognizer,
  List<Float32List> segments, {
  required bool trimOverlaps,
}) {
  final texts = <String>[];
  for (final segmentSamples in segments) {
    final text = _decodeSegment(recognizer, segmentSamples);
    if (text.isEmpty) {
      continue;
    }

    final deduped = trimOverlaps && texts.isNotEmpty
        ? trimRepeatedPrefix(previous: texts.last, current: text)
        : text;
    if (deduped.isNotEmpty) {
      texts.add(deduped);
    }
  }
  return texts;
}

String trimRepeatedPrefix({required String previous, required String current}) {
  final previousRunes = previous.runes.toList();
  final currentRunes = current.runes.toList();
  final maxOverlap = math.min(
    32,
    math.min(previousRunes.length, currentRunes.length),
  );

  for (var length = maxOverlap; length >= 3; length -= 1) {
    var matches = true;
    for (var i = 0; i < length; i += 1) {
      if (previousRunes[previousRunes.length - length + i] != currentRunes[i]) {
        matches = false;
        break;
      }
    }
    if (matches &&
        _meaningfulCharacterCount(
              String.fromCharCodes(currentRunes.take(length)),
            ) >=
            3) {
      return String.fromCharCodes(currentRunes.skip(length)).trim();
    }
  }

  return current;
}

TranscriptScore scoreTranscript(
  List<String> texts, {
  required int sampleCount,
}) {
  if (texts.isEmpty) {
    return const TranscriptScore(
      texts: <String>[],
      score: double.negativeInfinity,
      isLowQuality: true,
    );
  }

  final durationSeconds = sampleCount / _sampleRate;
  var meaningfulTotal = 0;
  var shortSegments = 0;
  for (final text in texts) {
    final count = _meaningfulCharacterCount(text);
    meaningfulTotal += count;
    if (count <= 2) {
      shortSegments += 1;
    }
  }

  final shortRatio = shortSegments / texts.length;
  final averageLength = meaningfulTotal / texts.length;
  final charDensity = durationSeconds <= 0
      ? 0.0
      : meaningfulTotal / durationSeconds;
  final score = meaningfulTotal + averageLength * 8 - shortRatio * 80;

  if (texts.length >= 6 && shortRatio >= 0.65 && averageLength < 4) {
    return TranscriptScore(texts: texts, score: score, isLowQuality: true);
  }

  if (durationSeconds >= 60 && meaningfulTotal < durationSeconds * 0.4) {
    return TranscriptScore(texts: texts, score: score, isLowQuality: true);
  }

  if (durationSeconds >= 30 && charDensity < 0.25) {
    return TranscriptScore(texts: texts, score: score, isLowQuality: true);
  }

  return TranscriptScore(texts: texts, score: score, isLowQuality: false);
}

bool shouldRunVadFallback(TranscriptScore fixedCandidate) {
  return fixedCandidate.isLowQuality;
}

TranscriptScore chooseTranscriptCandidate({
  required TranscriptScore fixedCandidate,
  required TranscriptScore vadCandidate,
}) {
  return vadCandidate.score > fixedCandidate.score
      ? vadCandidate
      : fixedCandidate;
}

String _formatIntList(Iterable<int> values) {
  return values.join(',');
}

int _meaningfulCharacterCount(String text) {
  var count = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x4E00 && rune <= 0x9FFF)) {
      count += 1;
    }
  }
  return count;
}

class IndexedAudioChunk {
  const IndexedAudioChunk({required this.index, required this.samples});

  final int index;
  final Float32List samples;
}

class IndexedTranscript {
  const IndexedTranscript({required this.index, required this.text});

  final int index;
  final String text;
}

class TranscriptScore {
  const TranscriptScore({
    required this.texts,
    required this.score,
    required this.isLowQuality,
  });

  final List<String> texts;
  final double score;
  final bool isLowQuality;

  int get meaningfulCharacterCount {
    var total = 0;
    for (final text in texts) {
      total += _meaningfulCharacterCount(text);
    }
    return total;
  }
}

class FixedChunkDecodeProfile {
  const FixedChunkDecodeProfile({
    required this.workerIndex,
    required this.chunkIndex,
    required this.decodeMs,
    required this.sampleCount,
    required this.charCount,
  });

  final int workerIndex;
  final int chunkIndex;
  final int decodeMs;
  final int sampleCount;
  final int charCount;
}

class FixedWorkerDecodeProfile {
  const FixedWorkerDecodeProfile({
    required this.workerIndex,
    required this.recognizerInitMs,
    required this.totalMs,
    required this.chunks,
  });

  final int workerIndex;
  final int recognizerInitMs;
  final int totalMs;
  final List<FixedChunkDecodeProfile> chunks;

  int get chunkDecodeMs {
    var total = 0;
    for (final chunk in chunks) {
      total += chunk.decodeMs;
    }
    return total;
  }
}

class FixedDecodeProfile {
  const FixedDecodeProfile({required this.workers});

  final List<FixedWorkerDecodeProfile> workers;

  List<FixedChunkDecodeProfile> get chunks {
    final all = <FixedChunkDecodeProfile>[
      for (final worker in workers) ...worker.chunks,
    ]..sort((left, right) => left.chunkIndex.compareTo(right.chunkIndex));
    return all;
  }

  int get recognizerInitMs {
    var maxMs = 0;
    for (final worker in workers) {
      maxMs = math.max(maxMs, worker.recognizerInitMs);
    }
    return maxMs;
  }

  int get recognizerInitSumMs {
    var total = 0;
    for (final worker in workers) {
      total += worker.recognizerInitMs;
    }
    return total;
  }

  FixedChunkDecodeProfile? get slowestChunk {
    FixedChunkDecodeProfile? slowest;
    for (final chunk in chunks) {
      if (slowest == null || chunk.decodeMs > slowest.decodeMs) {
        slowest = chunk;
      }
    }
    return slowest;
  }

  String get workerSummary {
    if (workers.isEmpty) {
      return 'none';
    }

    return workers
        .map(
          (worker) =>
              '#${worker.workerIndex}:chunks=${worker.chunks.length} '
              'indexes=${_formatIntList(worker.chunks.map((chunk) => chunk.chunkIndex))} '
              'init=${worker.recognizerInitMs}ms '
              'chunkDecode=${worker.chunkDecodeMs}ms total=${worker.totalMs}ms',
        )
        .join('; ');
  }

  List<String> chunkTimingLines({int entriesPerLine = 12}) {
    final all = chunks;
    if (all.isEmpty) {
      return const <String>['[ASR import] fixedProfile chunks none'];
    }

    final lines = <String>[];
    for (var start = 0; start < all.length; start += entriesPerLine) {
      final end = math.min(start + entriesPerLine, all.length);
      final entries = all
          .sublist(start, end)
          .map(
            (chunk) =>
                '#${chunk.chunkIndex}:${chunk.decodeMs}ms'
                '(w${chunk.workerIndex},chars=${chunk.charCount})',
          )
          .join(' ');
      lines.add('[ASR import] fixedProfile chunks[$start-${end - 1}] $entries');
    }
    return lines;
  }
}

class _FixedDecodeRun {
  const _FixedDecodeRun({required this.texts, required this.profile});

  final List<String> texts;
  final FixedDecodeProfile profile;
}

class _FixedChunkBatchResult {
  const _FixedChunkBatchResult({
    required this.transcripts,
    required this.workerProfile,
  });

  final List<IndexedTranscript> transcripts;
  final FixedWorkerDecodeProfile workerProfile;
}

class _IndexedDecodeResult {
  const _IndexedDecodeResult({
    required this.transcripts,
    required this.chunkProfiles,
  });

  final List<IndexedTranscript> transcripts;
  final List<FixedChunkDecodeProfile> chunkProfiles;
}

class _FixedChunkBatchPayload {
  const _FixedChunkBatchPayload({
    required this.workerIndex,
    required this.modelPath,
    required this.tokensPath,
    required this.provider,
    required this.chunks,
  });

  final int workerIndex;
  final String modelPath;
  final String tokensPath;
  final String provider;
  final List<IndexedAudioChunk> chunks;
}

class _FixedDecodeResult {
  const _FixedDecodeResult({
    required this.texts,
    required this.profile,
    required this.requestedProvider,
    required this.provider,
    required this.fallbackReason,
    required this.qualityRetry,
  });

  final List<String> texts;
  final FixedDecodeProfile profile;
  final String requestedProvider;
  final String provider;
  final String? fallbackReason;
  final bool qualityRetry;

  _FixedDecodeResult withQualityRetry({
    required String selectedProvider,
    required List<String> selectedTexts,
    required FixedDecodeProfile selectedProfile,
    required String fallbackReason,
  }) {
    return _FixedDecodeResult(
      texts: selectedTexts,
      profile: selectedProfile,
      requestedProvider: requestedProvider,
      provider: selectedProvider,
      fallbackReason: fallbackReason,
      qualityRetry: true,
    );
  }
}

class _AsrTimings {
  const _AsrTimings({
    required this.pcmToFloatMs,
    required this.preprocessMs,
    required this.fixedDecodeMs,
    required this.vadDecodeMs,
    required this.totalMs,
  });

  final int pcmToFloatMs;
  final int preprocessMs;
  final int fixedDecodeMs;
  final int vadDecodeMs;
  final int totalMs;
}

class _FileTranscriptionResult {
  const _FileTranscriptionResult({
    required this.texts,
    required this.strategy,
    required this.fixedChunkCount,
    required this.totalFixedChunkCount,
    required this.skippedSilentChunkCount,
    required this.workerCount,
    required this.processorCount,
    required this.isIOS,
    required this.requestedFixedProvider,
    required this.fixedProvider,
    required this.fixedProviderFallbackReason,
    required this.fixedProviderQualityRetry,
    required this.asrProfileId,
    required this.preprocessingMode,
    required this.sampleCount,
    required this.fixedCandidate,
    required this.fixedDecodeProfile,
    required this.vadCandidate,
    required this.vadSpeechSegmentCount,
    required this.vadFallbackRun,
    required this.vadFallbackSelected,
    required this.timings,
  });

  final List<String> texts;
  final String strategy;
  final int fixedChunkCount;
  final int totalFixedChunkCount;
  final int skippedSilentChunkCount;
  final int workerCount;
  final int processorCount;
  final bool isIOS;
  final String requestedFixedProvider;
  final String fixedProvider;
  final String? fixedProviderFallbackReason;
  final bool fixedProviderQualityRetry;
  final String asrProfileId;
  final FileAudioPreprocessingMode preprocessingMode;
  final int sampleCount;
  final TranscriptScore fixedCandidate;
  final FixedDecodeProfile fixedDecodeProfile;
  final TranscriptScore? vadCandidate;
  final int vadSpeechSegmentCount;
  final bool vadFallbackRun;
  final bool vadFallbackSelected;
  final _AsrTimings timings;

  TranscriptScore get selectedCandidate {
    if (vadFallbackSelected) {
      return vadCandidate ?? fixedCandidate;
    }
    return fixedCandidate;
  }

  List<String> debugLines(String sourceName) {
    final name = sourceName.replaceAll('\n', ' ');
    final audioSeconds = sampleCount / _sampleRate;
    final vad = vadCandidate;
    final slowestChunk = fixedDecodeProfile.slowestChunk;
    return <String>[
      '[ASR import] result file=$name asrProfile=$asrProfileId '
          'strategy=$strategy selectedSegments=${texts.length}',
      '[ASR import] audio sampleRate=$_sampleRate samples=$sampleCount '
          'duration=${audioSeconds.toStringAsFixed(2)}s platform='
          '${isIOS ? 'ios' : 'other'} processors=$processorCount',
      '[ASR import] chunks fixedWindow=${_fixedChunkSamples ~/ _sampleRate}s '
          'overlap=${_fileChunkOverlapSamples ~/ _sampleRate}s '
          'vadFallbackWindow=${_vadFallbackChunkSamples ~/ _sampleRate}s '
          'totalFixed=$totalFixedChunkCount decodedFixed=$fixedChunkCount '
          'skippedSilent=$skippedSilentChunkCount workers=$workerCount '
          'parallelMinChunks=$_parallelDecodeMinChunks '
          'workerThreads=$_parallelRecognizerThreads serialThreads=$_recognizerThreads',
      '[ASR import] provider fixedRequested=$requestedFixedProvider '
          'fixedUsed=$fixedProvider qualityRetry=$fixedProviderQualityRetry '
          'fallbackReason=${fixedProviderFallbackReason ?? 'none'} '
          'vadDecodeProvider=$_cpuProvider',
      '[ASR import] timing preprocessMode=${preprocessingMode.name} '
          'total=${timings.totalMs}ms '
          'pcmToFloat=${timings.pcmToFloatMs}ms '
          'preprocess=${timings.preprocessMs}ms '
          'fixedDecode=${timings.fixedDecodeMs}ms '
          'vadDecode=${timings.vadDecodeMs}ms',
      '[ASR import] fixedProfile recognizerInitMs=${fixedDecodeProfile.recognizerInitMs}ms '
          'recognizerInitSum=${fixedDecodeProfile.recognizerInitSumMs}ms '
          'slowestChunk=${slowestChunk == null ? 'none' : '#${slowestChunk.chunkIndex}:${slowestChunk.decodeMs}ms(w${slowestChunk.workerIndex},chars=${slowestChunk.charCount})'}',
      '[ASR import] fixedProfile workers ${fixedDecodeProfile.workerSummary}',
      ...fixedDecodeProfile.chunkTimingLines(),
      '[ASR import] fixedCandidate score=${fixedCandidate.score.toStringAsFixed(2)} '
          'lowQuality=${fixedCandidate.isLowQuality} '
          'segments=${fixedCandidate.texts.length} '
          'chars=${fixedCandidate.meaningfulCharacterCount}',
      if (vad == null)
        '[ASR import] vadCandidate run=$vadFallbackRun selected=$vadFallbackSelected '
            'speechSegments=$vadSpeechSegmentCount score=n/a lowQuality=n/a '
            'segments=0 chars=0'
      else
        '[ASR import] vadCandidate run=$vadFallbackRun selected=$vadFallbackSelected '
            'speechSegments=$vadSpeechSegmentCount '
            'score=${vad.score.toStringAsFixed(2)} '
            'lowQuality=${vad.isLowQuality} segments=${vad.texts.length} '
            'chars=${vad.meaningfulCharacterCount}',
    ];
  }
}

sherpa.OfflineRecognizer _createSenseVoiceRecognizer({
  required String modelPath,
  required String tokensPath,
  required int numThreads,
  required String provider,
}) {
  return sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: modelPath,
          language: 'zh',
          useInverseTextNormalization: true,
        ),
        tokens: tokensPath,
        numThreads: numThreads,
        provider: provider,
        debug: false,
      ),
    ),
  );
}

String _compactError(Object error) {
  return error.toString().replaceAll('\n', ' ').trim();
}

String _decodeSegment(
  sherpa.OfflineRecognizer recognizer,
  Float32List samples,
) {
  if (samples.isEmpty) {
    return '';
  }

  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream.free();
  }
}

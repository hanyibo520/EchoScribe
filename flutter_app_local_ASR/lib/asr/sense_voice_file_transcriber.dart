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
const int _parallelDecodeWorkers = 2;
const int _parallelRecognizerThreads = 2;
const double _digitalSilencePeak = 2.0 / 32768.0;
const int _digitalSilenceMaxLoudSamples = 8;
const String _cpuProvider = 'cpu';
const String _coreMlProvider = 'coreml';

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
  }) async {
    if (pcm16Audio.isEmpty) {
      return const <AsrSegment>[];
    }

    final files = modelFiles ?? await _senseVoiceModelFiles();
    final result = await Isolate.run(
      () => _transcribeSenseVoiceTextSegments(
        pcm16Audio: pcm16Audio,
        modelPath: files.model,
        tokensPath: files.tokens,
        vadPath: files.vad,
      ),
    );
    for (final line in result.debugLines(sourceName)) {
      debugPrint(line);
    }

    final segments = <AsrSegment>[];
    for (final text in result.texts) {
      segments.add(
        AsrSegment(
          index: segments.length + 1,
          text: text,
          createdAt: DateTime.now(),
          engineName: 'Sherpa-ONNX SenseVoice file: $sourceName',
        ),
      );
    }
    return segments;
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

Future<_FileTranscriptionResult> _transcribeSenseVoiceTextSegments({
  required Uint8List pcm16Audio,
  required String modelPath,
  required String tokensPath,
  required String vadPath,
}) async {
  sherpa.initBindings();

  final totalWatch = Stopwatch()..start();
  final pcmWatch = Stopwatch()..start();
  final rawSamples = pcm16BytesToFloat32(pcm16Audio);
  pcmWatch.stop();

  final preprocessWatch = Stopwatch()..start();
  final samples = conditionSpeechSamples(
    rawSamples,
    sampleRate: _sampleRate,
    targetPeak: _targetPeak,
    maxGain: _maxGain,
  );
  preprocessWatch.stop();

  final fixedChunks = decodableFixedOverlapChunks(
    samples: samples,
    rawSamples: rawSamples,
  );
  final totalFixedChunkCount = fixedOverlapChunks(samples).length;
  final processorCount = Platform.numberOfProcessors;
  final isIOS = Platform.isIOS;
  final preferredFixedProvider = selectFixedDecodeProvider(isIOS: isIOS);
  final workerCount = selectFixedDecodeWorkerCount(
    chunkCount: fixedChunks.length,
    processorCount: processorCount,
    isIOS: isIOS,
  );
  final fixedWatch = Stopwatch()..start();
  var fixedDecodeResult = await _decodeFixedChunksWithProviderFallback(
    chunks: fixedChunks,
    modelPath: modelPath,
    tokensPath: tokensPath,
    workerCount: workerCount,
    preferredProvider: preferredFixedProvider,
  );

  var fixedCandidate = scoreTranscript(
    fixedDecodeResult.texts,
    sampleCount: samples.length,
  );
  if (fixedDecodeResult.provider == _coreMlProvider &&
      fixedCandidate.isLowQuality) {
    final cpuRun = await _decodeFixedChunks(
      chunks: fixedChunks,
      modelPath: modelPath,
      tokensPath: tokensPath,
      workerCount: workerCount,
      provider: _cpuProvider,
    );
    final cpuCandidate = scoreTranscript(
      cpuRun.texts,
      sampleCount: samples.length,
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
    if (cpuCandidate.score >= fixedCandidate.score) {
      fixedCandidate = cpuCandidate;
    }
  }
  fixedWatch.stop();
  final skippedSilentChunkCount = totalFixedChunkCount - fixedChunks.length;

  if (!shouldRunVadFallback(fixedCandidate)) {
    totalWatch.stop();
    return _FileTranscriptionResult(
      texts: fixedCandidate.texts,
      strategy: workerCount > 1
          ? 'fixed_parallel_${workerCount}w'
          : 'fixed_serial',
      fixedChunkCount: fixedChunks.length,
      totalFixedChunkCount: totalFixedChunkCount,
      skippedSilentChunkCount: skippedSilentChunkCount,
      workerCount: workerCount,
      processorCount: processorCount,
      isIOS: isIOS,
      requestedFixedProvider: fixedDecodeResult.requestedProvider,
      fixedProvider: fixedDecodeResult.provider,
      fixedProviderFallbackReason: fixedDecodeResult.fallbackReason,
      fixedProviderQualityRetry: fixedDecodeResult.qualityRetry,
      sampleCount: samples.length,
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
    final speechSegments = _detectSpeechSegments(samples, vad);
    vadSpeechSegmentCount = speechSegments.length;
    if (speechSegments.isEmpty) {
      vadWatch.stop();
      totalWatch.stop();
      return _FileTranscriptionResult(
        texts: fixedCandidate.texts,
        strategy: 'fixed_low_quality_no_vad_speech',
        fixedChunkCount: fixedChunks.length,
        totalFixedChunkCount: totalFixedChunkCount,
        skippedSilentChunkCount: skippedSilentChunkCount,
        workerCount: workerCount,
        processorCount: processorCount,
        isIOS: isIOS,
        requestedFixedProvider: fixedDecodeResult.requestedProvider,
        fixedProvider: fixedDecodeResult.provider,
        fixedProviderFallbackReason: fixedDecodeResult.fallbackReason,
        fixedProviderQualityRetry: fixedDecodeResult.qualityRetry,
        sampleCount: samples.length,
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
        sampleCount: samples.length,
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
    fixedChunkCount: fixedChunks.length,
    totalFixedChunkCount: totalFixedChunkCount,
    skippedSilentChunkCount: skippedSilentChunkCount,
    workerCount: workerCount,
    processorCount: processorCount,
    isIOS: isIOS,
    requestedFixedProvider: fixedDecodeResult.requestedProvider,
    fixedProvider: fixedDecodeResult.provider,
    fixedProviderFallbackReason: fixedDecodeResult.fallbackReason,
    fixedProviderQualityRetry: fixedDecodeResult.qualityRetry,
    sampleCount: samples.length,
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

int selectFixedDecodeWorkerCount({
  required int chunkCount,
  required int processorCount,
  required bool isIOS,
}) {
  if (!isIOS || chunkCount < _parallelDecodeMinChunks) {
    return 1;
  }
  if (processorCount < _parallelDecodeWorkers * _parallelRecognizerThreads) {
    return 1;
  }
  return _parallelDecodeWorkers;
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

Future<_FixedDecodeResult> _decodeFixedChunksWithProviderFallback({
  required List<IndexedAudioChunk> chunks,
  required String modelPath,
  required String tokensPath,
  required int workerCount,
  required String preferredProvider,
}) async {
  if (preferredProvider == _cpuProvider) {
    final run = await _decodeFixedChunks(
      chunks: chunks,
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

  final batches = splitFixedDecodeBatches(chunks, workerCount);
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
  int workerCount,
) {
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
        samples: Float32List.fromList(chunk.samples),
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
  final int sampleCount;
  final TranscriptScore fixedCandidate;
  final FixedDecodeProfile fixedDecodeProfile;
  final TranscriptScore? vadCandidate;
  final int vadSpeechSegmentCount;
  final bool vadFallbackRun;
  final bool vadFallbackSelected;
  final _AsrTimings timings;

  List<String> debugLines(String sourceName) {
    final name = sourceName.replaceAll('\n', ' ');
    final audioSeconds = sampleCount / _sampleRate;
    final vad = vadCandidate;
    final slowestChunk = fixedDecodeProfile.slowestChunk;
    return <String>[
      '[ASR import] result file=$name strategy=$strategy selectedSegments=${texts.length}',
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
      '[ASR import] timing total=${timings.totalMs}ms '
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

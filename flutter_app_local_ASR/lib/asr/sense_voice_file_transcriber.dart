import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'asr_engine.dart';
import 'audio_utils.dart';
import 'model_store.dart';

const int _sampleRate = 16000;
const double _targetPeak = 0.92;
const double _maxGain = 6.0;
const double _vadBufferSeconds = 35;
const int _vadBlockSamples = _sampleRate * 30;
const int _fallbackChunkSamples = _sampleRate * 25;

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
  }) async {
    if (pcm16Audio.isEmpty) {
      return const <AsrSegment>[];
    }

    final check = await _modelStore.inspect();
    if (!check.isSenseVoiceReady) {
      throw StateError(
        'Missing SenseVoice files: ${check.missingSenseVoiceFiles.join(', ')}',
      );
    }

    final files = check.senseVoiceFiles;
    final recognizedTexts = await Isolate.run(
      () => _transcribeSenseVoiceTextSegments(
        pcm16Audio: pcm16Audio,
        modelPath: files.model,
        tokensPath: files.tokens,
        vadPath: files.vad,
      ),
    );

    final segments = <AsrSegment>[];
    for (final text in recognizedTexts) {
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
}

List<String> _transcribeSenseVoiceTextSegments({
  required Uint8List pcm16Audio,
  required String modelPath,
  required String tokensPath,
  required String vadPath,
}) {
  sherpa.initBindings();

  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: modelPath,
          language: 'zh',
          useInverseTextNormalization: true,
        ),
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
      ),
    ),
  );

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
    final samples = _normalize(pcm16BytesToFloat32(pcm16Audio));
    final speechSegments = _detectSpeechSegments(samples, vad);
    final segmentsToDecode = speechSegments.isEmpty
        ? _fixedChunks(samples)
        : speechSegments;

    final texts = <String>[];
    for (final segmentSamples in segmentsToDecode) {
      final text = _decodeSegment(recognizer, segmentSamples);
      if (text.isNotEmpty) {
        texts.add(text);
      }
    }
    return texts;
  } finally {
    vad.free();
    recognizer.free();
  }
}

Float32List _normalize(Float32List samples) {
  var peak = 0.0;
  for (final sample in samples) {
    peak = math.max(peak, sample.abs());
  }
  if (peak <= 0.0) {
    return samples;
  }

  final gain = math.min(_targetPeak / peak, _maxGain);
  if (gain <= 1.0) {
    return samples;
  }

  final normalized = Float32List(samples.length);
  for (var i = 0; i < samples.length; i += 1) {
    normalized[i] = (samples[i] * gain).clamp(-1.0, 1.0).toDouble();
  }
  return normalized;
}

List<Float32List> _detectSpeechSegments(
  Float32List samples,
  sherpa.VoiceActivityDetector vad,
) {
  final segments = <Float32List>[];
  final windowSize = vad.config.sileroVad.windowSize;

  for (
    var blockStart = 0;
    blockStart < samples.length;
    blockStart += _vadBlockSamples
  ) {
    final blockEnd = math.min(blockStart + _vadBlockSamples, samples.length);
    for (var start = blockStart; start < blockEnd; start += windowSize) {
      final end = math.min(start + windowSize, blockEnd);
      vad.acceptWaveform(Float32List.sublistView(samples, start, end));
      _drainVad(vad, segments);
    }

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

List<Float32List> _fixedChunks(Float32List samples) {
  if (samples.isEmpty) {
    return const <Float32List>[];
  }

  final chunks = <Float32List>[];
  for (var start = 0; start < samples.length; start += _fallbackChunkSamples) {
    final end = math.min(start + _fallbackChunkSamples, samples.length);
    chunks.add(Float32List.sublistView(samples, start, end));
  }
  return chunks;
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

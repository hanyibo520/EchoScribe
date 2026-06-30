import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../asr/asr_engine.dart';
import '../asr/audio_utils.dart';
import '../asr/model_store.dart';

class SherpaSpeakerService {
  SherpaSpeakerService({required ModelStore modelStore})
    : _modelStore = modelStore;

  static const int sampleRate = 16000;
  static const int _numThreads = 2;

  final ModelStore _modelStore;

  Future<AsrAvailability> checkDiarizationAvailability() async {
    final check = await _modelStore.inspect();
    if (check.isSpeakerDiarizationReady) {
      return const AsrAvailability.available();
    }

    return AsrAvailability.unavailable(
      'Missing speaker diarization files: '
      '${check.missingSpeakerDiarizationFiles.join(', ')}',
    );
  }

  Future<AsrAvailability> checkEmbeddingAvailability() async {
    final check = await _modelStore.inspect();
    if (check.isSpeakerEmbeddingReady) {
      return const AsrAvailability.available();
    }

    return AsrAvailability.unavailable(
      'Missing speaker embedding files: '
      '${check.missingSpeakerEmbeddingFiles.join(', ')}',
    );
  }

  Future<List<SpeakerTurnSegment>> diarizePcm16Audio({
    required Uint8List pcm16Audio,
    int audioSampleRate = sampleRate,
    int numClusters = -1,
    double clusteringThreshold = 0.5,
  }) async {
    if (pcm16Audio.isEmpty) {
      return const <SpeakerTurnSegment>[];
    }
    _checkSampleRate(audioSampleRate);

    final check = await _modelStore.inspect();
    if (!check.isSpeakerDiarizationReady) {
      throw StateError(
        'Missing speaker diarization files: '
        '${check.missingSpeakerDiarizationFiles.join(', ')}',
      );
    }

    return Isolate.run(
      () => _diarizePcm16Audio(
        pcm16Audio: pcm16Audio,
        segmentationModelPath: check.speakerDiarizationFiles.segmentation,
        embeddingModelPath: check.speakerDiarizationFiles.embedding,
        numClusters: numClusters,
        clusteringThreshold: clusteringThreshold,
      ),
    );
  }

  Future<SpeakerEmbeddingVector> computeEmbeddingFromPcm16Audio({
    required Uint8List pcm16Audio,
    int audioSampleRate = sampleRate,
  }) async {
    if (pcm16Audio.isEmpty) {
      return SpeakerEmbeddingVector.empty();
    }
    _checkSampleRate(audioSampleRate);

    final check = await _modelStore.inspect();
    if (!check.isSpeakerEmbeddingReady) {
      throw StateError(
        'Missing speaker embedding files: '
        '${check.missingSpeakerEmbeddingFiles.join(', ')}',
      );
    }

    return Isolate.run(
      () => _computeEmbeddingFromPcm16Audio(
        pcm16Audio: pcm16Audio,
        embeddingModelPath: check.speakerEmbeddingFiles.model,
      ),
    );
  }

  void _checkSampleRate(int audioSampleRate) {
    if (audioSampleRate != sampleRate) {
      throw ArgumentError.value(
        audioSampleRate,
        'audioSampleRate',
        'Sherpa speaker models expect 16 kHz mono PCM audio',
      );
    }
  }
}

class SpeakerTurnSegment {
  const SpeakerTurnSegment({
    required this.startTimeSeconds,
    required this.endTimeSeconds,
    required this.speakerIndex,
  });

  final double startTimeSeconds;
  final double endTimeSeconds;
  final int speakerIndex;

  double get durationSeconds => endTimeSeconds - startTimeSeconds;
  String get speakerLabel => 'S${speakerIndex + 1}';
}

class SpeakerEmbeddingVector {
  const SpeakerEmbeddingVector(this.values);

  factory SpeakerEmbeddingVector.empty() {
    return SpeakerEmbeddingVector(Float32List(0));
  }

  final Float32List values;

  int get dimension => values.length;
  bool get isEmpty => values.isEmpty;
}

List<SpeakerTurnSegment> _diarizePcm16Audio({
  required Uint8List pcm16Audio,
  required String segmentationModelPath,
  required String embeddingModelPath,
  required int numClusters,
  required double clusteringThreshold,
}) {
  sherpa.initBindings();
  final samples = conditionSpeechSamples(
    pcm16BytesToFloat32(pcm16Audio),
    sampleRate: SherpaSpeakerService.sampleRate,
  );

  final diarizer = sherpa.OfflineSpeakerDiarization(
    sherpa.OfflineSpeakerDiarizationConfig(
      segmentation: sherpa.OfflineSpeakerSegmentationModelConfig(
        pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
          model: segmentationModelPath,
        ),
        numThreads: SherpaSpeakerService._numThreads,
        debug: false,
      ),
      embedding: sherpa.SpeakerEmbeddingExtractorConfig(
        model: embeddingModelPath,
        numThreads: SherpaSpeakerService._numThreads,
        debug: false,
      ),
      clustering: sherpa.FastClusteringConfig(
        numClusters: numClusters,
        threshold: clusteringThreshold,
      ),
    ),
  );

  try {
    final segments = diarizer.processWithCallback(
      samples: samples,
      callback: (_, _) => 1,
    );
    return [
      for (final segment in segments)
        SpeakerTurnSegment(
          startTimeSeconds: segment.start,
          endTimeSeconds: segment.end,
          speakerIndex: segment.speaker,
        ),
    ];
  } finally {
    diarizer.free();
  }
}

SpeakerEmbeddingVector _computeEmbeddingFromPcm16Audio({
  required Uint8List pcm16Audio,
  required String embeddingModelPath,
}) {
  sherpa.initBindings();
  final samples = conditionSpeechSamples(
    pcm16BytesToFloat32(pcm16Audio),
    sampleRate: SherpaSpeakerService.sampleRate,
  );

  final extractor = sherpa.SpeakerEmbeddingExtractor(
    config: sherpa.SpeakerEmbeddingExtractorConfig(
      model: embeddingModelPath,
      numThreads: SherpaSpeakerService._numThreads,
      debug: false,
    ),
  );
  final stream = extractor.createStream();
  try {
    stream.acceptWaveform(
      samples: samples,
      sampleRate: SherpaSpeakerService.sampleRate,
    );
    stream.inputFinished();
    if (!extractor.isReady(stream)) {
      return SpeakerEmbeddingVector.empty();
    }
    return SpeakerEmbeddingVector(extractor.compute(stream));
  } finally {
    stream.free();
    extractor.free();
  }
}

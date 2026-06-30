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
  static const double defaultSpeakerMatchThreshold = 0.6;
  static const double defaultSpeakerMatchMargin = 0.03;
  static const int _numThreads = 2;

  final ModelStore _modelStore;

  Future<AsrAvailability> checkDiarizationAvailability() async {
    final check = await _modelStore.inspect();
    if (check.isSherpaSpeakerProcessingReady) {
      return const AsrAvailability.available();
    }

    return AsrAvailability.unavailable(
      'Missing speaker processing files: '
      '${[...check.missingSpeakerDiarizationFiles, ...check.missingSpeakerEmbeddingFiles].join(', ')}',
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
    if (!check.isSherpaSpeakerProcessingReady) {
      throw StateError(
        'Missing speaker processing files: '
        '${[...check.missingSpeakerDiarizationFiles, ...check.missingSpeakerEmbeddingFiles].join(', ')}',
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

  Future<String> searchSpeakerEmbedding({
    required Float32List embedding,
    required Map<String, Float32List> referenceEmbeddings,
    double threshold = defaultSpeakerMatchThreshold,
  }) async {
    if (embedding.isEmpty || referenceEmbeddings.isEmpty) {
      return '';
    }

    final dimension = embedding.length;
    final compatibleReferences = <String, Float32List>{
      for (final entry in referenceEmbeddings.entries)
        if (entry.value.length == dimension) entry.key: entry.value,
    };
    if (compatibleReferences.isEmpty) {
      return '';
    }

    return Isolate.run(
      () => _searchSpeakerEmbedding(
        embedding: embedding,
        referenceEmbeddings: compatibleReferences,
        threshold: threshold,
      ),
    );
  }

  Future<SpeakerEmbeddingMatch> findBestSpeakerEmbeddingMatch({
    required Float32List embedding,
    required Map<String, Float32List> referenceEmbeddings,
    double threshold = defaultSpeakerMatchThreshold,
    double margin = defaultSpeakerMatchMargin,
  }) async {
    if (embedding.isEmpty || referenceEmbeddings.isEmpty) {
      return SpeakerEmbeddingMatch.noMatch(
        threshold: threshold,
        margin: margin,
      );
    }

    final dimension = embedding.length;
    final compatibleReferences = <String, Float32List>{
      for (final entry in referenceEmbeddings.entries)
        if (entry.value.length == dimension) entry.key: entry.value,
    };
    if (compatibleReferences.isEmpty) {
      return SpeakerEmbeddingMatch.noMatch(
        threshold: threshold,
        margin: margin,
      );
    }

    return Isolate.run(
      () => _findBestSpeakerEmbeddingMatch(
        embedding: embedding,
        referenceEmbeddings: compatibleReferences,
        threshold: threshold,
        margin: margin,
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

class SpeakerEmbeddingMatch {
  const SpeakerEmbeddingMatch({
    required this.name,
    required this.score,
    required this.runnerUpScore,
    required this.threshold,
    required this.margin,
  });

  factory SpeakerEmbeddingMatch.noMatch({
    required double threshold,
    required double margin,
    double score = 0,
    double runnerUpScore = 0,
  }) {
    return SpeakerEmbeddingMatch(
      name: '',
      score: score,
      runnerUpScore: runnerUpScore,
      threshold: threshold,
      margin: margin,
    );
  }

  final String name;
  final double score;
  final double runnerUpScore;
  final double threshold;
  final double margin;

  bool get isAccepted =>
      name.isNotEmpty && score >= threshold && score - runnerUpScore >= margin;
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

String _searchSpeakerEmbedding({
  required Float32List embedding,
  required Map<String, Float32List> referenceEmbeddings,
  required double threshold,
}) {
  sherpa.initBindings();
  final manager = sherpa.SpeakerEmbeddingManager(embedding.length);
  try {
    for (final entry in referenceEmbeddings.entries) {
      manager.add(name: entry.key, embedding: entry.value);
    }
    return manager.search(embedding: embedding, threshold: threshold);
  } finally {
    manager.free();
  }
}

SpeakerEmbeddingMatch _findBestSpeakerEmbeddingMatch({
  required Float32List embedding,
  required Map<String, Float32List> referenceEmbeddings,
  required double threshold,
  required double margin,
}) {
  sherpa.initBindings();
  final manager = sherpa.SpeakerEmbeddingManager(embedding.length);
  try {
    for (final entry in referenceEmbeddings.entries) {
      manager.add(name: entry.key, embedding: entry.value);
    }

    var bestName = '';
    var bestScore = 0.0;
    var runnerUpScore = 0.0;
    for (final name in referenceEmbeddings.keys) {
      final score = _estimateVerificationScore(
        manager: manager,
        name: name,
        embedding: embedding,
      );
      if (score > bestScore) {
        runnerUpScore = bestScore;
        bestScore = score;
        bestName = name;
      } else if (score > runnerUpScore) {
        runnerUpScore = score;
      }
    }

    final match = SpeakerEmbeddingMatch(
      name: bestName,
      score: bestScore,
      runnerUpScore: runnerUpScore,
      threshold: threshold,
      margin: margin,
    );
    return match.isAccepted
        ? match
        : SpeakerEmbeddingMatch.noMatch(
            threshold: threshold,
            margin: margin,
            score: bestScore,
            runnerUpScore: runnerUpScore,
          );
  } finally {
    manager.free();
  }
}

double _estimateVerificationScore({
  required sherpa.SpeakerEmbeddingManager manager,
  required String name,
  required Float32List embedding,
}) {
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 14; i += 1) {
    final mid = (low + high) / 2;
    if (manager.verify(name: name, embedding: embedding, threshold: mid)) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return low;
}

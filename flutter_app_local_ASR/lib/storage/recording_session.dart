import 'dart:typed_data';

import '../asr/asr_engine.dart';

enum RecordingSourceType { live, import }

class RecordingSegment {
  const RecordingSegment({
    required this.index,
    required this.text,
    required this.createdAt,
    required this.engineName,
  });

  final int index;
  final String text;
  final DateTime createdAt;
  final String engineName;

  factory RecordingSegment.fromAsr(AsrSegment segment) {
    return RecordingSegment(
      index: segment.index,
      text: segment.text,
      createdAt: segment.createdAt,
      engineName: segment.engineName,
    );
  }

  AsrSegment toAsrSegment() {
    return AsrSegment(
      index: index,
      text: text,
      createdAt: createdAt,
      engineName: engineName,
    );
  }

  Map<String, Object?> toMap(int recordingId) {
    return {
      'recording_id': recordingId,
      'segment_index': index,
      'text': text,
      'created_at': createdAt.millisecondsSinceEpoch,
      'engine_name': engineName,
    };
  }

  factory RecordingSegment.fromMap(Map<String, Object?> map) {
    return RecordingSegment(
      index: map['segment_index']! as int,
      text: map['text']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      engineName: map['engine_name']! as String,
    );
  }
}

class RecordingSession {
  const RecordingSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.endedAt,
    required this.segments,
    this.engineName,
    this.sourceType = RecordingSourceType.live,
    this.audioPath,
    this.audioSampleRate,
    this.audioDurationMs,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime endedAt;
  final String? engineName;
  final RecordingSourceType sourceType;
  final String? audioPath;
  final int? audioSampleRate;
  final int? audioDurationMs;
  final List<RecordingSegment> segments;

  bool get hasAudio => audioPath != null && audioPath!.isNotEmpty;

  String get previewText {
    if (segments.isEmpty) {
      return '';
    }
    final ordered = [...segments]..sort((a, b) => a.index.compareTo(b.index));
    return ordered.map((segment) => segment.text).join(' ');
  }

  List<AsrSegment> get asrSegments {
    final ordered = [...segments]..sort((a, b) => a.index.compareTo(b.index));
    return ordered.map((segment) => segment.toAsrSegment()).toList();
  }

  String fullTranscript() {
    return asrSegments.map((segment) => segment.text).join('\n');
  }

  factory RecordingSession.fromMaps({
    required Map<String, Object?> recording,
    required List<Map<String, Object?>> segmentMaps,
  }) {
    final segments = segmentMaps.map(RecordingSegment.fromMap).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return RecordingSession(
      id: recording['id']! as int,
      title: recording['title']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        recording['created_at']! as int,
      ),
      endedAt: DateTime.fromMillisecondsSinceEpoch(
        recording['ended_at']! as int,
      ),
      engineName: recording['engine_name'] as String?,
      sourceType: recording['source_type'] == 'import'
          ? RecordingSourceType.import
          : RecordingSourceType.live,
      audioPath: recording['audio_path'] as String?,
      audioSampleRate: recording['audio_sample_rate'] as int?,
      audioDurationMs: recording['audio_duration_ms'] as int?,
      segments: segments,
    );
  }
}

class SpeakerTurn {
  const SpeakerTurn({
    this.id,
    required this.recordingId,
    required this.speakerLabel,
    required this.startMs,
    required this.endMs,
  });

  final int? id;
  final int recordingId;
  final String speakerLabel;
  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'recording_id': recordingId,
      'speaker_label': speakerLabel,
      'start_ms': startMs,
      'end_ms': endMs,
    };
  }

  factory SpeakerTurn.fromMap(Map<String, Object?> map) {
    return SpeakerTurn(
      id: map['id'] as int?,
      recordingId: map['recording_id']! as int,
      speakerLabel: map['speaker_label']! as String,
      startMs: map['start_ms']! as int,
      endMs: map['end_ms']! as int,
    );
  }
}

class SpeakerEmbeddingRecord {
  const SpeakerEmbeddingRecord({
    this.id,
    required this.recordingId,
    required this.speakerLabel,
    required this.embedding,
  });

  final int? id;
  final int recordingId;
  final String speakerLabel;
  final Float32List embedding;

  int get dimension => embedding.length;
}

class VoiceProfile {
  const VoiceProfile({
    this.id,
    required this.displayName,
    required this.embedding,
    required this.sampleAudioPath,
    required this.sampleRate,
    required this.durationMs,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  final int? id;
  final String displayName;
  final Float32List embedding;
  final String sampleAudioPath;
  final int sampleRate;
  final int durationMs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  int get dimension => embedding.length;
}

class SpeakerProfileMatch {
  const SpeakerProfileMatch({
    this.id,
    required this.recordingId,
    required this.speakerLabel,
    required this.matchedProfileId,
    required this.displayLabel,
    required this.isSelfMatch,
    required this.threshold,
  });

  final int? id;
  final int recordingId;
  final String speakerLabel;
  final int? matchedProfileId;
  final String displayLabel;
  final bool isSelfMatch;
  final double threshold;

  bool get isProfileMatch => matchedProfileId != null;

  factory SpeakerProfileMatch.fromMap(Map<String, Object?> map) {
    return SpeakerProfileMatch(
      id: map['id'] as int?,
      recordingId: map['recording_id']! as int,
      speakerLabel: map['speaker_label']! as String,
      matchedProfileId: map['matched_profile_id'] as int?,
      displayLabel: map['display_label']! as String,
      isSelfMatch: (map['is_self_match']! as int) == 1,
      threshold: (map['threshold']! as num).toDouble(),
    );
  }
}

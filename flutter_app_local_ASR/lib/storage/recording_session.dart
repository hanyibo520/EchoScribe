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
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
      ),
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
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime endedAt;
  final String? engineName;
  final RecordingSourceType sourceType;
  final List<RecordingSegment> segments;

  String get previewText {
    if (segments.isEmpty) {
      return '';
    }
    final ordered = [...segments]
      ..sort((a, b) => a.index.compareTo(b.index));
    return ordered.map((segment) => segment.text).join(' ');
  }

  List<AsrSegment> get asrSegments {
    final ordered = [...segments]
      ..sort((a, b) => a.index.compareTo(b.index));
    return ordered.map((segment) => segment.toAsrSegment()).toList();
  }

  String fullTranscript() {
    return asrSegments.map((segment) => segment.text).join('\n');
  }

  factory RecordingSession.fromMaps({
    required Map<String, Object?> recording,
    required List<Map<String, Object?>> segmentMaps,
  }) {
    final segments = segmentMaps
        .map(RecordingSegment.fromMap)
        .toList()
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
      segments: segments,
    );
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/storage/recording_session.dart';

void main() {
  test('RecordingSession maps optional audio metadata', () {
    final session = RecordingSession.fromMaps(
      recording: <String, Object?>{
        'id': 7,
        'title': 'Meeting 7',
        'created_at': 1000,
        'ended_at': 2000,
        'engine_name': 'Sherpa-ONNX SenseVoice',
        'source_type': 'live',
        'audio_path': '/tmp/sample.wav',
        'audio_sample_rate': 16000,
        'audio_duration_ms': 4500,
      },
      segmentMaps: const <Map<String, Object?>>[],
    );

    expect(session.hasAudio, isTrue);
    expect(session.audioPath, '/tmp/sample.wav');
    expect(session.audioSampleRate, 16000);
    expect(session.audioDurationMs, 4500);
  });

  test('speaker records carry timeline and anonymous embedding values', () {
    final turn = SpeakerTurn(
      recordingId: 3,
      speakerLabel: 'Speaker 1',
      startMs: 1200,
      endMs: 2800,
    );
    final embedding = SpeakerEmbeddingRecord(
      recordingId: 3,
      speakerLabel: 'Speaker 1',
      embedding: Float32List.fromList(<double>[0.1, -0.2, 0.3]),
    );

    expect(turn.durationMs, 1600);
    expect(turn.toMap()['speaker_label'], 'Speaker 1');
    expect(embedding.dimension, 3);
  });
}

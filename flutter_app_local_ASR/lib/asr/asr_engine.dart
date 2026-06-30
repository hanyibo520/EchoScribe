abstract class AsrEngine {
  String get name;
  Stream<AsrSegment> get segments;
  Stream<AsrPartial> get partials;
  Stream<String> get status;

  Future<AsrAvailability> checkAvailability();
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

class CapturedRecordingAudio {
  const CapturedRecordingAudio({
    required this.path,
    required this.sampleRate,
    required this.durationMs,
    required this.byteLength,
  });

  final String path;
  final int sampleRate;
  final int durationMs;
  final int byteLength;
}

abstract class CapturedAudioAsrEngine {
  Future<CapturedRecordingAudio?> takeLastCapturedAudio();
}

class AsrAvailability {
  const AsrAvailability.available() : reason = null;
  const AsrAvailability.unavailable(this.reason);

  final String? reason;

  bool get isAvailable => reason == null;
}

class AsrSegment {
  const AsrSegment({
    required this.index,
    required this.text,
    required this.createdAt,
    required this.engineName,
  });

  final int index;
  final String text;
  final DateTime createdAt;
  final String engineName;
}

class AsrPartial {
  const AsrPartial({
    required this.text,
    required this.updatedAt,
    required this.engineName,
  });

  final String text;
  final DateTime updatedAt;
  final String engineName;
}

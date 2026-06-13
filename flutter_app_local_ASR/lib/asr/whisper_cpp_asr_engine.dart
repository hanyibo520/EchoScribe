import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../native/local_native_bridge.dart';
import 'asr_engine.dart';
import 'model_store.dart';

class WhisperCppAsrEngine implements AsrEngine {
  WhisperCppAsrEngine({
    required ModelStore modelStore,
    LocalNativeBridge? nativeBridge,
  }) : _modelStore = modelStore,
       _nativeBridge = nativeBridge ?? LocalNativeBridge.instance;

  final ModelStore _modelStore;
  final LocalNativeBridge _nativeBridge;
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<AsrSegment> _segments =
      StreamController<AsrSegment>.broadcast();
  final StreamController<AsrPartial> _partials =
      StreamController<AsrPartial>.broadcast();
  final StreamController<String> _status = StreamController<String>.broadcast();
  final BytesBuilder _audioBuffer = BytesBuilder(copy: false);

  static const int _sampleRate = 16000;

  StreamSubscription<Uint8List>? _audioSubscription;
  bool _isRecording = false;
  int _segmentIndex = 0;

  @override
  String get name => 'whisper.cpp';

  @override
  Stream<AsrSegment> get segments => _segments.stream;

  @override
  Stream<AsrPartial> get partials => _partials.stream;

  @override
  Stream<String> get status => _status.stream;

  @override
  Future<AsrAvailability> checkAvailability() async {
    final check = await _modelStore.inspect();
    if (!check.isWhisperModelReady) {
      return AsrAvailability.unavailable(
        'Missing whisper.cpp model: ${check.whisperModelPath}',
      );
    }

    final bridge = await _nativeBridge.checkWhisperCpp(
      modelPath: check.whisperModelPath,
    );
    if (!bridge.isAvailable) {
      return AsrAvailability.unavailable(bridge.reason);
    }

    return const AsrAvailability.available();
  }

  @override
  Future<void> start() async {
    if (_isRecording) {
      return;
    }

    final availability = await checkAvailability();
    if (!availability.isAvailable) {
      throw StateError(availability.reason ?? 'whisper.cpp is not available');
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission denied');
    }

    const encoder = AudioEncoder.pcm16bits;
    if (!await _recorder.isEncoderSupported(encoder)) {
      throw StateError('PCM16 audio stream is not supported on this device');
    }

    _audioBuffer.clear();
    const config = RecordConfig(
      encoder: encoder,
      sampleRate: _sampleRate,
      numChannels: 1,
      streamBufferSize: 4096,
    );
    final audioStream = await _recorder.startStream(config);
    _audioSubscription = audioStream.listen(
      _audioBuffer.add,
      onError: (Object error) => _status.add(error.toString()),
      onDone: () => _status.add('Audio stream stopped'),
    );

    _isRecording = true;
    _status.add('Listening with whisper.cpp');
  }

  @override
  Future<void> stop() async {
    if (!_isRecording) {
      return;
    }

    _isRecording = false;
    await _recorder.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    final audio = _audioBuffer.takeBytes();
    if (audio.isEmpty) {
      _status.add('Stopped');
      return;
    }

    _status.add('Transcribing with whisper.cpp');
    try {
      final check = await _modelStore.inspect();
      final text = await _nativeBridge.transcribeWithWhisperCpp(
        modelPath: check.whisperModelPath,
        pcm16Audio: audio,
        sampleRate: _sampleRate,
        languageCode: 'zh',
      );
      final trimmed = text.trim();
      if (trimmed.isNotEmpty) {
        _segmentIndex += 1;
        _segments.add(
          AsrSegment(
            index: _segmentIndex,
            text: trimmed,
            createdAt: DateTime.now(),
            engineName: name,
          ),
        );
      }
      _status.add('Stopped');
    } catch (error) {
      _status.add('whisper.cpp transcription failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    if (_isRecording) {
      await stop();
    }
    await _audioSubscription?.cancel();
    await _recorder.dispose();
    await _segments.close();
    await _partials.close();
    await _status.close();
  }
}

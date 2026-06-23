import 'dart:async';

import 'package:record/record.dart';

import '../native/local_native_bridge.dart';
import 'asr_engine.dart';
import 'model_store.dart';

class MoonshineAsrEngine implements AsrEngine {
  MoonshineAsrEngine({
    required ModelStore modelStore,
    LocalNativeBridge? nativeBridge,
  }) : _modelStore = modelStore,
       _nativeBridge = nativeBridge ?? LocalNativeBridge.instance;

  final ModelStore _modelStore;
  final LocalNativeBridge _nativeBridge;
  final AudioRecorder _permissionRecorder = AudioRecorder();
  final StreamController<AsrSegment> _segments =
      StreamController<AsrSegment>.broadcast();
  final StreamController<AsrPartial> _partials =
      StreamController<AsrPartial>.broadcast();
  final StreamController<String> _status = StreamController<String>.broadcast();

  StreamSubscription<MoonshineAsrNativeEvent>? _eventSubscription;
  bool _isRecording = false;
  int _segmentIndex = 0;
  String _lastPartialText = '';
  String _lastSegmentText = '';

  @override
  String get name => 'Moonshine Tiny Streaming';

  @override
  Stream<AsrSegment> get segments => _segments.stream;

  @override
  Stream<AsrPartial> get partials => _partials.stream;

  @override
  Stream<String> get status => _status.stream;

  @override
  Future<AsrAvailability> checkAvailability() async {
    final check = await _modelStore.inspect();
    if (!check.isMoonshineTinyStreamingReady) {
      return AsrAvailability.unavailable(
        'Missing Moonshine Tiny Streaming files: '
        '${check.missingMoonshineTinyStreamingFiles.join(', ')}',
      );
    }

    final bridge = await _nativeBridge.checkMoonshine(
      modelPath: check.moonshineTinyStreamingFiles.directory,
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
      throw StateError(availability.reason ?? 'Moonshine is not available');
    }

    final hasPermission = await _permissionRecorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission denied');
    }

    final check = await _modelStore.inspect();
    _lastPartialText = '';
    _lastSegmentText = '';
    _eventSubscription ??= _nativeBridge.moonshineEvents.listen(_onEvent);
    await _nativeBridge.startMoonshine(
      modelPath: check.moonshineTinyStreamingFiles.directory,
    );
    _isRecording = true;
    _status.add('Listening with Moonshine Tiny Streaming');
  }

  @override
  Future<void> stop() async {
    if (!_isRecording) {
      return;
    }

    _isRecording = false;
    await _nativeBridge.stopMoonshine();
    _lastPartialText = '';
    _status.add('Stopped');
  }

  @override
  Future<void> dispose() async {
    if (_isRecording) {
      await stop();
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _nativeBridge.disposeMoonshine();
    await _permissionRecorder.dispose();
    await _segments.close();
    await _partials.close();
    await _status.close();
  }

  void _onEvent(MoonshineAsrNativeEvent event) {
    if (!_isRecording && event.type != MoonshineAsrNativeEventType.status) {
      return;
    }

    final text = event.text.trim();
    switch (event.type) {
      case MoonshineAsrNativeEventType.status:
        if (text.isNotEmpty) {
          _status.add(text);
        }
        return;
      case MoonshineAsrNativeEventType.partial:
        if (text.isEmpty || text == _lastPartialText) {
          return;
        }
        _lastPartialText = text;
        _partials.add(
          AsrPartial(text: text, updatedAt: DateTime.now(), engineName: name),
        );
        return;
      case MoonshineAsrNativeEventType.segment:
        if (text.isEmpty || text == _lastSegmentText) {
          return;
        }
        _lastSegmentText = text;
        _lastPartialText = '';
        _segmentIndex += 1;
        _segments.add(
          AsrSegment(
            index: _segmentIndex,
            text: text,
            createdAt: DateTime.now(),
            engineName: name,
          ),
        );
        return;
      case MoonshineAsrNativeEventType.error:
        if (text.isNotEmpty) {
          _status.add('Moonshine failed: $text');
        }
        return;
    }
  }
}

import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'asr_engine.dart';

class SystemAsrEngine implements AsrEngine {
  SystemAsrEngine({this.localeId = 'zh_CN'});

  final String localeId;
  final SpeechToText _speech = SpeechToText();
  final StreamController<AsrSegment> _segments =
      StreamController<AsrSegment>.broadcast();
  final StreamController<AsrPartial> _partials =
      StreamController<AsrPartial>.broadcast();
  final StreamController<String> _status = StreamController<String>.broadcast();

  bool _isInitialized = false;
  bool _isListening = false;
  int _segmentIndex = 0;
  String _lastRecognized = '';
  String _lastEmitted = '';

  @override
  String get name => 'System ASR';

  @override
  Stream<AsrSegment> get segments => _segments.stream;

  @override
  Stream<AsrPartial> get partials => _partials.stream;

  @override
  Stream<String> get status => _status.stream;

  @override
  Future<AsrAvailability> checkAvailability() async {
    return const AsrAvailability.available();
  }

  @override
  Future<void> start() async {
    final ready = await _ensureInitialized();
    if (!ready) {
      throw StateError('System ASR is not available or permission was denied');
    }

    _lastRecognized = '';
    _lastEmitted = '';
    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        onDevice: true,
        listenMode: ListenMode.dictation,
        localeId: localeId,
        listenFor: const Duration(minutes: 30),
        pauseFor: const Duration(seconds: 5),
        cancelOnError: false,
        autoPunctuation: true,
      ),
    );
    _isListening = true;
    _status.add('Listening with system recognizer');
  }

  @override
  Future<void> stop() async {
    if (!_isListening) {
      return;
    }
    await _speech.stop();
    _emitFinalIfNeeded();
    _isListening = false;
    _status.add('Stopped');
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _segments.close();
    await _partials.close();
    await _status.close();
  }

  Future<bool> _ensureInitialized() async {
    if (_isInitialized) {
      return _speech.isAvailable;
    }

    _isInitialized = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
      options: [SpeechToText.androidNoBluetooth, SpeechToText.iosNoBluetooth],
    );
    return _isInitialized;
  }

  void _onResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) {
      return;
    }

    _lastRecognized = words;
    _status.add(result.finalResult ? 'Final result' : 'Partial: $words');
    if (result.finalResult) {
      _emitFinalIfNeeded();
    } else if (words != _lastEmitted) {
      _partials.add(
        AsrPartial(text: words, updatedAt: DateTime.now(), engineName: name),
      );
    }
  }

  void _onStatus(String status) {
    _status.add(status);
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _emitFinalIfNeeded();
      _isListening = false;
    }
  }

  void _onError(SpeechRecognitionError error) {
    _status.add(error.errorMsg);
    if (error.permanent) {
      _isListening = false;
    }
  }

  void _emitFinalIfNeeded() {
    if (_lastRecognized.isEmpty || _lastRecognized == _lastEmitted) {
      return;
    }

    _segmentIndex += 1;
    _lastEmitted = _lastRecognized;
    _segments.add(
      AsrSegment(
        index: _segmentIndex,
        text: _lastRecognized,
        createdAt: DateTime.now(),
        engineName: name,
      ),
    );
  }
}

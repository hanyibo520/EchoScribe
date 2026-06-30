import 'dart:async';
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../audio/pcm16_wav_io.dart';
import '../native/local_native_bridge.dart';
import 'asr_engine.dart';
import 'audio_utils.dart';
import 'model_store.dart';

class SherpaSenseVoiceAsrService implements AsrEngine, CapturedAudioAsrEngine {
  SherpaSenseVoiceAsrService({required ModelStore modelStore})
    : _modelStore = modelStore;

  static const int _sampleRate = 16000;
  static const int _recognizerThreads = 4;
  static const Duration _partialInterval = Duration(milliseconds: 1200);
  static const int _maxPartialSamples = _sampleRate * 4;

  final ModelStore _modelStore;
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<AsrSegment> _segments =
      StreamController<AsrSegment>.broadcast();
  final StreamController<AsrPartial> _partials =
      StreamController<AsrPartial>.broadcast();
  final StreamController<String> _status = StreamController<String>.broadcast();

  @override
  Stream<AsrSegment> get segments => _segments.stream;

  @override
  Stream<AsrPartial> get partials => _partials.stream;

  @override
  Stream<String> get status => _status.stream;

  StreamSubscription<Uint8List>? _audioSubscription;
  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  sherpa.CircularBuffer? _buffer;
  sherpa.VadModelConfig? _vadConfig;
  Pcm16WavFileWriter? _audioWriter;
  CapturedRecordingAudio? _lastCapturedAudio;

  bool _isInitialized = false;
  bool _isRecording = false;
  int _segmentIndex = 0;
  final Float32RingBuffer _partialSamples = Float32RingBuffer(
    capacity: _maxPartialSamples,
  );
  DateTime _lastPartialDecodedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastPartialText = '';

  @override
  String get name => 'Sherpa-ONNX SenseVoice';

  @override
  Future<AsrAvailability> checkAvailability() async {
    final check = await _modelStore.inspect();
    if (check.isSenseVoiceReady) {
      return const AsrAvailability.available();
    }

    return AsrAvailability.unavailable(
      'Missing SenseVoice files: ${check.missingSenseVoiceFiles.join(', ')}',
    );
  }

  @override
  Future<void> start() async {
    if (_isRecording) {
      return;
    }

    _lastCapturedAudio = null;
    await _ensureInitialized();

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission denied');
    }

    const encoder = AudioEncoder.pcm16bits;
    if (!await _recorder.isEncoderSupported(encoder)) {
      throw StateError('PCM16 audio stream is not supported on this device');
    }

    const config = RecordConfig(
      encoder: encoder,
      sampleRate: _sampleRate,
      numChannels: 1,
      streamBufferSize: 4096,
    );

    final writer = await Pcm16WavFileWriter.create(
      path: await _recordingAudioPath(),
      sampleRate: _sampleRate,
    );
    late final Stream<Uint8List> audioStream;
    try {
      audioStream = await _recorder.startStream(config);
    } catch (_) {
      await writer.close();
      rethrow;
    }
    _audioWriter = writer;
    _audioSubscription = audioStream.listen(
      _acceptAudio,
      onError: (Object error) => _status.add(error.toString()),
      onDone: () => _status.add('Audio stream stopped'),
    );

    _segmentIndex = 0;
    _isRecording = true;
    _status.add('Listening with SenseVoice');
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
    final audioFile = await _audioWriter?.close();
    _audioWriter = null;
    _lastCapturedAudio = _capturedAudioFromFile(audioFile);

    _vad?.flush();
    _drainVadSegments();
    _buffer?.reset();
    _vad?.reset();
    _resetPartialPreview();
    _status.add('Stopped');
  }

  @override
  Future<void> dispose() async {
    if (_isRecording) {
      await stop();
    }
    await _audioSubscription?.cancel();
    await _audioWriter?.close();
    _audioWriter = null;
    await _recorder.dispose();
    _recognizer?.free();
    _vad?.free();
    _buffer?.free();
    await _segments.close();
    await _partials.close();
    await _status.close();
  }

  @override
  Future<CapturedRecordingAudio?> takeLastCapturedAudio() async {
    final audio = _lastCapturedAudio;
    _lastCapturedAudio = null;
    return audio;
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    final check = await _modelStore.inspect();
    if (!check.isSenseVoiceReady) {
      throw StateError(
        'Missing SenseVoice files: ${check.missingSenseVoiceFiles.join(', ')}',
      );
    }

    sherpa.initBindings();
    final files = check.senseVoiceFiles;
    final modelConfig = sherpa.OfflineModelConfig(
      senseVoice: sherpa.OfflineSenseVoiceModelConfig(
        model: files.model,
        language: 'zh',
        useInverseTextNormalization: true,
      ),
      tokens: files.tokens,
      numThreads: _recognizerThreads,
      debug: false,
    );
    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(model: modelConfig),
    );

    final sileroVad = sherpa.SileroVadModelConfig(
      model: files.vad,
      minSilenceDuration: 1.0,
      minSpeechDuration: 0.25,
      maxSpeechDuration: 30.0,
    );
    _vadConfig = sherpa.VadModelConfig(
      sileroVad: sileroVad,
      sampleRate: _sampleRate,
      numThreads: 1,
      debug: false,
    );
    _vad = sherpa.VoiceActivityDetector(
      config: _vadConfig!,
      bufferSizeInSeconds: 60,
    );
    _buffer = sherpa.CircularBuffer(capacity: 60 * _sampleRate);

    _isInitialized = true;
    _status.add('SenseVoice initialized');
  }

  void _acceptAudio(Uint8List data) {
    _audioWriter?.append(data);

    final buffer = _buffer;
    final vad = _vad;
    final vadConfig = _vadConfig;
    if (buffer == null || vad == null || vadConfig == null) {
      return;
    }

    final samples = pcm16BytesToFloat32(data);
    buffer.push(samples);
    _appendPartialSamples(samples);
    final windowSize = vadConfig.sileroVad.windowSize;
    while (buffer.size > windowSize) {
      final samples = buffer.get(startIndex: buffer.head, n: windowSize);
      buffer.pop(windowSize);
      vad.acceptWaveform(samples);
      _drainVadSegments();
    }
    if (vad.isDetected()) {
      _emitPartialPreviewIfDue();
    }
  }

  void _drainVadSegments() {
    final recognizer = _recognizer;
    final vad = _vad;
    if (recognizer == null || vad == null) {
      return;
    }

    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      if (segment.samples.isEmpty) {
        continue;
      }

      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: segment.samples, sampleRate: _sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text.trim();
      stream.free();
      _resetPartialPreview();

      if (text.isEmpty) {
        continue;
      }

      _segmentIndex += 1;
      _segments.add(
        AsrSegment(
          index: _segmentIndex,
          text: text,
          createdAt: DateTime.now(),
          engineName: name,
        ),
      );
    }
  }

  void _appendPartialSamples(Float32List samples) {
    _partialSamples.push(samples);
  }

  void _emitPartialPreviewIfDue() {
    final recognizer = _recognizer;
    if (recognizer == null || _partialSamples.length < _sampleRate ~/ 2) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastPartialDecodedAt) < _partialInterval) {
      return;
    }
    _lastPartialDecodedAt = now;

    final stream = recognizer.createStream();
    stream.acceptWaveform(
      samples: _partialSamples.toFloat32List(),
      sampleRate: _sampleRate,
    );
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text.trim();
    stream.free();

    if (text.isEmpty || text == _lastPartialText) {
      return;
    }

    _lastPartialText = text;
    _partials.add(
      AsrPartial(text: text, updatedAt: now, engineName: '$name partial'),
    );
  }

  Future<String> _recordingAudioPath() async {
    final supportPath = await LocalNativeBridge.instance
        .applicationSupportDirectory();
    final directory = Directory(p.join(supportPath, 'recording_audio', 'live'));
    await directory.create(recursive: true);
    return p.join(
      directory.path,
      'sherpa_live_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
  }

  CapturedRecordingAudio? _capturedAudioFromFile(Pcm16AudioFile? file) {
    if (file == null) {
      return null;
    }
    return CapturedRecordingAudio(
      path: file.path,
      sampleRate: file.sampleRate,
      durationMs: file.durationMs,
      byteLength: file.byteLength,
    );
  }

  void _resetPartialPreview() {
    _partialSamples.clear();
    _lastPartialText = '';
    _lastPartialDecodedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

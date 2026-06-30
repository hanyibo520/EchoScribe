import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../audio/pcm16_wav_io.dart';

class VoiceProfileSampleRecorder {
  VoiceProfileSampleRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const int sampleRate = 16000;

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  Pcm16WavFileWriter? _writer;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<void> start({required String path}) async {
    if (_isRecording) {
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission denied');
    }

    const encoder = AudioEncoder.pcm16bits;
    if (!await _recorder.isEncoderSupported(encoder)) {
      throw StateError('PCM16 audio stream is not supported on this device');
    }

    final writer = await Pcm16WavFileWriter.create(
      path: path,
      sampleRate: sampleRate,
    );
    const config = RecordConfig(
      encoder: encoder,
      sampleRate: sampleRate,
      numChannels: 1,
      streamBufferSize: 4096,
    );

    late final Stream<Uint8List> audioStream;
    try {
      audioStream = await _recorder.startStream(config);
    } catch (_) {
      await writer.close();
      rethrow;
    }

    _writer = writer;
    _audioSubscription = audioStream.listen((data) {
      _writer?.append(data);
    });
    _isRecording = true;
  }

  Future<Pcm16AudioFile?> stop() async {
    if (!_isRecording) {
      return null;
    }
    _isRecording = false;
    await _recorder.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    final audioFile = await _writer?.close();
    _writer = null;
    return audioFile;
  }

  Future<void> dispose() async {
    if (_isRecording) {
      await stop();
    }
    await _audioSubscription?.cancel();
    await _writer?.close();
    _writer = null;
    await _recorder.dispose();
  }
}

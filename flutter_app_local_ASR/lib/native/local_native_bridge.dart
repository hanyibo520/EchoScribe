import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class LocalNativeBridge {
  LocalNativeBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final LocalNativeBridge instance = LocalNativeBridge._();

  static const MethodChannel _channel = MethodChannel(
    'local_meeting_asr/native_bridge',
  );

  final StreamController<MoonshineAsrNativeEvent> _moonshineEvents =
      StreamController<MoonshineAsrNativeEvent>.broadcast();

  Stream<MoonshineAsrNativeEvent> get moonshineEvents =>
      _moonshineEvents.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'moonshineStatus':
        _moonshineEvents.add(
          MoonshineAsrNativeEvent.status(_stringArgument(call.arguments)),
        );
        return null;
      case 'moonshinePartial':
        _moonshineEvents.add(
          MoonshineAsrNativeEvent.partial(_stringArgument(call.arguments)),
        );
        return null;
      case 'moonshineSegment':
        _moonshineEvents.add(
          MoonshineAsrNativeEvent.segment(_stringArgument(call.arguments)),
        );
        return null;
      case 'moonshineError':
        _moonshineEvents.add(
          MoonshineAsrNativeEvent.error(_stringArgument(call.arguments)),
        );
        return null;
      default:
        throw MissingPluginException('Unknown native callback ${call.method}');
    }
  }

  String _stringArgument(Object? value) {
    if (value is Map) {
      return value['text']?.toString() ??
          value['message']?.toString() ??
          value['reason']?.toString() ??
          '';
    }
    return value?.toString() ?? '';
  }

  Future<String> applicationSupportDirectory() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'applicationSupportDirectory',
      );
      final path = response?['path']?.toString() ?? '';
      if (path.isNotEmpty) {
        return path;
      }
    } on MissingPluginException {
      // Unit tests and unsupported platforms can still use a temporary store.
    } on PlatformException {
      // Fall through to a temporary store so model checks remain non-fatal.
    }

    return '${Directory.systemTemp.path}/local_meeting_asr_support';
  }

  Future<String?> bundledAssetFilePath({
    required String assetDirectory,
    required String fileName,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'resolveBundledAssetPath',
        <String, Object?>{
          'assetDirectory': assetDirectory,
          'fileName': fileName,
        },
      );
      final path = response?['path']?.toString() ?? '';
      return path.isEmpty ? null : path;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<NativeBridgeReport> inspectBridges({
    required String whisperModelPath,
    required String llamaModelPath,
    String moonshineModelPath = '',
  }) async {
    try {
      final response = await _channel
          .invokeMapMethod<String, Object?>('inspectBridges', <String, Object?>{
            'whisperModelPath': whisperModelPath,
            'llamaModelPath': llamaModelPath,
            'moonshineModelPath': moonshineModelPath,
          });
      return NativeBridgeReport.fromMap(response);
    } on MissingPluginException {
      return NativeBridgeReport.unavailable(
        'Native bridge channel is not registered on this platform',
      );
    } on PlatformException catch (error) {
      return NativeBridgeReport.unavailable(error.message ?? error.code);
    }
  }

  Future<NativeBridgeStatus> checkWhisperCpp({
    required String modelPath,
  }) async {
    final report = await inspectBridges(
      whisperModelPath: modelPath,
      llamaModelPath: '',
    );
    return report.whisperCpp;
  }

  Future<NativeBridgeStatus> checkMoonshine({required String modelPath}) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'checkMoonshine',
        <String, Object?>{'modelPath': modelPath},
      );
      return NativeBridgeStatus.fromMap(response);
    } on MissingPluginException {
      return NativeBridgeStatus.unavailable(
        'Moonshine native bridge is not registered on this platform',
      );
    } on PlatformException catch (error) {
      return NativeBridgeStatus.unavailable(error.message ?? error.code);
    }
  }

  Future<void> startMoonshine({required String modelPath}) async {
    await _channel.invokeMethod<void>('startMoonshine', <String, Object?>{
      'modelPath': modelPath,
    });
  }

  Future<void> stopMoonshine() async {
    try {
      await _channel.invokeMethod<void>('stopMoonshine');
    } on MissingPluginException {
      // Unsupported platforms can fall back to the next ASR engine.
    }
  }

  Future<void> disposeMoonshine() async {
    try {
      await _channel.invokeMethod<void>('disposeMoonshine');
    } on MissingPluginException {
      // Unsupported platforms can fall back to the next ASR engine.
    }
  }

  Future<String> transcribeWithWhisperCpp({
    required String modelPath,
    required Uint8List pcm16Audio,
    required int sampleRate,
    required String languageCode,
  }) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'transcribeWithWhisperCpp',
      <String, Object?>{
        'modelPath': modelPath,
        'pcm16Audio': pcm16Audio,
        'sampleRate': sampleRate,
        'languageCode': languageCode,
      },
    );
    return response?['text']?.toString() ?? '';
  }

  Future<PickedAudioFile?> pickAudioFile() async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'pickAudioFile',
    );
    if (response == null) {
      return null;
    }

    final path = response['path']?.toString() ?? '';
    if (path.isEmpty) {
      return null;
    }

    return PickedAudioFile(
      path: path,
      name: response['name']?.toString() ?? 'audio',
    );
  }

  Future<String> transcribeAudioFileWithWhisperCpp({
    required String modelPath,
    required String audioFilePath,
    required String languageCode,
  }) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'transcribeAudioFileWithWhisperCpp',
      <String, Object?>{
        'modelPath': modelPath,
        'audioFilePath': audioFilePath,
        'languageCode': languageCode,
      },
    );
    return response?['text']?.toString() ?? '';
  }

  Future<List<MoonshineFileSegment>> transcribeAudioFileWithMoonshine({
    required String modelPath,
    required String audioFilePath,
    double speedFactor = 1.0,
  }) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'transcribeAudioFileWithMoonshine',
      <String, Object?>{
        'modelPath': modelPath,
        'audioFilePath': audioFilePath,
        'speedFactor': speedFactor,
      },
    );
    final values = response?['segments'];
    if (values is! List) {
      return const <MoonshineFileSegment>[];
    }
    return values
        .whereType<Map<Object?, Object?>>()
        .map(MoonshineFileSegment.fromMap)
        .where((segment) => segment.text.isNotEmpty)
        .toList(growable: false);
  }

  Future<DecodedPcmAudio> decodeAudioFileToPcm16({
    required String audioFilePath,
  }) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'decodeAudioFileToPcm16',
      <String, Object?>{'audioFilePath': audioFilePath},
    );
    final audio = response?['pcm16Audio'];
    return DecodedPcmAudio(
      pcm16Audio: audio is Uint8List ? audio : Uint8List(0),
      sampleRate: response?['sampleRate'] as int? ?? 16000,
    );
  }

  Future<void> deleteImportedAudioIfNeeded(String audioFilePath) async {
    try {
      await _channel.invokeMethod<void>(
        'deleteImportedAudioIfNeeded',
        <String, Object?>{'audioFilePath': audioFilePath},
      );
    } on MissingPluginException {
      await _deleteImportedAudioFallback(audioFilePath);
    } on PlatformException {
      await _deleteImportedAudioFallback(audioFilePath);
    }
  }

  Future<NativeBridgeStatus> checkLlamaCpp({required String modelPath}) async {
    final report = await inspectBridges(
      whisperModelPath: '',
      llamaModelPath: modelPath,
    );
    return report.llamaCpp;
  }

  Future<bool> installBundledDirectory({
    required String assetDirectory,
    required String destinationDirectory,
    required List<String> fileNames,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'installBundledDirectory',
        <String, Object?>{
          'assetDirectory': assetDirectory,
          'destinationDirectory': destinationDirectory,
          'fileNames': fileNames,
        },
      );
      return response?['installed'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, Object?>> summarizeWithLlamaCpp({
    required String modelPath,
    required String transcript,
    required String languageCode,
  }) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'summarizeWithLlamaCpp',
      <String, Object?>{
        'modelPath': modelPath,
        'transcript': transcript,
        'languageCode': languageCode,
      },
    );
    return response ?? const <String, Object?>{};
  }

  Future<void> _deleteImportedAudioFallback(String audioFilePath) async {
    final file = File(audioFilePath);
    if (file.parent.path.split(Platform.pathSeparator).last !=
        'ImportedAudio') {
      return;
    }
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class PickedAudioFile {
  const PickedAudioFile({required this.path, required this.name});

  final String path;
  final String name;
}

class DecodedPcmAudio {
  const DecodedPcmAudio({required this.pcm16Audio, required this.sampleRate});

  final Uint8List pcm16Audio;
  final int sampleRate;
}

class MoonshineFileSegment {
  const MoonshineFileSegment({
    required this.text,
    required this.startTimeSeconds,
    required this.durationSeconds,
  });

  factory MoonshineFileSegment.fromMap(Map<Object?, Object?> value) {
    return MoonshineFileSegment(
      text: value['text']?.toString().trim() ?? '',
      startTimeSeconds: _doubleValue(value['startTimeSeconds']),
      durationSeconds: _doubleValue(value['durationSeconds']),
    );
  }

  static double _doubleValue(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  final String text;
  final double startTimeSeconds;
  final double durationSeconds;
}

enum MoonshineAsrNativeEventType { status, partial, segment, error }

class MoonshineAsrNativeEvent {
  const MoonshineAsrNativeEvent._({required this.type, required this.text});

  const MoonshineAsrNativeEvent.status(String text)
    : this._(type: MoonshineAsrNativeEventType.status, text: text);

  const MoonshineAsrNativeEvent.partial(String text)
    : this._(type: MoonshineAsrNativeEventType.partial, text: text);

  const MoonshineAsrNativeEvent.segment(String text)
    : this._(type: MoonshineAsrNativeEventType.segment, text: text);

  const MoonshineAsrNativeEvent.error(String text)
    : this._(type: MoonshineAsrNativeEventType.error, text: text);

  final MoonshineAsrNativeEventType type;
  final String text;
}

class NativeBridgeReport {
  const NativeBridgeReport({
    required this.whisperCpp,
    required this.llamaCpp,
    required this.moonshine,
  });

  factory NativeBridgeReport.fromMap(Map<String, Object?>? value) {
    return NativeBridgeReport(
      whisperCpp: NativeBridgeStatus.fromMap(value?['whisperCpp']),
      llamaCpp: NativeBridgeStatus.fromMap(value?['llamaCpp']),
      moonshine: NativeBridgeStatus.fromMap(value?['moonshine']),
    );
  }

  factory NativeBridgeReport.unavailable(String reason) {
    final status = NativeBridgeStatus.unavailable(reason);
    return NativeBridgeReport(
      whisperCpp: status,
      llamaCpp: status,
      moonshine: status,
    );
  }

  final NativeBridgeStatus whisperCpp;
  final NativeBridgeStatus llamaCpp;
  final NativeBridgeStatus moonshine;
}

class NativeBridgeStatus {
  const NativeBridgeStatus.available({this.detail})
    : isAvailable = true,
      reason = null;

  const NativeBridgeStatus.unavailable(this.reason)
    : isAvailable = false,
      detail = null;

  factory NativeBridgeStatus.fromMap(Object? value) {
    if (value is! Map) {
      return const NativeBridgeStatus.unavailable(
        'Native bridge did not return a status',
      );
    }

    final available = value['available'] == true;
    if (available) {
      return NativeBridgeStatus.available(detail: value['detail']?.toString());
    }

    return NativeBridgeStatus.unavailable(
      value['reason']?.toString() ?? 'Native runtime is not available',
    );
  }

  final bool isAvailable;
  final String? reason;
  final String? detail;
}

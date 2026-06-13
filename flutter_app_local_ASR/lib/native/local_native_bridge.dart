import 'dart:io';

import 'package:flutter/services.dart';

class LocalNativeBridge {
  LocalNativeBridge._();

  static final LocalNativeBridge instance = LocalNativeBridge._();

  static const MethodChannel _channel = MethodChannel(
    'local_meeting_asr/native_bridge',
  );

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
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'inspectBridges',
        <String, Object?>{
          'whisperModelPath': whisperModelPath,
          'llamaModelPath': llamaModelPath,
        },
      );
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
}

class PickedAudioFile {
  const PickedAudioFile({required this.path, required this.name});

  final String path;
  final String name;
}

class NativeBridgeReport {
  const NativeBridgeReport({required this.whisperCpp, required this.llamaCpp});

  factory NativeBridgeReport.fromMap(Map<String, Object?>? value) {
    return NativeBridgeReport(
      whisperCpp: NativeBridgeStatus.fromMap(value?['whisperCpp']),
      llamaCpp: NativeBridgeStatus.fromMap(value?['llamaCpp']),
    );
  }

  factory NativeBridgeReport.unavailable(String reason) {
    final status = NativeBridgeStatus.unavailable(reason);
    return NativeBridgeReport(whisperCpp: status, llamaCpp: status);
  }

  final NativeBridgeStatus whisperCpp;
  final NativeBridgeStatus llamaCpp;
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

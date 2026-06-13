import 'dart:io';

import 'package:path/path.dart' as p;

import '../native/local_native_bridge.dart';

enum ModelInstallScope {
  primaryAsr,
  detailedSummary,
  offlineTranscription,
  all,
}

class ModelStore {
  ModelStore({LocalNativeBridge? nativeBridge})
    : _nativeBridge = nativeBridge ?? LocalNativeBridge.instance;

  final LocalNativeBridge _nativeBridge;

  static const String senseVoiceModelFile = 'model.int8.onnx';
  static const String senseVoiceTokensFile = 'tokens.txt';
  static const String sileroVadFile = 'silero_vad.onnx';
  static const String whisperModelFile = 'ggml-base.bin';
  static const String qwenGgufModelFile = 'qwen3-0.6b-q4.gguf';
  static const String bundledModelAssetRoot = 'assets/models';
  static const int _senseVoiceModelMinBytes = 200 * 1024 * 1024;
  static const int _senseVoiceTokensMinBytes = 1024;
  static const int _sileroVadMinBytes = 512 * 1024;
  static const int _whisperModelMinBytes = 120 * 1024 * 1024;
  static const int _qwenGgufModelMinBytes = 350 * 1024 * 1024;

  Future<ModelCheckResult> inspect() async {
    final paths = await _paths();
    await paths.createDirectories();

    final senseVoiceFiles = SenseVoiceModelFiles(
      model: await _runtimeModelPath(
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice',
        fileName: senseVoiceModelFile,
        installedPath: p.join(paths.senseVoiceRoot, senseVoiceModelFile),
      ),
      tokens: await _runtimeModelPath(
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice',
        fileName: senseVoiceTokensFile,
        installedPath: p.join(paths.senseVoiceRoot, senseVoiceTokensFile),
      ),
      vad: await _runtimeModelPath(
        assetDirectory: '$bundledModelAssetRoot/asr',
        fileName: sileroVadFile,
        installedPath: p.join(paths.asrRoot, sileroVadFile),
      ),
    );
    final requiredAsrFiles = <_RequiredRuntimeModel>[
      _RequiredRuntimeModel(
        path: senseVoiceFiles.model,
        minBytes: _senseVoiceModelMinBytes,
      ),
      _RequiredRuntimeModel(
        path: senseVoiceFiles.tokens,
        minBytes: _senseVoiceTokensMinBytes,
      ),
      _RequiredRuntimeModel(
        path: senseVoiceFiles.vad,
        minBytes: _sileroVadMinBytes,
      ),
    ];
    final missingSenseVoiceFiles = <String>[];
    for (final file in requiredAsrFiles) {
      if (!_isUsableFile(file.path, minBytes: file.minBytes)) {
        missingSenseVoiceFiles.add(file.path);
      }
    }

    final whisperModel = await _runtimeModelPath(
      assetDirectory: '$bundledModelAssetRoot/asr/whisper',
      fileName: whisperModelFile,
      installedPath: p.join(paths.whisperRoot, whisperModelFile),
    );
    final llamaModel = await _runtimeModelPath(
      assetDirectory: '$bundledModelAssetRoot/llm',
      fileName: qwenGgufModelFile,
      installedPath: p.join(paths.llmRoot, qwenGgufModelFile),
    );
    return ModelCheckResult(
      asrRootPath: paths.asrRoot,
      senseVoiceFiles: senseVoiceFiles,
      missingSenseVoiceFiles: missingSenseVoiceFiles,
      whisperModelPath: whisperModel,
      isWhisperModelReady: _isUsableFile(
        whisperModel,
        minBytes: _whisperModelMinBytes,
      ),
      llamaModelPath: llamaModel,
      isLlamaModelReady: _isUsableFile(
        llamaModel,
        minBytes: _qwenGgufModelMinBytes,
      ),
    );
  }

  Future<void> installBundledModels({
    required void Function(ModelInstallProgress progress) onProgress,
    ModelInstallScope scope = ModelInstallScope.primaryAsr,
  }) async {
    final check = await inspect();
    final paths = await _paths();
    final groups = _bundledGroups(
      check,
      paths: paths,
      scope: scope,
    ).where(_needsDirectoryInstall).toList(growable: false);

    if (groups.isEmpty) {
      return;
    }

    final missingAssets = <String>[];
    for (var i = 0; i < groups.length; i += 1) {
      final group = groups[i];
      onProgress(
        ModelInstallProgress(
          label: group.label,
          itemIndex: i + 1,
          itemCount: groups.length,
        ),
      );

      final installed = await _copyBundledDirectory(
        assetDirectory: group.assetDirectory,
        destinationDirectory: group.destinationDirectory,
        fileNames: group.fileNames,
      );
      if (!installed) {
        missingAssets.add(group.assetDirectory);
      }
    }

    if (missingAssets.isNotEmpty) {
      throw MissingBundledModelsException(missingAssets);
    }
  }

  Future<bool> _copyBundledDirectory({
    required String assetDirectory,
    required String destinationDirectory,
    required List<String> fileNames,
  }) async {
    return _nativeBridge.installBundledDirectory(
      assetDirectory: assetDirectory,
      destinationDirectory: destinationDirectory,
      fileNames: fileNames,
    );
  }

  List<ModelInstallGroup> _bundledGroups(
    ModelCheckResult check, {
    required _ModelPaths paths,
    required ModelInstallScope scope,
  }) {
    final primaryAsrGroups = <ModelInstallGroup>[
      ModelInstallGroup(
        label: 'SenseVoice',
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice',
        destinationDirectory: paths.senseVoiceRoot,
        fileNames: const <String>[senseVoiceModelFile, senseVoiceTokensFile],
        runtimeFilePaths: <String>[
          check.senseVoiceFiles.model,
          check.senseVoiceFiles.tokens,
        ],
      ),
      ModelInstallGroup(
        label: 'Silero VAD',
        assetDirectory: '$bundledModelAssetRoot/asr',
        destinationDirectory: paths.asrRoot,
        fileNames: const <String>[sileroVadFile],
        runtimeFilePaths: <String>[check.senseVoiceFiles.vad],
      ),
    ];
    final detailedSummaryGroups = <ModelInstallGroup>[
      ModelInstallGroup(
        label: 'Qwen3 0.6B GGUF',
        assetDirectory: '$bundledModelAssetRoot/llm',
        destinationDirectory: paths.llmRoot,
        fileNames: const <String>[qwenGgufModelFile],
        runtimeFilePaths: <String>[check.llamaModelPath],
      ),
    ];
    final offlineTranscriptionGroups = <ModelInstallGroup>[
      ModelInstallGroup(
        label: 'Whisper base',
        assetDirectory: '$bundledModelAssetRoot/asr/whisper',
        destinationDirectory: paths.whisperRoot,
        fileNames: const <String>[whisperModelFile],
        runtimeFilePaths: <String>[check.whisperModelPath],
      ),
    ];
    return switch (scope) {
      ModelInstallScope.primaryAsr => primaryAsrGroups,
      ModelInstallScope.detailedSummary => detailedSummaryGroups,
      ModelInstallScope.offlineTranscription => offlineTranscriptionGroups,
      ModelInstallScope.all => [
        ...primaryAsrGroups,
        ...detailedSummaryGroups,
        ...offlineTranscriptionGroups,
      ],
    };
  }

  bool _needsDirectoryInstall(ModelInstallGroup group) {
    return group.runtimeFilePaths.any(
      (filePath) => !_isUsableRuntimeFile(filePath),
    );
  }

  bool _isUsableRuntimeFile(String filePath) {
    final minBytes = switch (p.basename(filePath)) {
      senseVoiceModelFile => _senseVoiceModelMinBytes,
      senseVoiceTokensFile => _senseVoiceTokensMinBytes,
      sileroVadFile => _sileroVadMinBytes,
      whisperModelFile => _whisperModelMinBytes,
      qwenGgufModelFile => _qwenGgufModelMinBytes,
      _ => 1,
    };
    return _isUsableFile(filePath, minBytes: minBytes);
  }

  bool _isUsableFile(String filePath, {required int minBytes}) {
    final file = File(filePath);
    if (!file.existsSync()) {
      return false;
    }
    try {
      return file.lengthSync() >= minBytes;
    } on FileSystemException {
      return false;
    }
  }

  Future<int> purgeBundledModelCopies() async {
    final paths = await _paths();
    final entries = <_BundledModelCopy>[
      _BundledModelCopy(
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice',
        fileName: senseVoiceModelFile,
        installedPath: p.join(paths.senseVoiceRoot, senseVoiceModelFile),
      ),
      _BundledModelCopy(
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice',
        fileName: senseVoiceTokensFile,
        installedPath: p.join(paths.senseVoiceRoot, senseVoiceTokensFile),
      ),
      _BundledModelCopy(
        assetDirectory: '$bundledModelAssetRoot/asr',
        fileName: sileroVadFile,
        installedPath: p.join(paths.asrRoot, sileroVadFile),
      ),
      _BundledModelCopy(
        assetDirectory: '$bundledModelAssetRoot/asr/whisper',
        fileName: whisperModelFile,
        installedPath: p.join(paths.whisperRoot, whisperModelFile),
      ),
      _BundledModelCopy(
        assetDirectory: '$bundledModelAssetRoot/llm',
        fileName: qwenGgufModelFile,
        installedPath: p.join(paths.llmRoot, qwenGgufModelFile),
      ),
    ];

    var removedBytes = 0;
    for (final entry in entries) {
      final bundledPath = await _nativeBridge.bundledAssetFilePath(
        assetDirectory: entry.assetDirectory,
        fileName: entry.fileName,
      );
      if (bundledPath == null || !File(bundledPath).existsSync()) {
        continue;
      }

      final installedFile = File(entry.installedPath);
      if (!installedFile.existsSync()) {
        continue;
      }

      try {
        removedBytes += installedFile.lengthSync();
        await installedFile.delete();
      } on FileSystemException {
        // Best-effort cleanup; stale copies should not block ASR startup.
      }
    }

    await _deleteEmptyDirectory(paths.senseVoiceRoot);
    await _deleteEmptyDirectory(paths.whisperRoot);
    removedBytes += await _deleteDirectoryIfExists(
      p.join(paths.llmRoot, 'qwen3-0.6b-mlx'),
    );
    await _deleteEmptyDirectory(paths.asrRoot);
    await _deleteEmptyDirectory(paths.llmRoot);
    return removedBytes;
  }

  Future<String> _runtimeModelPath({
    required String assetDirectory,
    required String fileName,
    required String installedPath,
  }) async {
    final bundledPath = await _nativeBridge.bundledAssetFilePath(
      assetDirectory: assetDirectory,
      fileName: fileName,
    );
    if (bundledPath != null && File(bundledPath).existsSync()) {
      return bundledPath;
    }
    return installedPath;
  }

  Future<void> _deleteEmptyDirectory(String path) async {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return;
    }
    try {
      if (directory.listSync().isEmpty) {
        await directory.delete();
      }
    } on FileSystemException {
      // Leaving an empty directory is harmless.
    }
  }

  Future<int> _deleteDirectoryIfExists(String path) async {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return 0;
    }

    final bytes = _directorySize(directory);
    try {
      await directory.delete(recursive: true);
      return bytes;
    } on FileSystemException {
      return 0;
    }
  }

  int _directorySize(Directory directory) {
    var bytes = 0;
    try {
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is File) {
          bytes += entity.lengthSync();
        }
      }
    } on FileSystemException {
      return 0;
    }
    return bytes;
  }

  Future<_ModelPaths> _paths() async {
    final supportPath = await _nativeBridge.applicationSupportDirectory();
    final asrRoot = p.join(supportPath, 'asr_models');
    final senseVoiceRoot = p.join(asrRoot, 'sensevoice');
    final whisperRoot = p.join(asrRoot, 'whisper');
    final llmRoot = p.join(supportPath, 'llm_models');
    return _ModelPaths(
      asrRoot: asrRoot,
      senseVoiceRoot: senseVoiceRoot,
      whisperRoot: whisperRoot,
      llmRoot: llmRoot,
    );
  }
}

class _ModelPaths {
  const _ModelPaths({
    required this.asrRoot,
    required this.senseVoiceRoot,
    required this.whisperRoot,
    required this.llmRoot,
  });

  final String asrRoot;
  final String senseVoiceRoot;
  final String whisperRoot;
  final String llmRoot;

  Future<void> createDirectories() async {
    await Directory(senseVoiceRoot).create(recursive: true);
    await Directory(whisperRoot).create(recursive: true);
    await Directory(llmRoot).create(recursive: true);
  }
}

class ModelInstallGroup {
  const ModelInstallGroup({
    required this.label,
    required this.assetDirectory,
    required this.destinationDirectory,
    required this.fileNames,
    required this.runtimeFilePaths,
  });

  final String label;
  final String assetDirectory;
  final String destinationDirectory;
  final List<String> fileNames;
  final List<String> runtimeFilePaths;
}

class _RequiredRuntimeModel {
  const _RequiredRuntimeModel({required this.path, required this.minBytes});

  final String path;
  final int minBytes;
}

class _BundledModelCopy {
  const _BundledModelCopy({
    required this.assetDirectory,
    required this.fileName,
    required this.installedPath,
  });

  final String assetDirectory;
  final String fileName;
  final String installedPath;
}

class ModelInstallProgress {
  const ModelInstallProgress({
    required this.label,
    required this.itemIndex,
    required this.itemCount,
  });

  final String label;
  final int itemIndex;
  final int itemCount;
}

class MissingBundledModelsException implements Exception {
  const MissingBundledModelsException(this.missingAssets);

  final List<String> missingAssets;

  @override
  String toString() =>
      'Missing bundled model assets: ${missingAssets.join(', ')}';
}

class SenseVoiceModelFiles {
  const SenseVoiceModelFiles({
    required this.model,
    required this.tokens,
    required this.vad,
  });

  final String model;
  final String tokens;
  final String vad;
}

class ModelCheckResult {
  const ModelCheckResult({
    required this.asrRootPath,
    required this.senseVoiceFiles,
    required this.missingSenseVoiceFiles,
    required this.whisperModelPath,
    required this.isWhisperModelReady,
    required this.llamaModelPath,
    required this.isLlamaModelReady,
  });

  final String asrRootPath;
  final SenseVoiceModelFiles senseVoiceFiles;
  final List<String> missingSenseVoiceFiles;
  final String whisperModelPath;
  final bool isWhisperModelReady;
  final String llamaModelPath;
  final bool isLlamaModelReady;

  bool get isSenseVoiceReady => missingSenseVoiceFiles.isEmpty;
  bool get hasInstallableMissingModels =>
      !isSenseVoiceReady || !isWhisperModelReady || !isLlamaModelReady;
}

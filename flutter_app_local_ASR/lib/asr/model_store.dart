import 'dart:io';

import 'package:path/path.dart' as p;

import '../native/local_native_bridge.dart';

enum ModelInstallScope {
  primaryAsr,
  moonshineAsr,
  fastAsr,
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
  static const List<String> moonshineTinyStreamingFiles = <String>[
    'adapter.ort',
    'cross_kv.ort',
    'decoder_kv.ort',
    'decoder_kv_with_attention.ort',
    'encoder.ort',
    'frontend.ort',
    'streaming_config.json',
    'tokenizer.bin',
  ];
  static const String whisperModelFile = 'ggml-base.bin';
  static const String qwenGgufModelFile = 'qwen3-0.6b-q4.gguf';
  static const String bundledModelAssetRoot = 'assets/models';
  static const int _senseVoiceModelMinBytes = 200 * 1024 * 1024;
  static const int _fastSenseVoiceModelMinBytes = 1024 * 1024;
  static const int _senseVoiceTokensMinBytes = 1024;
  static const int _sileroVadMinBytes = 512 * 1024;
  static const int _moonshineModelMinBytes = 1024;
  static const int _moonshineTokenizerMinBytes = 1024;
  static const int _moonshineConfigMinBytes = 64;
  static const int _whisperModelMinBytes = 120 * 1024 * 1024;
  static const int _qwenGgufModelMinBytes = 350 * 1024 * 1024;

  Future<ModelCheckResult> inspect() async {
    final paths = await _paths();
    await paths.createDirectories();

    final senseVoiceVad = await _runtimeModelPath(
      assetDirectory: '$bundledModelAssetRoot/asr',
      fileName: sileroVadFile,
      installedPath: p.join(paths.asrRoot, sileroVadFile),
    );
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
      vad: senseVoiceVad,
    );
    final fastSenseVoiceFiles = SenseVoiceModelFiles(
      model: await _runtimeModelPath(
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice_fast',
        fileName: senseVoiceModelFile,
        installedPath: p.join(paths.fastSenseVoiceRoot, senseVoiceModelFile),
      ),
      tokens: await _runtimeModelPath(
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice_fast',
        fileName: senseVoiceTokensFile,
        installedPath: p.join(paths.fastSenseVoiceRoot, senseVoiceTokensFile),
      ),
      vad: senseVoiceVad,
    );
    final moonshineFilePaths = <String, String>{
      for (final fileName in moonshineTinyStreamingFiles)
        fileName: await _runtimeModelPath(
          assetDirectory:
              '$bundledModelAssetRoot/asr/moonshine_tiny_streaming_en',
          fileName: fileName,
          installedPath: p.join(paths.moonshineTinyStreamingRoot, fileName),
        ),
    };
    final moonshineFiles = MoonshineModelFiles(
      directory: _sharedModelDirectory(
        moonshineFilePaths.values,
        fallback: paths.moonshineTinyStreamingRoot,
      ),
      files: moonshineFilePaths,
    );
    final missingMoonshineTinyStreamingFiles = <String>[];
    for (final fileName in moonshineTinyStreamingFiles) {
      final path = moonshineFiles.files[fileName]!;
      if (!_isUsableFile(path, minBytes: _moonshineMinBytesFor(fileName))) {
        missingMoonshineTinyStreamingFiles.add(path);
      }
    }
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
    final requiredFastAsrFiles = <_RequiredRuntimeModel>[
      _RequiredRuntimeModel(
        path: fastSenseVoiceFiles.model,
        minBytes: _fastSenseVoiceModelMinBytes,
      ),
      _RequiredRuntimeModel(
        path: fastSenseVoiceFiles.tokens,
        minBytes: _senseVoiceTokensMinBytes,
      ),
      _RequiredRuntimeModel(
        path: fastSenseVoiceFiles.vad,
        minBytes: _sileroVadMinBytes,
      ),
    ];
    final missingFastSenseVoiceFiles = <String>[];
    for (final file in requiredFastAsrFiles) {
      if (!_isUsableFile(file.path, minBytes: file.minBytes)) {
        missingFastSenseVoiceFiles.add(file.path);
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
      fastSenseVoiceFiles: fastSenseVoiceFiles,
      missingFastSenseVoiceFiles: missingFastSenseVoiceFiles,
      moonshineTinyStreamingFiles: moonshineFiles,
      missingMoonshineTinyStreamingFiles: missingMoonshineTinyStreamingFiles,
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
      if (!installed && group.isRequired) {
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

  List<_ModelInstallGroup> _bundledGroups(
    ModelCheckResult check, {
    required _ModelPaths paths,
    required ModelInstallScope scope,
  }) {
    final primaryAsrGroups = <_ModelInstallGroup>[
      _ModelInstallGroup(
        label: 'Moonshine Tiny Streaming EN',
        assetDirectory:
            '$bundledModelAssetRoot/asr/moonshine_tiny_streaming_en',
        destinationDirectory: paths.moonshineTinyStreamingRoot,
        fileNames: moonshineTinyStreamingFiles,
        runtimeModels: <_RequiredRuntimeModel>[
          for (final fileName in moonshineTinyStreamingFiles)
            _RequiredRuntimeModel(
              path: check.moonshineTinyStreamingFiles.files[fileName]!,
              minBytes: _moonshineMinBytesFor(fileName),
            ),
        ],
        isRequired: false,
      ),
      _ModelInstallGroup(
        label: 'SenseVoice',
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice',
        destinationDirectory: paths.senseVoiceRoot,
        fileNames: const <String>[senseVoiceModelFile, senseVoiceTokensFile],
        runtimeModels: <_RequiredRuntimeModel>[
          _RequiredRuntimeModel(
            path: check.senseVoiceFiles.model,
            minBytes: _senseVoiceModelMinBytes,
          ),
          _RequiredRuntimeModel(
            path: check.senseVoiceFiles.tokens,
            minBytes: _senseVoiceTokensMinBytes,
          ),
        ],
      ),
      _ModelInstallGroup(
        label: 'Silero VAD',
        assetDirectory: '$bundledModelAssetRoot/asr',
        destinationDirectory: paths.asrRoot,
        fileNames: const <String>[sileroVadFile],
        runtimeModels: <_RequiredRuntimeModel>[
          _RequiredRuntimeModel(
            path: check.senseVoiceFiles.vad,
            minBytes: _sileroVadMinBytes,
          ),
        ],
      ),
    ];
    final fastAsrGroups = <_ModelInstallGroup>[
      _ModelInstallGroup(
        label: 'SenseVoice fast',
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice_fast',
        destinationDirectory: paths.fastSenseVoiceRoot,
        fileNames: const <String>[senseVoiceModelFile, senseVoiceTokensFile],
        runtimeModels: <_RequiredRuntimeModel>[
          _RequiredRuntimeModel(
            path: check.fastSenseVoiceFiles.model,
            minBytes: _fastSenseVoiceModelMinBytes,
          ),
          _RequiredRuntimeModel(
            path: check.fastSenseVoiceFiles.tokens,
            minBytes: _senseVoiceTokensMinBytes,
          ),
        ],
        isRequired: false,
      ),
    ];
    final detailedSummaryGroups = <_ModelInstallGroup>[
      _ModelInstallGroup(
        label: 'Qwen3 0.6B GGUF',
        assetDirectory: '$bundledModelAssetRoot/llm',
        destinationDirectory: paths.llmRoot,
        fileNames: const <String>[qwenGgufModelFile],
        runtimeModels: <_RequiredRuntimeModel>[
          _RequiredRuntimeModel(
            path: check.llamaModelPath,
            minBytes: _qwenGgufModelMinBytes,
          ),
        ],
      ),
    ];
    final offlineTranscriptionGroups = <_ModelInstallGroup>[
      _ModelInstallGroup(
        label: 'Whisper base',
        assetDirectory: '$bundledModelAssetRoot/asr/whisper',
        destinationDirectory: paths.whisperRoot,
        fileNames: const <String>[whisperModelFile],
        runtimeModels: <_RequiredRuntimeModel>[
          _RequiredRuntimeModel(
            path: check.whisperModelPath,
            minBytes: _whisperModelMinBytes,
          ),
        ],
      ),
    ];
    return switch (scope) {
      ModelInstallScope.primaryAsr => primaryAsrGroups,
      ModelInstallScope.moonshineAsr =>
        primaryAsrGroups
            .where((group) => group.label == 'Moonshine Tiny Streaming EN')
            .toList(growable: false),
      ModelInstallScope.fastAsr => fastAsrGroups,
      ModelInstallScope.detailedSummary => detailedSummaryGroups,
      ModelInstallScope.offlineTranscription => offlineTranscriptionGroups,
      ModelInstallScope.all => [
        ...primaryAsrGroups,
        ...fastAsrGroups,
        ...detailedSummaryGroups,
        ...offlineTranscriptionGroups,
      ],
    };
  }

  bool _needsDirectoryInstall(_ModelInstallGroup group) {
    return group.runtimeModels.any(
      (file) => !_isUsableFile(file.path, minBytes: file.minBytes),
    );
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

  int _moonshineMinBytesFor(String fileName) {
    if (fileName == 'streaming_config.json') {
      return _moonshineConfigMinBytes;
    }
    if (fileName == 'tokenizer.bin') {
      return _moonshineTokenizerMinBytes;
    }
    return _moonshineModelMinBytes;
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
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice_fast',
        fileName: senseVoiceModelFile,
        installedPath: p.join(paths.fastSenseVoiceRoot, senseVoiceModelFile),
      ),
      _BundledModelCopy(
        assetDirectory: '$bundledModelAssetRoot/asr/sensevoice_fast',
        fileName: senseVoiceTokensFile,
        installedPath: p.join(paths.fastSenseVoiceRoot, senseVoiceTokensFile),
      ),
      for (final fileName in moonshineTinyStreamingFiles)
        _BundledModelCopy(
          assetDirectory:
              '$bundledModelAssetRoot/asr/moonshine_tiny_streaming_en',
          fileName: fileName,
          installedPath: p.join(paths.moonshineTinyStreamingRoot, fileName),
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
    await _deleteEmptyDirectory(paths.fastSenseVoiceRoot);
    await _deleteEmptyDirectory(paths.moonshineTinyStreamingRoot);
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

  String _sharedModelDirectory(
    Iterable<String> filePaths, {
    required String fallback,
  }) {
    final directories = <String>{};
    for (final filePath in filePaths) {
      if (filePath.isEmpty) {
        return fallback;
      }
      directories.add(p.dirname(filePath));
    }
    return directories.length == 1 ? directories.single : fallback;
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
    final fastSenseVoiceRoot = p.join(asrRoot, 'sensevoice_fast');
    final moonshineTinyStreamingRoot = p.join(
      asrRoot,
      'moonshine_tiny_streaming_en',
    );
    final whisperRoot = p.join(asrRoot, 'whisper');
    final llmRoot = p.join(supportPath, 'llm_models');
    return _ModelPaths(
      asrRoot: asrRoot,
      senseVoiceRoot: senseVoiceRoot,
      fastSenseVoiceRoot: fastSenseVoiceRoot,
      moonshineTinyStreamingRoot: moonshineTinyStreamingRoot,
      whisperRoot: whisperRoot,
      llmRoot: llmRoot,
    );
  }
}

class _ModelPaths {
  const _ModelPaths({
    required this.asrRoot,
    required this.senseVoiceRoot,
    required this.fastSenseVoiceRoot,
    required this.moonshineTinyStreamingRoot,
    required this.whisperRoot,
    required this.llmRoot,
  });

  final String asrRoot;
  final String senseVoiceRoot;
  final String fastSenseVoiceRoot;
  final String moonshineTinyStreamingRoot;
  final String whisperRoot;
  final String llmRoot;

  Future<void> createDirectories() async {
    await Directory(senseVoiceRoot).create(recursive: true);
    await Directory(fastSenseVoiceRoot).create(recursive: true);
    await Directory(moonshineTinyStreamingRoot).create(recursive: true);
    await Directory(whisperRoot).create(recursive: true);
    await Directory(llmRoot).create(recursive: true);
  }
}

class _ModelInstallGroup {
  const _ModelInstallGroup({
    required this.label,
    required this.assetDirectory,
    required this.destinationDirectory,
    required this.fileNames,
    required this.runtimeModels,
    this.isRequired = true,
  });

  final String label;
  final String assetDirectory;
  final String destinationDirectory;
  final List<String> fileNames;
  final List<_RequiredRuntimeModel> runtimeModels;
  final bool isRequired;
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

class SenseVoiceModelProfile {
  const SenseVoiceModelProfile({required this.id, required this.files});

  const SenseVoiceModelProfile.standard(SenseVoiceModelFiles files)
    : this(id: standardId, files: files);

  const SenseVoiceModelProfile.fast(SenseVoiceModelFiles files)
    : this(id: fastId, files: files);

  static const String standardId = 'sensevoice_standard';
  static const String fastId = 'sensevoice_fast';

  final String id;
  final SenseVoiceModelFiles files;
}

class MoonshineModelFiles {
  const MoonshineModelFiles({required this.directory, required this.files});

  final String directory;
  final Map<String, String> files;
}

class ModelCheckResult {
  const ModelCheckResult({
    required this.asrRootPath,
    required this.senseVoiceFiles,
    required this.missingSenseVoiceFiles,
    required this.fastSenseVoiceFiles,
    required this.missingFastSenseVoiceFiles,
    required this.moonshineTinyStreamingFiles,
    required this.missingMoonshineTinyStreamingFiles,
    required this.whisperModelPath,
    required this.isWhisperModelReady,
    required this.llamaModelPath,
    required this.isLlamaModelReady,
  });

  final String asrRootPath;
  final SenseVoiceModelFiles senseVoiceFiles;
  final List<String> missingSenseVoiceFiles;
  final SenseVoiceModelFiles fastSenseVoiceFiles;
  final List<String> missingFastSenseVoiceFiles;
  final MoonshineModelFiles moonshineTinyStreamingFiles;
  final List<String> missingMoonshineTinyStreamingFiles;
  final String whisperModelPath;
  final bool isWhisperModelReady;
  final String llamaModelPath;
  final bool isLlamaModelReady;

  bool get isSenseVoiceReady => missingSenseVoiceFiles.isEmpty;
  bool get isFastSenseVoiceReady => missingFastSenseVoiceFiles.isEmpty;
  bool get isMoonshineTinyStreamingReady =>
      missingMoonshineTinyStreamingFiles.isEmpty;
  bool get isLiveAsrReady => isMoonshineTinyStreamingReady || isSenseVoiceReady;
  bool get hasFileTranscriptionSenseVoiceReady =>
      isFastSenseVoiceReady || isSenseVoiceReady;
  List<SenseVoiceModelProfile> get fileTranscriptionSenseVoiceProfiles => [
    if (isFastSenseVoiceReady) SenseVoiceModelProfile.fast(fastSenseVoiceFiles),
    if (isSenseVoiceReady) SenseVoiceModelProfile.standard(senseVoiceFiles),
  ];
  bool get hasInstallableMissingModels =>
      !isMoonshineTinyStreamingReady ||
      !isSenseVoiceReady ||
      !isWhisperModelReady ||
      !isLlamaModelReady;
}

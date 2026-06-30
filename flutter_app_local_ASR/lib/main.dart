import 'dart:async';
import 'dart:io' show Directory, File, FileSystemException;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;

import 'audio/pcm16_wav_io.dart';
import 'asr/asr_engine.dart';
import 'asr/fallback_asr_service.dart';
import 'asr/model_store.dart';
import 'asr/moonshine_asr_engine.dart';
import 'asr/partial_preview.dart';
import 'asr/sense_voice_file_transcriber.dart';
import 'asr/sherpa_sense_voice_asr_service.dart';
import 'asr/system_asr_engine.dart';
import 'asr/whisper_cpp_asr_engine.dart';
import 'l10n/app_strings.dart';
import 'native/local_native_bridge.dart';
import 'speaker/sherpa_speaker_service.dart';
import 'speaker/voice_profile_sample_recorder.dart';
import 'summary/llama_cpp_summary_service.dart';
import 'summary/meeting_summary_service.dart';
import 'storage/recording_database.dart';
import 'storage/recording_session.dart';
import 'storage/meeting_summary_record.dart';
import 'ui/meeting_picker_sheet.dart';
import 'ui/recording_detail_page.dart';
import 'ui/summary_detail_page.dart';

enum _PrimaryAsrModel { moonshine, sherpa }

extension _PrimaryAsrModelInfo on _PrimaryAsrModel {
  String get engineName {
    return switch (this) {
      _PrimaryAsrModel.moonshine => 'Moonshine Tiny Streaming',
      _PrimaryAsrModel.sherpa => 'Sherpa-ONNX SenseVoice',
    };
  }

  String label(AppStrings strings) {
    return switch (this) {
      _PrimaryAsrModel.moonshine => strings.moonshineModelChoice,
      _PrimaryAsrModel.sherpa => strings.sherpaModelChoice,
    };
  }

  String fullLabel(AppStrings strings) {
    return switch (this) {
      _PrimaryAsrModel.moonshine => strings.moonshineTinyStreaming,
      _PrimaryAsrModel.sherpa => strings.sherpaSenseVoice,
    };
  }
}

void main() {
  runApp(const MeetingAsrApp());
}

class MeetingAsrApp extends StatelessWidget {
  const MeetingAsrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppStrings.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppStrings.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF465DFF),
          primary: const Color(0xFF465DFF),
          secondary: const Color(0xFF10B7C7),
          tertiary: const Color(0xFFFF8A34),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 66,
          elevation: 0,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE8EDFF),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFFF5F6FA),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const MeetingAsrPage(),
    );
  }
}

class _StatusMessage {
  const _StatusMessage(this._resolver, {this.tone = _StatusTone.info});

  factory _StatusMessage.raw(String value) {
    return _StatusMessage((strings) => strings.runtimeStatus(value));
  }

  final String Function(AppStrings strings) _resolver;
  final _StatusTone tone;

  String resolve(AppStrings strings) => _resolver(strings);
}

class MeetingAsrPage extends StatefulWidget {
  const MeetingAsrPage({super.key});

  @override
  State<MeetingAsrPage> createState() => _MeetingAsrPageState();
}

class _MeetingAsrPageState extends State<MeetingAsrPage>
    with WidgetsBindingObserver {
  late final ModelStore _modelStore;
  late final FallbackAsrService _asrService;
  late final SenseVoiceFileTranscriber _senseVoiceFileTranscriber;
  late final SherpaSpeakerService _speakerService;
  late final VoiceProfileSampleRecorder _voiceProfileRecorder;
  late final MeetingSummaryService _simpleSummaryService;
  late final MeetingSummaryService _detailedSummaryService;

  ModelCheckResult? _modelCheck;
  NativeBridgeReport? _nativeBridgeReport;
  final List<AsrSegment> _liveSegments = [];
  List<RecordingSession> _recordings = [];
  List<MeetingSummaryRecord> _summaries = [];
  List<VoiceProfile> _voiceProfiles = const <VoiceProfile>[];
  RecordingSession? _selectedRecording;
  DateTime? _recordingStartedAt;
  AsrPartial? _partial;
  Timer? _partialRevealTimer;
  Timer? _voiceProfileTimer;
  String _partialTargetText = '';
  String _partialVisibleText = '';
  DateTime _partialUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _partialEngineName = '';
  SummaryTemplate _selectedSummaryTemplate = SummaryTemplate.general;
  SummaryMode _selectedSummaryMode = SummaryMode.simple;
  _StatusMessage _status = _StatusMessage(
    (strings) => strings.checkingLocalModels,
  );
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  bool _isSummarizing = false;
  bool _isInstallingModels = false;
  bool _isImportingAudio = false;
  bool _isRecordingVoiceProfile = false;
  bool _isSavingVoiceProfile = false;
  Duration _voiceProfileElapsed = Duration.zero;
  int? _recordingVoiceProfileId;
  String? _recordingVoiceProfileName;
  _PrimaryAsrModel _selectedPrimaryAsrModel = _PrimaryAsrModel.moonshine;
  int _selectedTab = 0;

  static const int _summaryTabIndex = 3;
  static const int _minVoiceProfileDurationMs = 10000;
  static const int _minSpeakerTurnForEmbeddingMs = 400;
  static const int _minSpeakerEmbeddingDurationMs = 1500;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _modelStore = ModelStore();
    _asrService = FallbackAsrService(
      engines: [
        MoonshineAsrEngine(modelStore: _modelStore),
        SherpaSenseVoiceAsrService(modelStore: _modelStore),
        WhisperCppAsrEngine(modelStore: _modelStore),
        SystemAsrEngine(),
      ],
    );
    _applySelectedPrimaryAsrModel();
    _senseVoiceFileTranscriber = SenseVoiceFileTranscriber(
      modelStore: _modelStore,
    );
    _speakerService = SherpaSpeakerService(modelStore: _modelStore);
    _voiceProfileRecorder = VoiceProfileSampleRecorder();
    _simpleSummaryService = FallbackMeetingSummaryService(
      engines: [
        HeuristicMeetingSummaryService(),
        LlamaCppSummaryService(modelStore: _modelStore),
      ],
    );
    _detailedSummaryService = FallbackMeetingSummaryService(
      engines: [
        LlamaCppSummaryService(modelStore: _modelStore),
        HeuristicMeetingSummaryService(),
      ],
    );

    _asrService.segments.listen((segment) {
      if (!_isRecording && !_isStoppingRecording) {
        return;
      }
      _liveSegments.insert(0, segment);
      if (!mounted) {
        return;
      }
      setState(() {
        _clearPartialPreviewState();
      });
    });
    _asrService.partials.listen((partial) {
      _queuePartialPreview(partial);
    });
    _asrService.status.listen((status) {
      setState(() => _status = _StatusMessage.raw(status));
    });

    _prepareModels();
    _loadRecordings();
    _loadSummaries();
    _loadVoiceProfiles();
  }

  void _applySelectedPrimaryAsrModel() {
    _asrService.useOnlyEngine(_selectedPrimaryAsrModel.engineName);
  }

  void _onPrimaryAsrModelChanged(_PrimaryAsrModel model) {
    if (_selectedPrimaryAsrModel == model) {
      return;
    }
    if (_isRecording || _isStoppingRecording || _isImportingAudio) {
      setState(() {
        _status = _StatusMessage(
          (strings) => strings.primaryAsrChangeBlocked,
          tone: _StatusTone.info,
        );
      });
      return;
    }

    setState(() {
      _selectedPrimaryAsrModel = model;
      _applySelectedPrimaryAsrModel();
      _status = _StatusMessage(
        (strings) => _primaryAsrReadyStatus(
          strings,
          check: _modelCheck,
          bridgeReport: _nativeBridgeReport,
        ),
        tone: _selectedPrimaryAsrReady(_modelCheck, _nativeBridgeReport)
            ? _StatusTone.success
            : _StatusTone.info,
      );
    });
  }

  Future<void> _loadSummaries() async {
    try {
      final summaries = await RecordingDatabase.instance.listSummaries();
      if (!mounted) {
        return;
      }
      setState(() => _summaries = summaries);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _StatusMessage(
          (strings) => strings.errorMessage(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  void _onTabSelected(int index) {
    setState(() => _selectedTab = index);
    if (index == _summaryTabIndex) {
      unawaited(_loadSummaries());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadSummaries());
      unawaited(_loadRecordings());
      unawaited(_loadVoiceProfiles());
    }
  }

  Future<void> _loadRecordings() async {
    final recordings = await RecordingDatabase.instance.listRecordings();
    if (!mounted) {
      return;
    }
    setState(() => _recordings = recordings);
  }

  Future<void> _loadVoiceProfiles() async {
    final profiles = await RecordingDatabase.instance.listVoiceProfiles();
    if (!mounted) {
      return;
    }
    setState(() => _voiceProfiles = profiles);
  }

  Future<void> _stopCurrentVoiceProfileRecording() async {
    if (_isRecordingVoiceProfile) {
      await _stopVoiceProfileRecording();
    }
  }

  Future<void> _addVoiceProfile() async {
    if (_isRecordingVoiceProfile || _isSavingVoiceProfile) {
      return;
    }
    final strings = AppStrings.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _VoiceProfileNameDialog(
        initialName: strings.defaultVoiceProfileName(_voiceProfiles.length + 1),
        title: strings.addVoiceProfile,
      ),
    );
    if (!mounted || name == null || name.trim().isEmpty) {
      return;
    }
    await _startVoiceProfileRecording(displayName: name.trim());
  }

  Future<void> _reRecordVoiceProfile(VoiceProfile profile) async {
    await _startVoiceProfileRecording(
      profileId: profile.id,
      displayName: profile.displayName,
    );
  }

  Future<void> _startVoiceProfileRecording({
    int? profileId,
    required String displayName,
  }) async {
    if (_isRecording ||
        _isStoppingRecording ||
        _isImportingAudio ||
        _isSummarizing ||
        _isInstallingModels ||
        _isRecordingVoiceProfile ||
        _isSavingVoiceProfile) {
      return;
    }

    try {
      final check = await _modelStore.inspect();
      if (!check.isSpeakerEmbeddingReady) {
        setState(() {
          _modelCheck = check;
          _status = _StatusMessage(
            (strings) => strings.speakerModelsUnavailableForAnalysis,
            tone: _StatusTone.error,
          );
        });
        return;
      }
      await _voiceProfileRecorder.start(path: await _voiceProfileAudioPath());
      _voiceProfileTimer?.cancel();
      _voiceProfileTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceProfileElapsed += const Duration(seconds: 1);
        });
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _modelCheck = check;
        _isRecordingVoiceProfile = true;
        _voiceProfileElapsed = Duration.zero;
        _recordingVoiceProfileId = profileId;
        _recordingVoiceProfileName = displayName.trim();
        _status = _StatusMessage(
          (strings) => strings.recordingVoiceProfile(displayName.trim()),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoiceProfile = false;
        _voiceProfileElapsed = Duration.zero;
        _recordingVoiceProfileId = null;
        _recordingVoiceProfileName = null;
        _status = _StatusMessage(
          (strings) => strings.errorMessage(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  Future<void> _stopVoiceProfileRecording() async {
    final appStrings = AppStrings.of(context);
    _voiceProfileTimer?.cancel();
    _voiceProfileTimer = null;
    final profileId = _recordingVoiceProfileId;
    final profileName =
        _recordingVoiceProfileName ?? appStrings.defaultVoiceProfileName(1);
    setState(() {
      _isRecordingVoiceProfile = false;
      _isSavingVoiceProfile = true;
      _status = _StatusMessage(
        (strings) => strings.savingVoiceProfile(profileName),
      );
    });

    Pcm16AudioFile? sampleFile;
    try {
      sampleFile = await _voiceProfileRecorder.stop();
      if (sampleFile == null) {
        throw StateError(appStrings.voiceProfileNoAudio);
      }
      if (sampleFile.durationMs < _minVoiceProfileDurationMs) {
        await _deleteFileIfExists(sampleFile.path);
        throw StateError(appStrings.voiceProfileTooShort);
      }
      final audio = await readPcm16WavFile(sampleFile.path);
      final embedding = await _speakerService.computeEmbeddingFromPcm16Audio(
        pcm16Audio: audio.pcm16Audio,
        audioSampleRate: audio.sampleRate,
      );
      if (embedding.isEmpty) {
        await _deleteFileIfExists(sampleFile.path);
        throw StateError(appStrings.voiceProfileEmbeddingEmpty);
      }
      final previousProfile = profileId == null
          ? null
          : await RecordingDatabase.instance.getVoiceProfile(profileId);
      final profile = await RecordingDatabase.instance.saveVoiceProfile(
        id: profileId,
        displayName: profileName,
        embedding: embedding.values,
        sampleAudioPath: sampleFile.path,
        sampleRate: sampleFile.sampleRate,
        durationMs: sampleFile.durationMs,
      );
      if (previousProfile != null &&
          previousProfile.sampleAudioPath != sampleFile.path) {
        unawaited(_deleteFileIfExists(previousProfile.sampleAudioPath));
      }
      if (!mounted) {
        return;
      }
      final profiles = await RecordingDatabase.instance.listVoiceProfiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceProfiles = profiles;
        _isSavingVoiceProfile = false;
        _voiceProfileElapsed = Duration.zero;
        _recordingVoiceProfileId = null;
        _recordingVoiceProfileName = null;
        _status = _StatusMessage(
          (strings) => strings.voiceProfileSaved(profile.displayName),
          tone: _StatusTone.success,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingVoiceProfile = false;
        _voiceProfileElapsed = Duration.zero;
        _recordingVoiceProfileId = null;
        _recordingVoiceProfileName = null;
        _status = _StatusMessage(
          (strings) => strings.errorMessage(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  Future<void> _renameVoiceProfile(VoiceProfile profile) async {
    final profileId = profile.id;
    if (profileId == null) {
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          _VoiceProfileNameDialog(initialName: profile.displayName),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final updated = await RecordingDatabase.instance.updateVoiceProfileName(
      profileId,
      name,
    );
    if (!mounted || updated == null) {
      return;
    }
    final profiles = await RecordingDatabase.instance.listVoiceProfiles();
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceProfiles = profiles;
      _status = _StatusMessage(
        (strings) => strings.voiceProfileRenamed(updated.displayName),
        tone: _StatusTone.success,
      );
    });
  }

  Future<void> _deleteVoiceProfile(VoiceProfile profile) async {
    final profileId = profile.id;
    if (profileId == null) {
      return;
    }
    final deleted = await RecordingDatabase.instance.deleteVoiceProfile(
      profileId,
    );
    if (deleted == null) {
      return;
    }
    await _deleteFileIfExists(deleted.sampleAudioPath);
    if (!mounted) {
      return;
    }
    final profiles = await RecordingDatabase.instance.listVoiceProfiles();
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceProfiles = profiles;
      _status = _StatusMessage(
        (strings) => strings.voiceProfileDeleted(profile.displayName),
        tone: _StatusTone.success,
      );
    });
  }

  Future<void> _saveCompletedRecording({
    required List<AsrSegment> segments,
    String? engineName,
    RecordingSourceType sourceType = RecordingSourceType.live,
    String? title,
    DateTime? createdAt,
    CapturedRecordingAudio? capturedAudio,
  }) async {
    if (segments.isEmpty) {
      return;
    }

    final strings = AppStrings.of(context);
    final session = await RecordingDatabase.instance.saveRecording(
      title:
          title ??
          await RecordingDatabase.instance.nextDefaultTitle(isZh: strings.isZh),
      segments: segments,
      engineName: engineName,
      sourceType: sourceType,
      createdAt: createdAt ?? _recordingStartedAt,
      audioPath: capturedAudio?.path,
      audioSampleRate: capturedAudio?.sampleRate,
      audioDurationMs: capturedAudio?.durationMs,
    );
    if (!mounted) {
      return;
    }
    await _loadRecordings();
    setState(() {
      _selectedRecording = session;
      _status = _StatusMessage(
        (strings) => strings.recordingSaved(session.title),
        tone: _StatusTone.success,
      );
    });
    await _tryAutoAnalyzeSpeakers(session);
  }

  void _selectRecordingForSummary(RecordingSession session) {
    setState(() {
      _selectedRecording = session;
      _status = _StatusMessage(
        (strings) => strings.selectedForSummary,
        tone: _StatusTone.success,
      );
    });
  }

  Future<RecordingSession?> _pickRecordingForSummary() async {
    if (_recordings.isEmpty) {
      await _loadRecordings();
    }
    if (!mounted) {
      return null;
    }
    if (_recordings.isEmpty) {
      setState(() {
        _status = _StatusMessage((strings) => strings.noRecordingsYet);
      });
      return null;
    }
    return MeetingPickerSheet.show(context: context, recordings: _recordings);
  }

  Future<void> _openSummaryDetail(MeetingSummaryRecord record) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SummaryDetailPage(record: record),
      ),
    );
  }

  Future<void> _openRecordingDetail(RecordingSession session) async {
    final check = await _modelStore.inspect();
    if (!mounted) {
      return;
    }
    setState(() => _modelCheck = check);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RecordingDetailPage(
          session: session,
          speakerModelsReady: check.isSherpaSpeakerProcessingReady,
          onUseForSummary: () {
            _selectRecordingForSummary(session);
            Navigator.of(context).pop();
            _onTabSelected(_summaryTabIndex);
          },
          onAnalyzeSpeakers: _analyzeSpeakersForRecording,
        ),
      ),
    );
  }

  void _queuePartialPreview(AsrPartial partial) {
    if (!mounted) {
      return;
    }

    final target = latestPartialPreviewText(partial.text);
    setState(() {
      if (target.isEmpty) {
        _clearPartialPreviewState();
        return;
      }

      _partialTargetText = target;
      _partialUpdatedAt = partial.updatedAt;
      _partialEngineName = partial.engineName;

      if (!_partialTargetText.startsWith(_partialVisibleText)) {
        _partialVisibleText = _commonPrefix(
          _partialVisibleText,
          _partialTargetText,
        );
      }
      _advancePartialPreviewState();
    });
    _ensurePartialRevealTimer();
  }

  void _ensurePartialRevealTimer() {
    if (_partialRevealTimer?.isActive ?? false) {
      return;
    }

    _partialRevealTimer = Timer.periodic(const Duration(milliseconds: 38), (_) {
      if (!mounted) {
        _partialRevealTimer?.cancel();
        return;
      }

      setState(() {
        if (_partialTargetText.isEmpty ||
            _partialVisibleText == _partialTargetText) {
          _partialRevealTimer?.cancel();
          _partialRevealTimer = null;
          return;
        }
        _advancePartialPreviewState();
      });
    });
  }

  void _advancePartialPreviewState() {
    if (_partialTargetText.isEmpty) {
      _partial = null;
      return;
    }

    _partialVisibleText = _nextPrefix(
      target: _partialTargetText,
      current: _partialVisibleText,
    );
    _partial = AsrPartial(
      text: _partialVisibleText,
      updatedAt: _partialUpdatedAt,
      engineName: _partialEngineName,
    );
  }

  void _clearPartialPreviewState() {
    _partialRevealTimer?.cancel();
    _partialRevealTimer = null;
    _partialTargetText = '';
    _partialVisibleText = '';
    _partialEngineName = '';
    _partialUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _partial = null;
  }

  String _nextPrefix({required String target, required String current}) {
    final targetRunes = target.runes.toList(growable: false);
    final currentLength = current.runes.length;
    final nextLength = (currentLength + 1).clamp(0, targetRunes.length);
    return String.fromCharCodes(targetRunes.take(nextLength));
  }

  String _commonPrefix(String first, String second) {
    final firstRunes = first.runes.toList(growable: false);
    final secondRunes = second.runes.toList(growable: false);
    var index = 0;
    while (index < firstRunes.length &&
        index < secondRunes.length &&
        firstRunes[index] == secondRunes[index]) {
      index += 1;
    }
    return String.fromCharCodes(firstRunes.take(index));
  }

  Future<void> _prepareModels() async {
    await _modelStore.purgeBundledModelCopies();
    final initial = await _modelStore.inspect();
    final initialBridgeReport = await _inspectNativeBridges(initial);
    if (!mounted) {
      return;
    }

    if (_selectedPrimaryAsrReady(initial, initialBridgeReport)) {
      setState(() {
        _modelCheck = initial;
        _nativeBridgeReport = initialBridgeReport;
        _status = _StatusMessage(
          (strings) => _primaryAsrReadyStatus(
            strings,
            check: initial,
            bridgeReport: initialBridgeReport,
          ),
          tone: _StatusTone.success,
        );
      });
      return;
    }

    setState(() {
      _modelCheck = initial;
      _nativeBridgeReport = initialBridgeReport;
      _isInstallingModels = true;
    });

    try {
      await _modelStore.installBundledModels(
        scope: ModelInstallScope.primaryAsr,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _status = _StatusMessage(
              (strings) => strings.installingBundledModel(
                progress.label,
                _formatInstallProgress(progress),
              ),
            );
          });
        },
      );
      final result = await _modelStore.inspect();
      final bridgeReport = await _inspectNativeBridges(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _modelCheck = result;
        _nativeBridgeReport = bridgeReport;
        _isInstallingModels = false;
        _status = _StatusMessage(
          (strings) => _primaryAsrReadyStatus(
            strings,
            check: result,
            bridgeReport: bridgeReport,
          ),
          tone: _hasReadyLiveAsr(result, bridgeReport)
              ? _StatusTone.success
              : _StatusTone.info,
        );
      });
    } on MissingBundledModelsException catch (error) {
      final result = await _modelStore.inspect();
      final bridgeReport = await _inspectNativeBridges(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _modelCheck = result;
        _nativeBridgeReport = bridgeReport;
        _isInstallingModels = false;
        _status = _StatusMessage(
          (strings) => strings.bundledModelsMissing(error.missingAssets.length),
          tone: _StatusTone.error,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInstallingModels = false;
        _status = _StatusMessage(
          (strings) => strings.installModelsFailed(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  Future<void> _installSpeakerModels() async {
    if (_isInstallingModels) {
      return;
    }

    setState(() {
      _isInstallingModels = true;
      _status = _StatusMessage((strings) => strings.installingSpeakerModels);
    });

    try {
      await _modelStore.installBundledModels(
        scope: ModelInstallScope.speakerProcessing,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _status = _StatusMessage(
              (strings) => strings.installingBundledModel(
                progress.label,
                _formatInstallProgress(progress),
              ),
            );
          });
        },
      );
      final result = await _modelStore.inspect();
      final bridgeReport = await _inspectNativeBridges(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _modelCheck = result;
        _nativeBridgeReport = bridgeReport;
        _isInstallingModels = false;
        _status = _StatusMessage(
          (strings) => result.isSherpaSpeakerProcessingReady
              ? strings.speakerModelsReady
              : strings.speakerModelsMissing,
          tone: result.isSherpaSpeakerProcessingReady
              ? _StatusTone.success
              : _StatusTone.info,
        );
      });
    } on MissingBundledModelsException catch (error) {
      final result = await _modelStore.inspect();
      final bridgeReport = await _inspectNativeBridges(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _modelCheck = result;
        _nativeBridgeReport = bridgeReport;
        _isInstallingModels = false;
        _status = _StatusMessage(
          (strings) => strings.bundledModelsMissing(error.missingAssets.length),
          tone: _StatusTone.error,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInstallingModels = false;
        _status = _StatusMessage(
          (strings) => strings.installModelsFailed(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  List<AsrSegment> _buildSegmentsToPersist() {
    final segments = List<AsrSegment>.from(_liveSegments)
      ..sort((a, b) => a.index.compareTo(b.index));

    final partialText = _partialTargetText.trim().isNotEmpty
        ? _partialTargetText.trim()
        : _partialVisibleText.trim();
    if (partialText.isEmpty) {
      return segments;
    }

    final alreadyCovered = segments.any((segment) {
      final text = segment.text.trim();
      if (text.isEmpty) {
        return false;
      }
      return text == partialText ||
          text.contains(partialText) ||
          partialText.contains(text);
    });
    if (alreadyCovered) {
      return segments;
    }

    final nextIndex = segments.isEmpty
        ? 1
        : segments
                  .map((segment) => segment.index)
                  .reduce((left, right) => left > right ? left : right) +
              1;
    segments.add(
      AsrSegment(
        index: nextIndex,
        text: partialText,
        createdAt: DateTime.now(),
        engineName: _partialEngineName.isEmpty
            ? (_asrService.activeEngineName ?? 'partial')
            : _partialEngineName,
      ),
    );
    return segments;
  }

  Future<NativeBridgeReport> _inspectNativeBridges(ModelCheckResult check) {
    return LocalNativeBridge.instance.inspectBridges(
      moonshineModelPath: check.moonshineTinyStreamingFiles.directory,
      whisperModelPath: check.whisperModelPath,
      llamaModelPath: check.llamaModelPath,
    );
  }

  bool _hasReadyLiveAsr(
    ModelCheckResult check,
    NativeBridgeReport bridgeReport,
  ) {
    return _isSelectedPrimaryAsrReady(check, bridgeReport);
  }

  bool _isMoonshineReady(
    ModelCheckResult check,
    NativeBridgeReport bridgeReport,
  ) {
    return check.isMoonshineTinyStreamingReady &&
        bridgeReport.moonshine.isAvailable;
  }

  bool _isSelectedPrimaryAsrReady(
    ModelCheckResult check,
    NativeBridgeReport bridgeReport,
  ) {
    return switch (_selectedPrimaryAsrModel) {
      _PrimaryAsrModel.moonshine => _isMoonshineReady(check, bridgeReport),
      _PrimaryAsrModel.sherpa => check.isSenseVoiceReady,
    };
  }

  bool _selectedPrimaryAsrReady(
    ModelCheckResult? check,
    NativeBridgeReport? bridgeReport,
  ) {
    if (check == null || bridgeReport == null) {
      return false;
    }
    return _isSelectedPrimaryAsrReady(check, bridgeReport);
  }

  String _primaryAsrReadyStatus(
    AppStrings strings, {
    required ModelCheckResult? check,
    required NativeBridgeReport? bridgeReport,
  }) {
    if (check == null || bridgeReport == null) {
      return strings.checkingLocalModels;
    }
    if (_isSelectedPrimaryAsrReady(check, bridgeReport)) {
      return switch (_selectedPrimaryAsrModel) {
        _PrimaryAsrModel.moonshine => strings.primaryAsrReadyMoonshine,
        _PrimaryAsrModel.sherpa => strings.primaryAsrReady,
      };
    }
    return strings.selectedPrimaryAsrMissing(
      _selectedPrimaryAsrModel.fullLabel(strings),
    );
  }

  Future<List<AsrSegment>> _transcribeImportedAudio({
    required PickedAudioFile picked,
    required ModelCheckResult check,
    required NativeBridgeReport bridgeReport,
    required AppStrings strings,
  }) async {
    final totalWatch = Stopwatch()..start();
    final sourceBytes = await _safeFileLength(picked.path);
    debugPrint(
      '[ASR timing] import start file=${picked.name} path=${picked.path} '
      'sourceBytes=$sourceBytes',
    );
    switch (_selectedPrimaryAsrModel) {
      case _PrimaryAsrModel.moonshine:
        if (!check.isMoonshineTinyStreamingReady ||
            !bridgeReport.moonshine.isAvailable) {
          throw StateError(
            bridgeReport.moonshine.reason ??
                strings.selectedPrimaryAsrMissing(
                  _selectedPrimaryAsrModel.fullLabel(strings),
                ),
          );
        }
        final moonshineWatch = Stopwatch()..start();
        final moonshineSegments = await LocalNativeBridge.instance
            .transcribeAudioFileWithMoonshine(
              modelPath: check.moonshineTinyStreamingFiles.directory,
              audioFilePath: picked.path,
            );
        moonshineWatch.stop();
        debugPrint(
          '[ASR timing] import engine=Moonshine elapsedMs='
          '${moonshineWatch.elapsedMilliseconds} segments='
          '${moonshineSegments.length} chars='
          '${_segmentTextLength(moonshineSegments.map((segment) => segment.text))}',
        );
        totalWatch.stop();
        debugPrint(
          '[ASR timing] import done engine=Moonshine totalMs='
          '${totalWatch.elapsedMilliseconds} file=${picked.name}',
        );
        return [
          for (var i = 0; i < moonshineSegments.length; i += 1)
            AsrSegment(
              index: i + 1,
              text: moonshineSegments[i].text,
              createdAt: DateTime.now(),
              engineName: 'Moonshine Tiny Streaming file: ${picked.name}',
            ),
        ];
      case _PrimaryAsrModel.sherpa:
        var currentCheck = check;
        if (!currentCheck.isFastSenseVoiceReady) {
          await _modelStore.installBundledModels(
            scope: ModelInstallScope.fastAsr,
            onProgress: (_) {},
          );
          currentCheck = await _modelStore.inspect();
        }
        if (!currentCheck.hasFileTranscriptionSenseVoiceReady) {
          throw StateError(
            strings.selectedPrimaryAsrMissing(
              _selectedPrimaryAsrModel.fullLabel(strings),
            ),
          );
        }

        final senseVoiceWatch = Stopwatch()..start();
        final decodeWatch = Stopwatch()..start();
        final decoded = await LocalNativeBridge.instance.decodeAudioFileToPcm16(
          audioFilePath: picked.path,
        );
        decodeWatch.stop();
        final pcmDurationSeconds =
            decoded.pcm16Audio.length / 2 / decoded.sampleRate;
        debugPrint(
          '[ASR import] source file=${picked.name} path=${picked.path} '
          'sourceBytes=$sourceBytes audioToPcm='
          '${decodeWatch.elapsedMilliseconds}ms '
          'pcmBytes=${decoded.pcm16Audio.length} '
          'sampleRate=${decoded.sampleRate} '
          'pcmDuration=${pcmDurationSeconds.toStringAsFixed(2)}s',
        );
        if (decoded.pcm16Audio.isEmpty) {
          return const <AsrSegment>[];
        }
        final senseVoiceDecodeWatch = Stopwatch()..start();
        final segments = await _senseVoiceFileTranscriber.transcribePcm16Audio(
          pcm16Audio: decoded.pcm16Audio,
          sourceName: picked.name,
          modelProfiles: currentCheck.fileTranscriptionSenseVoiceProfiles,
          preprocessingMode: FileAudioPreprocessingMode.none,
        );
        senseVoiceDecodeWatch.stop();
        senseVoiceWatch.stop();
        debugPrint(
          '[ASR timing] import engine=SenseVoice elapsedMs='
          '${senseVoiceWatch.elapsedMilliseconds} decodeMs='
          '${decodeWatch.elapsedMilliseconds} asrMs='
          '${senseVoiceDecodeWatch.elapsedMilliseconds} segments='
          '${segments.length} chars='
          '${_segmentTextLength(segments.map((segment) => segment.text))}',
        );
        totalWatch.stop();
        debugPrint(
          '[ASR timing] import done engine=SenseVoice totalMs='
          '${totalWatch.elapsedMilliseconds} file=${picked.name}',
        );
        return segments;
    }
  }

  Future<CapturedRecordingAudio?> _saveImportedAudio(
    PickedAudioFile picked,
  ) async {
    final decoded = await LocalNativeBridge.instance.decodeAudioFileToPcm16(
      audioFilePath: picked.path,
    );
    if (decoded.pcm16Audio.isEmpty) {
      return null;
    }
    final saved = await savePcm16WavFile(
      path: await _recordingAudioPath('import'),
      pcm16Audio: decoded.pcm16Audio,
      sampleRate: decoded.sampleRate,
    );
    return _capturedAudioFromFile(saved);
  }

  Future<String> _recordingAudioPath(String prefix) async {
    final supportPath = await LocalNativeBridge.instance
        .applicationSupportDirectory();
    final directory = Directory(p.join(supportPath, 'recording_audio'));
    await directory.create(recursive: true);
    return p.join(
      directory.path,
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
  }

  Future<String> _voiceProfileAudioPath() async {
    final supportPath = await LocalNativeBridge.instance
        .applicationSupportDirectory();
    final directory = Directory(p.join(supportPath, 'voice_profiles'));
    await directory.create(recursive: true);
    return p.join(
      directory.path,
      'self_sample_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
  }

  Future<void> _deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best-effort cleanup; stale local audio should not block the UI.
    }
  }

  CapturedRecordingAudio _capturedAudioFromFile(Pcm16AudioFile file) {
    return CapturedRecordingAudio(
      path: file.path,
      sampleRate: file.sampleRate,
      durationMs: file.durationMs,
      byteLength: file.byteLength,
    );
  }

  Future<void> _analyzeSpeakersForRecording(RecordingSession session) async {
    await _runSpeakerAnalysisForRecording(
      session,
      voiceProfiles: await RecordingDatabase.instance.listVoiceProfiles(),
    );
    await _loadRecordings();
  }

  Future<void> _tryAutoAnalyzeSpeakers(RecordingSession session) async {
    if (!mounted) {
      return;
    }
    final profiles = _voiceProfiles.isNotEmpty
        ? _voiceProfiles
        : await RecordingDatabase.instance.listVoiceProfiles();
    if (profiles.isEmpty) {
      setState(() {
        _status = _StatusMessage(
          (strings) => strings.speakerAutoAnalysisSkippedNoVoiceProfiles,
          tone: _StatusTone.info,
        );
      });
      return;
    }
    if (!session.hasAudio) {
      setState(() {
        _status = _StatusMessage(
          (strings) => strings.speakerAutoAnalysisSkippedNoAudio,
          tone: _StatusTone.info,
        );
      });
      return;
    }

    final check = await _modelStore.inspect();
    if (!mounted) {
      return;
    }
    setState(() => _modelCheck = check);
    if (!check.isSherpaSpeakerProcessingReady) {
      setState(() {
        _status = _StatusMessage(
          (strings) => strings.speakerAutoAnalysisSkippedNoModels,
          tone: _StatusTone.info,
        );
      });
      return;
    }

    setState(() {
      _status = _StatusMessage((strings) => strings.analyzingSpeakers);
    });
    try {
      await _runSpeakerAnalysisForRecording(session, voiceProfiles: profiles);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _StatusMessage(
          (strings) => strings.speakerAutoAnalysisReady,
          tone: _StatusTone.success,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _StatusMessage(
          (strings) => strings.speakerAutoAnalysisFailed(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  Future<void> _runSpeakerAnalysisForRecording(
    RecordingSession session, {
    List<VoiceProfile> voiceProfiles = const <VoiceProfile>[],
  }) async {
    final check = await _modelStore.inspect();
    if (!check.isSherpaSpeakerProcessingReady) {
      throw StateError(
        'Missing speaker processing files: '
        '${[...check.missingSpeakerDiarizationFiles, ...check.missingSpeakerEmbeddingFiles].join(', ')}',
      );
    }
    final audioPath = session.audioPath;
    if (audioPath == null || audioPath.isEmpty) {
      throw StateError('Missing original audio for speaker analysis');
    }

    final audio = await readPcm16WavFile(audioPath);
    final rawTurns = await _speakerService.diarizePcm16Audio(
      pcm16Audio: audio.pcm16Audio,
      audioSampleRate: audio.sampleRate,
    );
    final turns = _speakerTurnsFromSherpaSegments(
      recordingId: session.id,
      segments: rawTurns,
      audioDurationMs: audio.durationMs,
    );
    if (turns.isEmpty) {
      throw StateError('No speaker turns were detected');
    }

    final embeddings = <SpeakerEmbeddingRecord>[];
    final turnsBySpeaker = <String, List<SpeakerTurn>>{};
    for (final turn in turns) {
      turnsBySpeaker.putIfAbsent(turn.speakerLabel, () => []).add(turn);
    }
    for (final entry in turnsBySpeaker.entries) {
      final embeddingTurns = entry.value
          .where((turn) => turn.durationMs >= _minSpeakerTurnForEmbeddingMs)
          .toList();
      final embeddingDurationMs = embeddingTurns.fold<int>(
        0,
        (total, turn) => total + turn.durationMs,
      );
      if (embeddingDurationMs < _minSpeakerEmbeddingDurationMs) {
        continue;
      }
      final speakerAudio = concatPcm16Audio(
        embeddingTurns.map(
          (turn) => slicePcm16Audio(
            pcm16Audio: audio.pcm16Audio,
            sampleRate: audio.sampleRate,
            startMs: turn.startMs,
            endMs: turn.endMs,
          ),
        ),
      );
      final embedding = await _speakerService.computeEmbeddingFromPcm16Audio(
        pcm16Audio: speakerAudio,
        audioSampleRate: audio.sampleRate,
      );
      if (embedding.isEmpty) {
        continue;
      }
      embeddings.add(
        SpeakerEmbeddingRecord(
          recordingId: session.id,
          speakerLabel: entry.key,
          embedding: embedding.values,
        ),
      );
    }
    final matches = await _speakerProfileMatches(
      recordingId: session.id,
      embeddings: embeddings,
      voiceProfiles: voiceProfiles,
    );

    await RecordingDatabase.instance.saveSpeakerAnalysis(
      recordingId: session.id,
      turns: turns,
      embeddings: embeddings,
      matches: matches,
    );
  }

  Future<List<SpeakerProfileMatch>> _speakerProfileMatches({
    required int recordingId,
    required List<SpeakerEmbeddingRecord> embeddings,
    required List<VoiceProfile> voiceProfiles,
  }) async {
    final profiles = [
      for (final profile in voiceProfiles)
        if (profile.id != null) profile,
    ];
    if (profiles.isEmpty || embeddings.isEmpty) {
      return const <SpeakerProfileMatch>[];
    }

    final strings = AppStrings.of(context);
    final profilesBySearchKey = <String, VoiceProfile>{
      for (final profile in profiles) 'profile:${profile.id}': profile,
    };
    final referenceEmbeddings = <String, Float32List>{
      for (final entry in profilesBySearchKey.entries)
        entry.key: entry.value.embedding,
    };
    final matches = <SpeakerProfileMatch>[];
    for (final embedding in embeddings) {
      final match = await _speakerService.findBestSpeakerEmbeddingMatch(
        embedding: embedding.embedding,
        referenceEmbeddings: referenceEmbeddings,
      );
      final matchedKey = match.name;
      final matchedProfile = profilesBySearchKey[matchedKey];
      matches.add(
        SpeakerProfileMatch(
          recordingId: recordingId,
          speakerLabel: embedding.speakerLabel,
          matchedProfileId: matchedProfile?.id,
          displayLabel: matchedProfile == null
              ? strings.otherSpeakerLabel(embedding.speakerLabel)
              : matchedProfile.displayName,
          isSelfMatch: match.isAccepted && matchedProfile != null,
          threshold: match.threshold,
        ),
      );
    }
    return matches;
  }

  List<SpeakerTurn> _speakerTurnsFromSherpaSegments({
    required int recordingId,
    required List<SpeakerTurnSegment> segments,
    required int audioDurationMs,
  }) {
    final turns = <SpeakerTurn>[];
    for (final segment in segments) {
      final startMs = (segment.startTimeSeconds * 1000)
          .round()
          .clamp(0, audioDurationMs)
          .toInt();
      final endMs = (segment.endTimeSeconds * 1000)
          .round()
          .clamp(startMs, audioDurationMs)
          .toInt();
      if (endMs <= startMs) {
        continue;
      }
      turns.add(
        SpeakerTurn(
          recordingId: recordingId,
          speakerLabel: 'Speaker ${segment.speakerIndex + 1}',
          startMs: startMs,
          endMs: endMs,
        ),
      );
    }
    turns.sort((a, b) {
      final start = a.startMs.compareTo(b.startMs);
      return start == 0 ? a.endMs.compareTo(b.endMs) : start;
    });
    return turns;
  }

  Future<int> _safeFileLength(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return -1;
    }
  }

  int _segmentTextLength(Iterable<String> texts) {
    var length = 0;
    for (final text in texts) {
      length += text.trim().length;
    }
    return length;
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final engineName = _asrService.activeEngineName;
      final recordingStartedAt = _recordingStartedAt;
      final stopWatch = Stopwatch()..start();
      setState(() {
        _isStoppingRecording = true;
        _status = _StatusMessage((strings) => strings.stoppingRecording);
      });
      await _asrService.stop();
      final capturedAudio = await _asrService.takeLastCapturedAudio();
      stopWatch.stop();
      await Future<void>.delayed(Duration.zero);
      final capturedSegments = _buildSegmentsToPersist();
      final recordedMs = recordingStartedAt == null
          ? 0
          : DateTime.now().difference(recordingStartedAt).inMilliseconds;
      debugPrint(
        '[ASR timing] live stop engine=${engineName ?? 'unknown'} '
        'recordedMs=$recordedMs stopMs=${stopWatch.elapsedMilliseconds} '
        'segments=${capturedSegments.length} chars='
        '${_segmentTextLength(capturedSegments.map((segment) => segment.text))}',
      );
      setState(() {
        _isRecording = false;
        _isStoppingRecording = false;
        _liveSegments.clear();
        _clearPartialPreviewState();
        _recordingStartedAt = null;
      });
      if (capturedSegments.isEmpty) {
        setState(() {
          _status = _StatusMessage(
            (strings) => strings.recordingNotSavedEmpty,
            tone: _StatusTone.error,
          );
        });
        return;
      }
      await _saveCompletedRecording(
        segments: capturedSegments,
        engineName: engineName,
        capturedAudio: capturedAudio,
      );
      return;
    }

    try {
      final prepareWatch = Stopwatch()..start();
      final result = await _modelStore.inspect();
      final bridgeReport = await _inspectNativeBridges(result);
      prepareWatch.stop();
      setState(() {
        _modelCheck = result;
        _nativeBridgeReport = bridgeReport;
        _liveSegments.clear();
        _clearPartialPreviewState();
        _recordingStartedAt = DateTime.now();
      });

      final startWatch = Stopwatch()..start();
      _applySelectedPrimaryAsrModel();
      await _asrService.start();
      startWatch.stop();
      debugPrint(
        '[ASR timing] live start engine=${_asrService.activeEngineName ?? 'unknown'} '
        'prepareMs=${prepareWatch.elapsedMilliseconds} '
        'startMs=${startWatch.elapsedMilliseconds}',
      );
      setState(() {
        _isRecording = true;
        _status = _StatusMessage(
          (strings) => strings.recordingWith(_asrService.activeEngineName),
          tone: _StatusTone.success,
        );
      });
    } catch (error) {
      setState(() {
        _isRecording = false;
        _recordingStartedAt = null;
        _status = _StatusMessage(
          (strings) => strings.errorMessage(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  Future<void> _summarize() async {
    if (_isRecordingVoiceProfile || _isSavingVoiceProfile) {
      return;
    }
    final recording = await _pickRecordingForSummary();
    if (!mounted || recording == null) {
      return;
    }

    final transcript = recording.fullTranscript();
    if (transcript.trim().isEmpty) {
      setState(() {
        _status = _StatusMessage((strings) => strings.noTranscriptToSummarize);
      });
      return;
    }

    await _summarizeRecording(recording, transcript);
  }

  Future<void> _summarizeRecording(
    RecordingSession recording,
    String transcript,
  ) async {
    final strings = AppStrings.of(context);

    setState(() {
      _isSummarizing = true;
      _status = _StatusMessage(
        (strings) => _selectedSummaryMode == SummaryMode.simple
            ? strings.summarizingFastSummary
            : strings.summarizingDetailedSummary,
      );
    });

    try {
      if (_selectedSummaryMode == SummaryMode.detailed) {
        await _modelStore.installBundledModels(
          scope: ModelInstallScope.detailedSummary,
          onProgress: (progress) {
            if (!mounted) {
              return;
            }
            setState(() {
              _status = _StatusMessage(
                (strings) => strings.installingBundledModel(
                  progress.label,
                  _formatInstallProgress(progress),
                ),
              );
            });
          },
        );
        final result = await _modelStore.inspect();
        final bridgeReport = await _inspectNativeBridges(result);
        if (!mounted) {
          return;
        }
        setState(() {
          _modelCheck = result;
          _nativeBridgeReport = bridgeReport;
          _status = _StatusMessage(
            (strings) => strings.summarizingDetailedSummary,
          );
        });
      }

      final summaryService = _selectedSummaryMode == SummaryMode.simple
          ? _simpleSummaryService
          : _detailedSummaryService;
      final summary = await summaryService.summarize(
        transcript,
        language: strings.isZh ? SummaryLanguage.zh : SummaryLanguage.en,
        summaryTemplate: _selectedSummaryTemplate,
      );
      final saved = await RecordingDatabase.instance.saveSummary(
        recording: recording,
        summary: summary,
        summaryTemplate: _selectedSummaryTemplate,
        summaryMode: _selectedSummaryMode,
        isZh: strings.isZh,
      );
      if (!mounted) {
        return;
      }
      await _loadSummaries();
      setState(() {
        _selectedRecording = recording;
        _isSummarizing = false;
        _status = _StatusMessage(
          (strings) => strings.summarySaved(saved.title),
          tone: _StatusTone.success,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSummarizing = false;
        _status = _StatusMessage(
          (strings) => strings.errorMessage(error),
          tone: _StatusTone.error,
        );
      });
    }
  }

  Future<void> _importAudioAndSummarize() async {
    if (_isRecording ||
        _isSummarizing ||
        _isImportingAudio ||
        _isInstallingModels ||
        _isRecordingVoiceProfile ||
        _isSavingVoiceProfile) {
      return;
    }

    final strings = AppStrings.of(context);
    setState(() {
      _isImportingAudio = true;
      _clearPartialPreviewState();
      _status = _StatusMessage((strings) => strings.pickingAudioFile);
    });

    PickedAudioFile? importedAudio;
    try {
      final picked = await LocalNativeBridge.instance.pickAudioFile();
      if (!mounted) {
        return;
      }
      if (picked == null) {
        setState(() {
          _isImportingAudio = false;
          _status = _StatusMessage((strings) => strings.audioImportCancelled);
        });
        return;
      }
      importedAudio = picked;

      final check = await _modelStore.inspect();
      final bridgeReport = await _inspectNativeBridges(check);
      if (!mounted) {
        return;
      }
      setState(() {
        _modelCheck = check;
        _nativeBridgeReport = bridgeReport;
        _status = _StatusMessage(
          (strings) => strings.transcribingAudioFile(picked.name),
        );
      });

      final importedSegments = await _transcribeImportedAudio(
        picked: picked,
        check: check,
        bridgeReport: bridgeReport,
        strings: strings,
      );
      if (!mounted) {
        return;
      }
      if (importedSegments.isEmpty) {
        throw StateError(strings.audioFileNoSpeech);
      }
      final capturedAudio = await _saveImportedAudio(picked);

      setState(() {
        _isImportingAudio = false;
        _status = _StatusMessage(
          (strings) => strings.audioFileTranscribed(picked.name),
          tone: _StatusTone.success,
        );
      });

      await _saveCompletedRecording(
        segments: importedSegments,
        engineName: importedSegments.first.engineName,
        sourceType: RecordingSourceType.import,
        title: strings.isZh ? '导入-${picked.name}' : 'Import-${picked.name}',
        capturedAudio: capturedAudio,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isImportingAudio = false;
        _isSummarizing = false;
        _status = _StatusMessage(
          (strings) => strings.errorMessage(error),
          tone: _StatusTone.error,
        );
      });
    } finally {
      final picked = importedAudio;
      if (picked != null) {
        try {
          await LocalNativeBridge.instance.deleteImportedAudioIfNeeded(
            picked.path,
          );
        } catch (_) {
          // Best-effort cleanup for copied import files.
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _partialRevealTimer?.cancel();
    _voiceProfileTimer?.cancel();
    _asrService.dispose();
    _voiceProfileRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final check = _modelCheck;
    final strings = AppStrings.of(context);
    final pages = [
      _ModelWorkspace(
        status: _status.resolve(strings),
        tone: _status.tone,
        modelCheck: check,
        nativeBridgeReport: _nativeBridgeReport,
        isInstallingModels: _isInstallingModels,
        selectedPrimaryAsrModel: _selectedPrimaryAsrModel,
        canChangePrimaryAsrModel:
            !_isRecording &&
            !_isStoppingRecording &&
            !_isImportingAudio &&
            !_isRecordingVoiceProfile &&
            !_isSavingVoiceProfile,
        onPrimaryAsrModelChanged: _onPrimaryAsrModelChanged,
        canInstallSpeakerModels:
            !_isRecording &&
            !_isStoppingRecording &&
            !_isImportingAudio &&
            !_isRecordingVoiceProfile &&
            !_isSavingVoiceProfile,
        onInstallSpeakerModels: _installSpeakerModels,
        onRefresh: _prepareModels,
      ),
      _RecordWorkspace(
        status: _status.resolve(strings),
        tone: _status.tone,
        isRecording: _isRecording,
        isBusy:
            _isSummarizing ||
            _isImportingAudio ||
            _isRecordingVoiceProfile ||
            _isSavingVoiceProfile,
        voiceProfiles: _voiceProfiles,
        isRecordingVoiceProfile: _isRecordingVoiceProfile,
        isSavingVoiceProfile: _isSavingVoiceProfile,
        voiceProfileElapsed: _voiceProfileElapsed,
        recordingVoiceProfileName: _recordingVoiceProfileName,
        speakerEmbeddingReady: check?.isSpeakerEmbeddingReady ?? false,
        activeEngineName: _asrService.activeEngineName,
        liveSegments: _liveSegments,
        recordings: _recordings,
        selectedRecordingTitle: _selectedRecording?.title,
        partial: _partial,
        onRecordPressed: _toggleRecording,
        onVoiceProfileAdd: _addVoiceProfile,
        onVoiceProfileStopRecording: _stopCurrentVoiceProfileRecording,
        onVoiceProfileReRecord: _reRecordVoiceProfile,
        onVoiceProfileRename: _renameVoiceProfile,
        onVoiceProfileDelete: _deleteVoiceProfile,
        onRefresh: _prepareModels,
        onRecordingTap: _openRecordingDetail,
      ),
      _ImportWorkspace(
        status: _status.resolve(strings),
        tone: _status.tone,
        isImportingAudio: _isImportingAudio,
        isInstallingModels: _isInstallingModels,
        isRecording:
            _isRecording || _isRecordingVoiceProfile || _isSavingVoiceProfile,
        isSummarizing: _isSummarizing,
        hasRecordings: _recordings.isNotEmpty,
        onImportAudioPressed: _importAudioAndSummarize,
        onRefresh: _prepareModels,
      ),
      _SummaryWorkspace(
        status: _status.resolve(strings),
        tone: _status.tone,
        isSummarizing: _isSummarizing,
        isRecording:
            _isRecording || _isRecordingVoiceProfile || _isSavingVoiceProfile,
        isImportingAudio: _isImportingAudio,
        hasRecordings: _recordings.isNotEmpty,
        summaries: _summaries,
        summaryTemplate: _selectedSummaryTemplate,
        summaryMode: _selectedSummaryMode,
        onSummaryTemplateChanged: (template) {
          setState(() => _selectedSummaryTemplate = template);
        },
        onSummaryModeChanged: (mode) {
          setState(() => _selectedSummaryMode = mode);
        },
        onSummarizePressed: _summarize,
        onSummaryTap: _openSummaryDetail,
        onRefresh: () async {
          await _loadRecordings();
          await _loadSummaries();
          await _prepareModels();
        },
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(_selectedTab),
            child: pages[_selectedTab],
          ),
        ),
      ),
      bottomNavigationBar: _AppBottomBar(
        selectedIndex: _selectedTab,
        onSelected: _onTabSelected,
        items: [
          _BottomBarItem(
            icon: Icons.memory_outlined,
            selectedIcon: Icons.memory,
            label: strings.modelsTab,
          ),
          _BottomBarItem(
            icon: Icons.mic_none_rounded,
            selectedIcon: Icons.mic_rounded,
            label: strings.recordTab,
          ),
          _BottomBarItem(
            icon: Icons.file_upload_outlined,
            selectedIcon: Icons.file_upload_rounded,
            label: strings.importTab,
          ),
          _BottomBarItem(
            icon: Icons.auto_awesome_outlined,
            selectedIcon: Icons.auto_awesome_rounded,
            label: strings.summaryTab,
          ),
        ],
      ),
    );
  }
}

class _AppBottomBar extends StatelessWidget {
  const _AppBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<_BottomBarItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8C4DE).withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _BottomTabButton(
                    item: items[index],
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _BottomBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const active = Color(0xFF465DFF);
    const inactive = Color(0xFF676C7B);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: selected ? 54 : 40,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE9EEFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 24,
                  color: selected ? active : inactive,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? const Color(0xFF222633) : inactive,
                ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem {
  const _BottomBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

String _formatInstallProgress(ModelInstallProgress progress) {
  return '${progress.itemIndex}/${progress.itemCount}';
}

String _formatShortDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.status,
    required this.tone,
    required this.modelCheck,
    required this.nativeBridgeReport,
    required this.isInstallingModels,
    required this.selectedPrimaryAsrModel,
    required this.canChangePrimaryAsrModel,
    required this.onPrimaryAsrModelChanged,
    required this.canInstallSpeakerModels,
    required this.onInstallSpeakerModels,
  });

  final String status;
  final _StatusTone tone;
  final ModelCheckResult? modelCheck;
  final NativeBridgeReport? nativeBridgeReport;
  final bool isInstallingModels;
  final _PrimaryAsrModel selectedPrimaryAsrModel;
  final bool canChangePrimaryAsrModel;
  final ValueChanged<_PrimaryAsrModel> onPrimaryAsrModelChanged;
  final bool canInstallSpeakerModels;
  final VoidCallback onInstallSpeakerModels;

  @override
  Widget build(BuildContext context) {
    final check = modelCheck;
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCBD6EE).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tone.icon, color: tone.color(colorScheme)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (check != null) ...[
              const SizedBox(height: 16),
              _PrimaryAsrSelector(
                selectedModel: selectedPrimaryAsrModel,
                enabled: canChangePrimaryAsrModel,
                onChanged: onPrimaryAsrModelChanged,
              ),
              const SizedBox(height: 14),
              _ModelStatusRow(
                label: strings.moonshineTinyStreaming,
                value: _bridgeValue(
                  strings,
                  modelReady: check.isMoonshineTinyStreamingReady,
                  bridge: nativeBridgeReport?.moonshine,
                  missingValue: strings.missingFiles(
                    check.missingMoonshineTinyStreamingFiles.length,
                  ),
                ),
                ok: nativeBridgeReport?.moonshine.isAvailable ?? false,
              ),
              _ModelStatusRow(
                label: strings.sherpaSenseVoice,
                value: check.isSenseVoiceReady
                    ? strings.ready
                    : strings.missingFiles(check.missingSenseVoiceFiles.length),
                ok: check.isSenseVoiceReady,
              ),
              _ModelStatusRow(
                label: strings.sherpaSpeakerDiarization,
                value: check.isSpeakerDiarizationReady
                    ? strings.ready
                    : strings.missingFiles(
                        check.missingSpeakerDiarizationFiles.length,
                      ),
                ok: check.isSpeakerDiarizationReady,
              ),
              _ModelStatusRow(
                label: strings.sherpaSpeakerEmbedding,
                value: check.isSpeakerEmbeddingReady
                    ? strings.ready
                    : strings.missingFiles(
                        check.missingSpeakerEmbeddingFiles.length,
                      ),
                ok: check.isSpeakerEmbeddingReady,
              ),
              if (!check.isSherpaSpeakerProcessingReady) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: canInstallSpeakerModels && !isInstallingModels
                        ? onInstallSpeakerModels
                        : null,
                    icon: isInstallingModels
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.group_add_rounded),
                    label: Text(strings.addSpeakerModels),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _ModelStatusRow(
                label: strings.whisperCpp,
                value: _bridgeValue(
                  strings,
                  modelReady: check.isWhisperModelReady,
                  bridge: nativeBridgeReport?.whisperCpp,
                  missingValue: strings.modelMissingBridgePending,
                ),
                ok: nativeBridgeReport?.whisperCpp.isAvailable ?? false,
              ),
              _ModelStatusRow(
                label: strings.systemAsr,
                value: strings.fallbackReady,
                ok: true,
              ),
              _ModelStatusRow(
                label: strings.llamaCppQwen,
                value: _bridgeValue(
                  strings,
                  modelReady: check.isLlamaModelReady,
                  bridge: nativeBridgeReport?.llamaCpp,
                  missingValue: strings.modelMissingBridgePending,
                ),
                ok: nativeBridgeReport?.llamaCpp.isAvailable ?? false,
              ),
              _ModelStatusRow(
                label: strings.rulesSummary,
                value: strings.fallbackReady,
                ok: true,
              ),
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  visualDensity: VisualDensity.compact,
                ),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    strings.modelPaths,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  children: [
                    _PathLine(strings.asrRoot, check.asrRootPath),
                    for (final file in check.missingMoonshineTinyStreamingFiles)
                      _PathLine(strings.missing, file),
                    for (final file in check.missingSenseVoiceFiles)
                      _PathLine(strings.missing, file),
                    for (final file in check.missingSpeakerDiarizationFiles)
                      _PathLine(strings.missing, file),
                    for (final file in check.missingSpeakerEmbeddingFiles)
                      _PathLine(strings.missing, file),
                    _PathLine(strings.whisper, check.whisperModelPath),
                    _PathLine(
                      strings.speakerDiarizationModel,
                      check.speakerDiarizationFiles.segmentation,
                    ),
                    _PathLine(
                      strings.speakerEmbeddingModel,
                      check.speakerEmbeddingFiles.model,
                    ),
                    _PathLine(strings.qwenGguf, check.llamaModelPath),
                  ],
                ),
              ),
              if (isInstallingModels) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PrimaryAsrSelector extends StatelessWidget {
  const _PrimaryAsrSelector({
    required this.selectedModel,
    required this.enabled,
    required this.onChanged,
  });

  final _PrimaryAsrModel selectedModel;
  final bool enabled;
  final ValueChanged<_PrimaryAsrModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.primaryAsrModel,
          style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_PrimaryAsrModel>(
            showSelectedIcon: false,
            selected: {selectedModel},
            onSelectionChanged: enabled
                ? (values) => onChanged(values.first)
                : null,
            segments: [
              ButtonSegment<_PrimaryAsrModel>(
                value: _PrimaryAsrModel.moonshine,
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: Text(
                  _PrimaryAsrModel.moonshine.label(strings),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment<_PrimaryAsrModel>(
                value: _PrimaryAsrModel.sherpa,
                icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                label: Text(
                  _PrimaryAsrModel.sherpa.label(strings),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _bridgeValue(
  AppStrings strings, {
  required bool modelReady,
  required NativeBridgeStatus? bridge,
  required String missingValue,
}) {
  if (!modelReady) {
    return missingValue;
  }
  if (bridge == null) {
    return strings.modelFoundBridgePending;
  }
  return bridge.isAvailable
      ? strings.bridgeReady
      : bridge.reason ?? strings.nativeRuntimeMissing;
}

enum _StatusTone {
  success,
  info,
  error;

  IconData get icon {
    return switch (this) {
      _StatusTone.success => Icons.check_circle,
      _StatusTone.info => Icons.info_outline,
      _StatusTone.error => Icons.error_outline,
    };
  }

  Color color(ColorScheme colorScheme) {
    return switch (this) {
      _StatusTone.success => colorScheme.primary,
      _StatusTone.info => colorScheme.secondary,
      _StatusTone.error => colorScheme.error,
    };
  }
}

class _ModelStatusRow extends StatelessWidget {
  const _ModelStatusRow({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ok
            ? const Color(0xFFF0FBF7)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.schedule_rounded,
            size: 18,
            color: ok ? const Color(0xFF17B26A) : colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF252A36),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6E7482),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  const _PathLine(this.label, this.path);

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$label: $path',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _WorkspaceScaffold extends StatelessWidget {
  const _WorkspaceScaffold({
    required this.title,
    required this.status,
    required this.tone,
    required this.children,
    required this.onRefresh,
  });

  final String title;
  final String status;
  final _StatusTone tone;
  final List<Widget> children;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        _BrandBar(onRefresh: onRefresh),
        const SizedBox(height: 16),
        _SectionHeader(title: title, status: status, tone: tone),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class _BrandBar extends StatelessWidget {
  const _BrandBar({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            strings.appTitle,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF232633),
            ),
          ),
        ),
        _RoundIconButton(
          tooltip: strings.refresh,
          icon: Icons.refresh_rounded,
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 20, color: const Color(0xFF222739)),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.status,
    required this.tone,
  });

  final String title;
  final String status;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F0FF), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFBFD2FF).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF3150FF),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: const Color(0xFF4C5262),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: tone.color(colorScheme),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: tone.color(colorScheme).withValues(alpha: 0.38),
                  blurRadius: 22,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(tone.icon, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCBD6EE).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _VoiceProfileNameDialog extends StatefulWidget {
  const _VoiceProfileNameDialog({required this.initialName, this.title});

  final String initialName;
  final String? title;

  @override
  State<_VoiceProfileNameDialog> createState() =>
      _VoiceProfileNameDialogState();
}

class _VoiceProfileNameDialogState extends State<_VoiceProfileNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(widget.title ?? strings.renameVoiceProfile),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: strings.voiceProfileName),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(strings.save),
        ),
      ],
    );
  }
}

class _VoiceLibraryCard extends StatelessWidget {
  const _VoiceLibraryCard({
    required this.profiles,
    required this.isRecording,
    required this.isSaving,
    required this.elapsed,
    required this.recordingName,
    required this.speakerEmbeddingReady,
    required this.canRecord,
    required this.onAddPressed,
    required this.onStopRecordingPressed,
    required this.onReRecordPressed,
    required this.onRenamePressed,
    required this.onDeletePressed,
  });

  final List<VoiceProfile> profiles;
  final bool isRecording;
  final bool isSaving;
  final Duration elapsed;
  final String? recordingName;
  final bool speakerEmbeddingReady;
  final bool canRecord;
  final VoidCallback onAddPressed;
  final VoidCallback onStopRecordingPressed;
  final ValueChanged<VoiceProfile> onReRecordPressed;
  final ValueChanged<VoiceProfile> onRenamePressed;
  final ValueChanged<VoiceProfile> onDeletePressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final canStartRecording = canRecord && speakerEmbeddingReady && !isSaving;
    final canEditProfiles = canRecord && !isRecording && !isSaving;
    return _ActionCard(
      icon: Icons.fingerprint_rounded,
      title: strings.voiceLibrary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profiles.isEmpty
                ? strings.voiceLibraryMissingHint
                : strings.voiceLibrarySummary(profiles.length),
            style: textTheme.bodyMedium,
          ),
          if (!speakerEmbeddingReady) ...[
            const SizedBox(height: 8),
            Text(
              strings.speakerModelsUnavailableForAnalysis,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isRecording)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: onStopRecordingPressed,
                icon: const Icon(Icons.stop_rounded),
                label: Text(
                  strings.stopAndSaveVoiceProfile(
                    recordingName ?? strings.voiceProfileName,
                    _formatShortDuration(elapsed),
                  ),
                ),
              ),
            )
          else if (isSaving)
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.savingVoiceProfile(
                      recordingName ?? strings.voiceProfileName,
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: canStartRecording ? onAddPressed : null,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(strings.addVoiceProfile),
              ),
            ),
          if (profiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final profile in profiles)
              _VoiceProfileRow(
                profile: profile,
                canReRecord: canStartRecording,
                canEdit: canEditProfiles,
                onReRecordPressed: () => onReRecordPressed(profile),
                onRenamePressed: () => onRenamePressed(profile),
                onDeletePressed: () => onDeletePressed(profile),
              ),
          ],
        ],
      ),
    );
  }
}

class _VoiceProfileRow extends StatelessWidget {
  const _VoiceProfileRow({
    required this.profile,
    required this.canReRecord,
    required this.canEdit,
    required this.onReRecordPressed,
    required this.onRenamePressed,
    required this.onDeletePressed,
  });

  final VoiceProfile profile;
  final bool canReRecord;
  final bool canEdit;
  final VoidCallback onReRecordPressed;
  final VoidCallback onRenamePressed;
  final VoidCallback onDeletePressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.account_circle_rounded,
            size: 26,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  strings.voiceProfileSampleDuration(
                    _formatShortDuration(
                      Duration(milliseconds: profile.durationMs),
                    ),
                  ),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: strings.reRecordVoiceProfile,
            onPressed: canReRecord ? onReRecordPressed : null,
            icon: const Icon(Icons.mic_rounded),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: strings.renameVoiceProfile,
            onPressed: canEdit ? onRenamePressed : null,
            icon: const Icon(Icons.edit_rounded),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: strings.deleteVoiceProfile,
            onPressed: canEdit ? onDeletePressed : null,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _RecordWorkspace extends StatelessWidget {
  const _RecordWorkspace({
    required this.status,
    required this.tone,
    required this.isRecording,
    required this.isBusy,
    required this.voiceProfiles,
    required this.isRecordingVoiceProfile,
    required this.isSavingVoiceProfile,
    required this.voiceProfileElapsed,
    required this.recordingVoiceProfileName,
    required this.speakerEmbeddingReady,
    required this.activeEngineName,
    required this.liveSegments,
    required this.recordings,
    required this.selectedRecordingTitle,
    required this.partial,
    required this.onRecordPressed,
    required this.onVoiceProfileAdd,
    required this.onVoiceProfileStopRecording,
    required this.onVoiceProfileReRecord,
    required this.onVoiceProfileRename,
    required this.onVoiceProfileDelete,
    required this.onRefresh,
    required this.onRecordingTap,
  });

  final String status;
  final _StatusTone tone;
  final bool isRecording;
  final bool isBusy;
  final List<VoiceProfile> voiceProfiles;
  final bool isRecordingVoiceProfile;
  final bool isSavingVoiceProfile;
  final Duration voiceProfileElapsed;
  final String? recordingVoiceProfileName;
  final bool speakerEmbeddingReady;
  final String? activeEngineName;
  final List<AsrSegment> liveSegments;
  final List<RecordingSession> recordings;
  final String? selectedRecordingTitle;
  final AsrPartial? partial;
  final VoidCallback onRecordPressed;
  final VoidCallback onVoiceProfileAdd;
  final VoidCallback onVoiceProfileStopRecording;
  final ValueChanged<VoiceProfile> onVoiceProfileReRecord;
  final ValueChanged<VoiceProfile> onVoiceProfileRename;
  final ValueChanged<VoiceProfile> onVoiceProfileDelete;
  final VoidCallback onRefresh;
  final ValueChanged<RecordingSession> onRecordingTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return _WorkspaceScaffold(
      title: strings.liveCapture,
      status: status,
      tone: tone,
      onRefresh: onRefresh,
      children: [
        _VoiceLibraryCard(
          profiles: voiceProfiles,
          isRecording: isRecordingVoiceProfile,
          isSaving: isSavingVoiceProfile,
          elapsed: voiceProfileElapsed,
          recordingName: recordingVoiceProfileName,
          speakerEmbeddingReady: speakerEmbeddingReady,
          canRecord: !isRecording && !isBusy,
          onAddPressed: onVoiceProfileAdd,
          onStopRecordingPressed: onVoiceProfileStopRecording,
          onReRecordPressed: onVoiceProfileReRecord,
          onRenamePressed: onVoiceProfileRename,
          onDeletePressed: onVoiceProfileDelete,
        ),
        const SizedBox(height: 14),
        _ActionCard(
          icon: Icons.graphic_eq,
          title: strings.record,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: isBusy ? null : onRecordPressed,
                  icon: Icon(isRecording ? Icons.stop : Icons.mic),
                  label: Text(
                    isRecording
                        ? strings.stopRecording
                        : strings.startRecording,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MetricStrip(
                items: [
                  _MetricItem(
                    icon: Icons.notes,
                    label: isRecording
                        ? strings.transcriptCount(liveSegments.length)
                        : strings.recordingListSummary(
                            recordings.length,
                            recordings.fold<int>(
                              0,
                              (total, recording) =>
                                  total + recording.segments.length,
                            ),
                          ),
                  ),
                  _MetricItem(
                    icon: Icons.memory,
                    label: isRecording
                        ? (activeEngineName ?? strings.noTranscriptShort)
                        : (selectedRecordingTitle ?? strings.noTranscriptShort),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (isRecording)
          _TranscriptPanel(segments: liveSegments, partial: partial)
        else
          _RecordingListPanel(
            recordings: recordings,
            onRecordingTap: onRecordingTap,
          ),
      ],
    );
  }
}

class _ImportWorkspace extends StatelessWidget {
  const _ImportWorkspace({
    required this.status,
    required this.tone,
    required this.isImportingAudio,
    required this.isInstallingModels,
    required this.isRecording,
    required this.isSummarizing,
    required this.hasRecordings,
    required this.onImportAudioPressed,
    required this.onRefresh,
  });

  final String status;
  final _StatusTone tone;
  final bool isImportingAudio;
  final bool isInstallingModels;
  final bool isRecording;
  final bool isSummarizing;
  final bool hasRecordings;
  final VoidCallback onImportAudioPressed;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isBusy =
        isImportingAudio || isInstallingModels || isRecording || isSummarizing;
    return _WorkspaceScaffold(
      title: strings.audioImport,
      status: status,
      tone: tone,
      onRefresh: onRefresh,
      children: [
        _ActionCard(
          icon: Icons.folder_open,
          title: strings.importAudio,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: isBusy ? null : onImportAudioPressed,
                  icon: isImportingAudio
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(strings.importAudioPrimary),
                ),
              ),
              const SizedBox(height: 12),
              _MetricStrip(
                items: [
                  _MetricItem(
                    icon: Icons.text_snippet,
                    label: hasRecordings
                        ? strings.importSavedHint
                        : strings.noTranscriptShort,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _EmptyPanel(
          text: hasRecordings
              ? strings.importGoToSummaryHint
              : strings.noRecordingsYet,
        ),
      ],
    );
  }
}

class _SummaryWorkspace extends StatelessWidget {
  const _SummaryWorkspace({
    required this.status,
    required this.tone,
    required this.isSummarizing,
    required this.isRecording,
    required this.isImportingAudio,
    required this.hasRecordings,
    required this.summaries,
    required this.summaryTemplate,
    required this.summaryMode,
    required this.onSummaryTemplateChanged,
    required this.onSummaryModeChanged,
    required this.onSummarizePressed,
    required this.onSummaryTap,
    required this.onRefresh,
  });

  final String status;
  final _StatusTone tone;
  final bool isSummarizing;
  final bool isRecording;
  final bool isImportingAudio;
  final bool hasRecordings;
  final List<MeetingSummaryRecord> summaries;
  final SummaryTemplate summaryTemplate;
  final SummaryMode summaryMode;
  final ValueChanged<SummaryTemplate> onSummaryTemplateChanged;
  final ValueChanged<SummaryMode> onSummaryModeChanged;
  final VoidCallback onSummarizePressed;
  final ValueChanged<MeetingSummaryRecord> onSummaryTap;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isBusy = isSummarizing || isRecording || isImportingAudio;
    return _WorkspaceScaffold(
      title: strings.summaryDesk,
      status: status,
      tone: tone,
      onRefresh: onRefresh,
      children: [
        _ActionCard(
          icon: Icons.tune,
          title: strings.summarySettings,
          child: _SummarySettings(
            isBusy: isBusy,
            hasRecordings: hasRecordings,
            isSummarizing: isSummarizing,
            summaryTemplate: summaryTemplate,
            summaryMode: summaryMode,
            onSummaryTemplateChanged: onSummaryTemplateChanged,
            onSummaryModeChanged: onSummaryModeChanged,
            onSummarizePressed: onSummarizePressed,
          ),
        ),
        const SizedBox(height: 14),
        _SummaryListPanel(summaries: summaries, onSummaryTap: onSummaryTap),
      ],
    );
  }
}

class _ModelWorkspace extends StatelessWidget {
  const _ModelWorkspace({
    required this.status,
    required this.tone,
    required this.modelCheck,
    required this.nativeBridgeReport,
    required this.isInstallingModels,
    required this.selectedPrimaryAsrModel,
    required this.canChangePrimaryAsrModel,
    required this.onPrimaryAsrModelChanged,
    required this.canInstallSpeakerModels,
    required this.onInstallSpeakerModels,
    required this.onRefresh,
  });

  final String status;
  final _StatusTone tone;
  final ModelCheckResult? modelCheck;
  final NativeBridgeReport? nativeBridgeReport;
  final bool isInstallingModels;
  final _PrimaryAsrModel selectedPrimaryAsrModel;
  final bool canChangePrimaryAsrModel;
  final ValueChanged<_PrimaryAsrModel> onPrimaryAsrModelChanged;
  final bool canInstallSpeakerModels;
  final VoidCallback onInstallSpeakerModels;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return _WorkspaceScaffold(
      title: strings.modelCenter,
      status: status,
      tone: tone,
      onRefresh: onRefresh,
      children: [
        _StatusPanel(
          status: status,
          tone: tone,
          modelCheck: modelCheck,
          nativeBridgeReport: nativeBridgeReport,
          isInstallingModels: isInstallingModels,
          selectedPrimaryAsrModel: selectedPrimaryAsrModel,
          canChangePrimaryAsrModel: canChangePrimaryAsrModel,
          onPrimaryAsrModelChanged: onPrimaryAsrModelChanged,
          canInstallSpeakerModels: canInstallSpeakerModels,
          onInstallSpeakerModels: onInstallSpeakerModels,
        ),
      ],
    );
  }
}

class _SummarySettings extends StatelessWidget {
  const _SummarySettings({
    required this.isBusy,
    required this.hasRecordings,
    required this.isSummarizing,
    required this.summaryTemplate,
    required this.summaryMode,
    required this.onSummaryTemplateChanged,
    required this.onSummaryModeChanged,
    required this.onSummarizePressed,
  });

  final bool isBusy;
  final bool hasRecordings;
  final bool isSummarizing;
  final SummaryTemplate summaryTemplate;
  final SummaryMode summaryMode;
  final ValueChanged<SummaryTemplate> onSummaryTemplateChanged;
  final ValueChanged<SummaryMode> onSummaryModeChanged;
  final VoidCallback onSummarizePressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<SummaryTemplate>(
          initialValue: summaryTemplate,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: strings.summaryTemplate,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
          items: [
            for (final template in SummaryTemplate.all)
              DropdownMenuItem(
                value: template,
                child: Text(
                  '${template.name} · ${template.description}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: isBusy
              ? null
              : (value) {
                  if (value != null) {
                    onSummaryTemplateChanged(value);
                  }
                },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<SummaryMode>(
            showSelectedIcon: false,
            selected: {summaryMode},
            segments: [
              ButtonSegment(
                value: SummaryMode.simple,
                label: Text(strings.summaryModeSimple),
                icon: const Icon(Icons.flash_on),
              ),
              ButtonSegment(
                value: SummaryMode.detailed,
                label: Text(strings.summaryModeDetailed),
                icon: const Icon(Icons.auto_awesome),
              ),
            ],
            onSelectionChanged: isBusy
                ? null
                : (values) {
                    if (values.isNotEmpty) {
                      onSummaryModeChanged(values.first);
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: hasRecordings && !isBusy ? onSummarizePressed : null,
            icon: isSummarizing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.summarize),
            label: Text(strings.summarize),
          ),
        ),
      ],
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.items});

  final List<_MetricItem> items;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetricItem {
  const _MetricItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF222633),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: textTheme.bodySmall?.copyWith(
              color: const Color(0xFF8A90A0),
            ),
          ),
      ],
    );
  }
}

class _RecordingListPanel extends StatelessWidget {
  const _RecordingListPanel({
    required this.recordings,
    required this.onRecordingTap,
  });

  final List<RecordingSession> recordings;
  final ValueChanged<RecordingSession> onRecordingTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelTitle(
          title: strings.meetingHistory,
          trailing: strings.recordingListSummary(
            recordings.length,
            recordings.fold<int>(
              0,
              (total, recording) => total + recording.segments.length,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (recordings.isEmpty)
          _EmptyPanel(text: strings.noRecordingsYet)
        else
          for (final recording in recordings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecordingListTile(
                recording: recording,
                onTap: () => onRecordingTap(recording),
              ),
            ),
      ],
    );
  }
}

class _RecordingListTile extends StatelessWidget {
  const _RecordingListTile({required this.recording, required this.onTap});

  final RecordingSession recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final preview = recording.previewText.trim();
    final subtitle = preview.isEmpty
        ? AppStrings.of(context).noTranscriptShort
        : (preview.length > 48 ? '${preview.substring(0, 48)}...' : preview);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFCBD6EE).withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EDFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.meeting_room_outlined, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording.title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.of(
                          context,
                        ).transcriptCount(recording.segments.length),
                        style: textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({required this.segments, required this.partial});

  final List<AsrSegment> segments;
  final AsrPartial? partial;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelTitle(
          title: strings.transcriptTitle,
          trailing: segments.isEmpty
              ? null
              : strings.transcriptCount(segments.length),
        ),
        const SizedBox(height: 10),
        if (segments.isEmpty && partial == null)
          _EmptyPanel(text: strings.noSpeechSegments)
        else ...[
          if (partial != null) _PartialTranscriptCard(partial: partial!),
          for (final segment in segments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFCBD6EE).withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${segment.index}.'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(segment.text),
                            const SizedBox(height: 4),
                            Text(
                              segment.engineName,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _PartialTranscriptCard extends StatelessWidget {
  const _PartialTranscriptCard({required this.partial});

  final AsrPartial partial;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final strings = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEFF5FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(partial.text),
                    const SizedBox(height: 4),
                    Text(
                      '${strings.partialTranscriptLabel} - ${partial.engineName}',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryListPanel extends StatelessWidget {
  const _SummaryListPanel({
    required this.summaries,
    required this.onSummaryTap,
  });

  final List<MeetingSummaryRecord> summaries;
  final ValueChanged<MeetingSummaryRecord> onSummaryTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelTitle(
          title: strings.summaryHistory,
          trailing: strings.summaryCount(summaries.length),
        ),
        const SizedBox(height: 10),
        if (summaries.isEmpty)
          _EmptyPanel(text: strings.noSummaryYet)
        else
          for (final summary in summaries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SummaryListTile(
                record: summary,
                onTap: () => onSummaryTap(summary),
              ),
            ),
      ],
    );
  }
}

class _SummaryListTile extends StatelessWidget {
  const _SummaryListTile({required this.record, required this.onTap});

  final MeetingSummaryRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    final template = record.summaryTemplate;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFCBD6EE).withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.summarize_outlined, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.summaryBasedOn(record.recordingTitle),
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${template.name} · ${record.summaryMode == SummaryMode.simple ? strings.summaryModeSimple : strings.summaryModeDetailed}',
                        style: textTheme.labelSmall,
                      ),
                      if (record.previewText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          record.previewText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCBD6EE).withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8A90A0)),
          ),
        ),
      ),
    );
  }
}

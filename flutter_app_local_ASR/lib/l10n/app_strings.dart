import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.locale);

  static const supportedLocales = <Locale>[Locale('en'), Locale('zh')];

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  final Locale locale;

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  bool get isZh => locale.languageCode == 'zh';

  String get appTitle => isZh ? '本地会议 ASR' : 'Local Meeting ASR';
  String get recordTab => isZh ? '录音' : 'Record';
  String get importTab => isZh ? '导入' : 'Import';
  String get summaryTab => isZh ? '总结' : 'Summary';
  String get modelsTab => isZh ? '模型' : 'Models';
  String get refresh => isZh ? '刷新' : 'Refresh';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get save => isZh ? '保存' : 'Save';
  String get checkingLocalModels =>
      isZh ? '正在检查本地模型...' : 'Checking local models...';
  String get primaryAsrReady => isZh
      ? '主 ASR 已就绪：Sherpa-ONNX SenseVoice'
      : 'Primary ASR ready: Sherpa-ONNX SenseVoice';
  String get primaryAsrReadyMoonshine => isZh
      ? '主 ASR 已就绪：Moonshine Tiny Streaming'
      : 'Primary ASR ready: Moonshine Tiny Streaming';
  String get primaryAsrMissing => isZh
      ? '主 ASR 模型缺失，将继续使用后备链路'
      : 'Primary ASR model is missing; fallback chain will continue';
  String get primaryAsrModel => isZh ? '主 ASR 模型' : 'Primary ASR model';
  String get moonshineModelChoice => 'Moonshine';
  String get sherpaModelChoice => 'Sherpa';
  String selectedPrimaryAsrMissing(String modelName) {
    return isZh
        ? '所选 ASR 未就绪：$modelName'
        : 'Selected ASR is not ready: $modelName';
  }

  String get primaryAsrChangeBlocked => isZh
      ? '录音或导入进行中，暂不能切换 ASR 模型'
      : 'ASR model cannot be changed while recording or importing';
  String get stoppingRecording => isZh ? '正在停止录音...' : 'Stopping recording...';
  String get bundledModelsInstalled =>
      isZh ? '本地模型已安装' : 'Local models installed';
  String bundledModelsMissing(int count) {
    return isZh
        ? '安装包内缺少 $count 个模型文件'
        : '$count bundled model files are missing';
  }

  String installingBundledModel(String label, String progress) {
    return isZh ? '正在安装 $label（$progress）' : 'Installing $label ($progress)';
  }

  String installModelsFailed(Object error) {
    return isZh ? '模型安装失败：$error' : 'Model install failed: $error';
  }

  String recordingWith(String? engineName) {
    final engine = engineName ?? (isZh ? '后备 ASR' : 'fallback ASR');
    return isZh ? '正在使用 $engine 录音' : 'Recording with $engine';
  }

  String get noTranscriptToSummarize =>
      isZh ? '暂无转写文本可总结' : 'No transcript to summarize';
  String get summarizingFastSummary =>
      isZh ? '正在极速生成会议总结' : 'Generating fast summary';
  String get summarizingDetailedSummary =>
      isZh ? '正在用本地模型生成详细总结' : 'Generating detailed local summary';
  String summaryReadyVia(String engineName) {
    return isZh ? '会议总结已完成：$engineName' : 'Summary ready via $engineName';
  }

  String errorMessage(Object error) {
    return isZh ? '发生错误：$error' : 'Error: $error';
  }

  String get sherpaSenseVoice => 'Sherpa SenseVoice';
  String get sherpaSpeakerDiarization =>
      isZh ? 'Sherpa 人声分离' : 'Sherpa speaker diarization';
  String get sherpaSpeakerEmbedding =>
      isZh ? 'Sherpa 声纹 embedding' : 'Sherpa speaker embedding';
  String get addSpeakerModels => isZh ? '添加人声分离与声纹模型' : 'Add speaker models';
  String get installingSpeakerModels =>
      isZh ? '正在添加人声分离与声纹模型' : 'Adding speaker models';
  String get speakerModelsReady =>
      isZh ? '人声分离与声纹模型已就绪' : 'Speaker models are ready';
  String get speakerModelsMissing => isZh
      ? '人声分离与声纹模型仍缺失，请检查打包资源'
      : 'Speaker models are still missing; check bundled assets';
  String get moonshineTinyStreaming => 'Moonshine Tiny Streaming';
  String get whisperCpp => 'whisper.cpp';
  String get systemAsr => isZh ? '系统 ASR' : 'System ASR';
  String get llamaCppQwen => 'llama.cpp Qwen';
  String get rulesSummary => isZh ? '规则摘要' : 'Rules summary';
  String get ready => isZh ? '已就绪' : 'Ready';
  String missingFiles(int count) =>
      isZh ? '缺少 $count 个文件' : 'Missing $count files';
  String get modelFoundBridgePending =>
      isZh ? '模型已找到，正在检查原生引擎' : 'Model found, checking native engine';
  String get modelMissingBridgePending =>
      isZh ? '模型缺失，原生引擎未启用' : 'Model missing, native engine disabled';
  String get bridgeReady => isZh ? '桥接已接入' : 'Bridge ready';
  String get nativeRuntimeMissing =>
      isZh ? '模型已安装，原生引擎未启用' : 'Model installed, native engine disabled';
  String get moonshineNativeRuntimeMissing => isZh
      ? 'iOS 运行库未接入，当前回退 SenseVoice'
      : 'iOS runtime not linked; falling back to SenseVoice';
  String get fallbackReady => isZh ? '后备可用' : 'Fallback ready';
  String get modelPaths => isZh ? '模型路径' : 'Model paths';
  String get asrRoot => isZh ? 'ASR 根目录' : 'ASR root';
  String get missing => isZh ? '缺失' : 'Missing';
  String get whisper => 'Whisper';
  String get speakerDiarizationModel =>
      isZh ? '人声分离模型' : 'Speaker diarization model';
  String get speakerEmbeddingModel =>
      isZh ? '声纹 embedding 模型' : 'Speaker embedding model';
  String get qwenGguf => 'Qwen GGUF';

  String get stop => isZh ? '停止' : 'Stop';
  String get record => isZh ? '录音' : 'Record';
  String get importAudio => isZh ? '上传音频' : 'Upload audio';
  String get importAudioPrimary => isZh ? '选择音频' : 'Choose audio';
  String get summarize => isZh ? '生成总结' : 'Summarize';
  String get startRecording => isZh ? '开始录音' : 'Start recording';
  String get stopRecording => isZh ? '停止录音' : 'Stop recording';
  String get liveCapture => isZh ? '实时记录' : 'Live capture';
  String get audioImport => isZh ? '音频导入' : 'Audio import';
  String get summaryDesk => isZh ? '纪要工作台' : 'Summary desk';
  String get modelCenter => isZh ? '模型中心' : 'Model center';
  String transcriptCount(int count) {
    return isZh ? '$count 段转写' : '$count segments';
  }

  String get noTranscriptShort => isZh ? '暂无转写' : 'No transcript';
  String get summarySettings => isZh ? '总结设置' : 'Summary settings';
  String get pickingAudioFile =>
      isZh ? '请选择本地音频文件' : 'Choose a local audio file';
  String get audioImportCancelled =>
      isZh ? '已取消选择音频' : 'Audio import cancelled';
  String transcribingAudioFile(String name) {
    return isZh ? '正在转写 $name' : 'Transcribing $name';
  }

  String audioFileTranscribed(String name) {
    return isZh ? '$name 转写完成，正在生成总结' : '$name transcribed; generating summary';
  }

  String get audioFileNoSpeech => isZh
      ? '音频里没有识别到可总结的文本'
      : 'No speech text was recognized in the audio file';
  String get summaryTemplate => isZh ? '总结模板' : 'Summary template';
  String get summaryMode => isZh ? '总结模式' : 'Summary mode';
  String get summaryModeSimple => isZh ? '简单版' : 'Simple';
  String get summaryModeDetailed => isZh ? '详细版' : 'Detailed';
  String get transcriptTitle => isZh ? '转写文本' : 'Transcript';
  String get partialTranscriptLabel => isZh ? '正在识别' : 'Recognizing';
  String get noSpeechSegments => isZh ? '暂无语音转写' : 'No speech segments yet';
  String get meetingHistory => isZh ? '录音记录' : 'Recordings';
  String get noRecordingsYet =>
      isZh ? '暂无录音记录，点击上方开始录音' : 'No recordings yet. Tap above to start.';
  String meetingTitle(int index) => isZh ? '会议$index' : 'Meeting $index';
  String recordingSaved(String title) => isZh ? '$title 已保存' : '$title saved';
  String get recordingNotSavedEmpty => isZh
      ? '未识别到语音内容，本次录音未保存'
      : 'No speech was recognized, recording not saved';
  String recordingListSummary(int recordingCount, int segmentCount) {
    return isZh
        ? '$recordingCount 条录音 · 共 $segmentCount 段转写'
        : '$recordingCount recordings · $segmentCount segments';
  }

  String recordingTimeLabel(String startedAt, String endedAt) {
    return isZh ? '时间：$startedAt - $endedAt' : 'Time: $startedAt - $endedAt';
  }

  String get useForSummary => isZh ? '用于生成总结' : 'Use for summary';
  String get defaultSelfName => isZh ? '我' : 'Me';
  String defaultVoiceProfileName(int index) {
    return isZh ? '说话人$index' : 'Speaker $index';
  }

  String get myVoiceProfile => isZh ? '我的声纹' : 'My voice';
  String get voiceLibrary => isZh ? '声纹库' : 'Voice library';
  String get voiceProfileMissingHint => isZh
      ? '开始前录制 10-20 秒你的声音，之后会自动区分你和其他人'
      : 'Record 10-20 seconds of your voice before meetings to identify you automatically';
  String get voiceLibraryMissingHint => isZh
      ? '添加每个人 10-20 秒的声音样本，录音完成后会自动匹配说话人'
      : 'Add 10-20 second voice samples for each person to identify speakers after recording';
  String voiceLibrarySummary(int count) {
    return isZh ? '已保存 $count 个声纹档案' : '$count voice profiles saved';
  }

  String voiceProfileReady(String name, String duration) {
    return isZh
        ? '已保存：$name · 样本 $duration'
        : 'Saved: $name · sample $duration';
  }

  String get recordMyVoice => isZh ? '录制我的声纹' : 'Record my voice';
  String get reRecordMyVoice => isZh ? '重录' : 'Re-record';
  String get addVoiceProfile => isZh ? '添加声纹' : 'Add voice profile';
  String get reRecordVoiceProfile => isZh ? '重录声纹' : 'Re-record voice';
  String voiceProfileSampleDuration(String duration) {
    return isZh ? '样本 $duration' : 'Sample $duration';
  }

  String stopAndSaveVoiceProfile(String name, String elapsed) {
    return isZh ? '停止并保存 $name · $elapsed' : 'Stop and save $name · $elapsed';
  }

  String recordingVoiceProfile(String name) {
    return isZh
        ? '正在录制 $name 的声纹，请说话 10-20 秒'
        : 'Recording $name; speak for 10-20 seconds';
  }

  String savingVoiceProfile(String name) {
    return isZh ? '正在保存 $name 的声纹' : 'Saving $name voice profile';
  }

  String voiceProfileSaved(String name) {
    return isZh ? '声纹已保存：$name' : 'Voice profile saved: $name';
  }

  String get voiceProfileNoAudio =>
      isZh ? '没有录到声纹音频，请重录' : 'No voice audio was recorded; try again';
  String get voiceProfileTooShort => isZh
      ? '声纹样本太短，请至少录制 10 秒'
      : 'Voice sample is too short; record at least 10 seconds';
  String get voiceProfileEmbeddingEmpty =>
      isZh ? '声纹向量生成失败，请重录' : 'Voice embedding failed; try recording again';
  String get renameVoiceProfile => isZh ? '修改声纹名称' : 'Rename voice profile';
  String get voiceProfileName => isZh ? '声纹名称' : 'Voice profile name';
  String voiceProfileRenamed(String name) {
    return isZh ? '声纹名称已更新：$name' : 'Voice profile renamed: $name';
  }

  String get deleteVoiceProfile => isZh ? '删除声纹' : 'Delete voice profile';
  String voiceProfileDeleted(String name) {
    return isZh ? '声纹已删除：$name' : 'Voice profile deleted: $name';
  }

  String get analyzeSpeakers => isZh ? '分析说话人' : 'Analyze speakers';
  String get analyzingSpeakers => isZh ? '正在分析说话人' : 'Analyzing speakers';
  String get speakerAnalysis => isZh ? '说话人分析' : 'Speaker analysis';
  String speakerCount(int count) {
    return isZh ? '$count 位说话人' : '$count speakers';
  }

  String get missingOriginalAudioForSpeakerAnalysis => isZh
      ? '缺少原始音频，无法进行说话人分析'
      : 'Original audio is missing; speaker analysis is unavailable';
  String get speakerModelsUnavailableForAnalysis => isZh
      ? '请先在模型中心添加人声分离与声纹模型'
      : 'Add speaker diarization and embedding models from the model center first';
  String get noSpeakerTurns => isZh ? '暂无说话人时间线' : 'No speaker timeline yet';
  String speakerAnalysisFailed(String error) {
    return isZh ? '说话人分析失败：$error' : 'Speaker analysis failed: $error';
  }

  String otherSpeakerLabel(String speakerLabel) {
    return isZh ? '其他人（$speakerLabel）' : 'Other ($speakerLabel)';
  }

  String get selfSpeakerBadge => isZh ? '我' : 'Me';
  String get speakerMatchedBadge => isZh ? '已识别' : 'Identified';
  String get speakerAutoAnalysisSkippedNoVoiceProfiles => isZh
      ? '录音已保存；声纹库为空，已跳过自动说话人识别'
      : 'Recording saved; the voice library is empty, so speaker identification was skipped';
  String get speakerAutoAnalysisSkippedNoAudio => isZh
      ? '录音已保存；缺少原始音频，已跳过自动说话人识别'
      : 'Recording saved; original audio is missing, so speaker identification was skipped';
  String get speakerAutoAnalysisSkippedNoModels => isZh
      ? '录音已保存；人声分离或声纹模型未就绪，已跳过自动说话人识别'
      : 'Recording saved; speaker models are not ready, so speaker identification was skipped';
  String get speakerAutoAnalysisReady =>
      isZh ? '说话人识别已完成' : 'Speaker identification complete';
  String speakerAutoAnalysisFailed(Object error) {
    return isZh
        ? '自动说话人识别失败：$error'
        : 'Automatic speaker identification failed: $error';
  }

  String get selectedForSummary => isZh ? '已选为当前总结来源' : 'Selected for summary';
  String get pickMeetingForSummary =>
      isZh ? '选择要总结的会议' : 'Choose a meeting to summarize';
  String get summaryHistory => isZh ? '总结记录' : 'Summaries';
  String summaryCount(int count) => isZh ? '$count 条总结' : '$count summaries';
  String summarySaved(String title) => isZh ? '$title 已生成' : '$title generated';
  String summaryBasedOn(String recordingTitle) =>
      isZh ? '基于 $recordingTitle' : 'Based on $recordingTitle';
  String get importSavedHint =>
      isZh ? '导入后会保存为录音记录' : 'Imports are saved as recordings';
  String get importGoToSummaryHint => isZh
      ? '音频已导入为录音记录，请前往「总结」页选择会议生成总结'
      : 'Audio saved as a recording. Go to Summary to generate.';
  String get meetingSummaryTitle => isZh ? '会议总结' : 'Meeting Summary';
  String get noSummaryYet => isZh ? '暂无会议总结' : 'No summary yet';
  String engineLabel(String engineName) {
    return isZh ? '引擎：$engineName' : 'Engine: $engineName';
  }

  String runtimeStatus(String value) {
    if (!isZh) {
      return value;
    }
    if (value.startsWith('Trying ')) {
      return '正在尝试 ${value.substring('Trying '.length)}';
    }
    if (value.startsWith('Using ')) {
      return '正在使用 ${value.substring('Using '.length)}';
    }
    if (value.startsWith('Stopped ')) {
      return '已停止 ${value.substring('Stopped '.length)}';
    }
    final separator = value.indexOf(': ');
    if (separator > 0) {
      final engine = value.substring(0, separator);
      final message = value.substring(separator + 2);
      return '$engine：${runtimeStatus(message)}';
    }
    return switch (value) {
      'Stopped' => '已停止',
      'Audio stream stopped' => '音频流已停止',
      'Listening with SenseVoice' => '正在监听 SenseVoice',
      'SenseVoice initialized' => 'SenseVoice 已初始化',
      _ => value,
    };
  }

  String get keyPoints => isZh ? '关键结论' : 'Key Points';
  String get actionItems => isZh ? '待办事项' : 'Action Items';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppStrings.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppStrings> load(Locale locale) {
    final languageCode = locale.languageCode == 'zh' ? 'zh' : 'en';
    return SynchronousFuture<AppStrings>(AppStrings(Locale(languageCode)));
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

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
  String get fallbackReady => isZh ? '后备可用' : 'Fallback ready';
  String get modelPaths => isZh ? '模型路径' : 'Model paths';
  String get asrRoot => isZh ? 'ASR 根目录' : 'ASR root';
  String get missing => isZh ? '缺失' : 'Missing';
  String get whisper => 'Whisper';
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

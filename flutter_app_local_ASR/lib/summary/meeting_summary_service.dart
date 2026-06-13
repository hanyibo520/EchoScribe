abstract class MeetingSummaryService {
  String get name;
  Future<SummaryAvailability> checkAvailability();
  Future<MeetingSummary> summarize(
    String transcript, {
    required SummaryLanguage language,
    required SummaryTemplate summaryTemplate,
  });
}

enum SummaryLanguage { en, zh }

enum SummaryMode { simple, detailed }

class SummaryTemplate {
  const SummaryTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.assetPath,
  });

  final String id;
  final String name;
  final String description;
  final String assetPath;

  static const general = SummaryTemplate(
    id: 'general',
    name: '通用',
    description: '适用于所有会议场景',
    assetPath: 'assets/templates/meeting_summary_zh.md',
  );

  static const businessCooperation = SummaryTemplate(
    id: 'business_cooperation',
    name: '商务洽谈合作',
    description: '用于商务讨论',
    assetPath: 'assets/templates/meeting_summary_business_zh.md',
  );

  static const all = <SummaryTemplate>[general, businessCooperation];
}

class SummaryAvailability {
  const SummaryAvailability.available() : reason = null;
  const SummaryAvailability.unavailable(this.reason);

  final String? reason;

  bool get isAvailable => reason == null;
}

class MeetingSummary {
  const MeetingSummary({
    required this.overview,
    required this.keyPoints,
    required this.actionItems,
    required this.engineName,
    this.markdown,
  });

  final String overview;
  final List<String> keyPoints;
  final List<String> actionItems;
  final String engineName;
  final String? markdown;

  bool get hasMarkdown => markdown?.trim().isNotEmpty ?? false;
}

class FallbackMeetingSummaryService implements MeetingSummaryService {
  const FallbackMeetingSummaryService({
    required List<MeetingSummaryService> engines,
  }) : _engines = engines;

  final List<MeetingSummaryService> _engines;

  @override
  String get name => 'LLM 后备链路';

  @override
  Future<SummaryAvailability> checkAvailability() async {
    final reasons = <String>[];
    for (final engine in _engines) {
      final availability = await engine.checkAvailability();
      if (availability.isAvailable) {
        return const SummaryAvailability.available();
      }
      reasons.add('${engine.name}: ${availability.reason}');
    }

    return SummaryAvailability.unavailable(reasons.join('\n'));
  }

  @override
  Future<MeetingSummary> summarize(
    String transcript, {
    required SummaryLanguage language,
    required SummaryTemplate summaryTemplate,
  }) async {
    final errors = <String>[];
    for (final engine in _engines) {
      final availability = await engine.checkAvailability();
      if (!availability.isAvailable) {
        errors.add('${engine.name}: ${availability.reason}');
        continue;
      }

      try {
        return await engine.summarize(
          transcript,
          language: language,
          summaryTemplate: summaryTemplate,
        );
      } catch (error) {
        errors.add('${engine.name}: $error');
      }
    }

    throw StateError('没有可用的会议总结引擎。\n${errors.join('\n')}');
  }
}

class HeuristicMeetingSummaryService implements MeetingSummaryService {
  @override
  String get name => '极速模板摘要';

  @override
  Future<SummaryAvailability> checkAvailability() async {
    return const SummaryAvailability.available();
  }

  @override
  Future<MeetingSummary> summarize(
    String transcript, {
    required SummaryLanguage language,
    required SummaryTemplate summaryTemplate,
  }) async {
    final lines = transcript
        .split(RegExp(r'[\n。！？!?]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (language == SummaryLanguage.zh) {
      final markdown = summaryTemplate == SummaryTemplate.businessCooperation
          ? _businessMarkdown(lines)
          : _generalMarkdown(lines);
      return MeetingSummary(
        overview: markdown,
        keyPoints: const <String>[],
        actionItems: const <String>[],
        engineName: '极速模板摘要 · ${summaryTemplate.name}',
        markdown: markdown,
      );
    }

    final keyPoints = lines.take(5).toList();
    final actionItems = lines
        .where(
          (line) =>
              line.contains('需要') ||
              line.contains('负责') ||
              line.contains('跟进') ||
              line.contains('todo') ||
              line.contains('TODO'),
        )
        .take(5)
        .toList();

    return MeetingSummary(
      overview: _overview(lines.length, language),
      keyPoints: keyPoints.isEmpty ? [_emptyKeyPoint(language)] : keyPoints,
      actionItems: actionItems.isEmpty
          ? [_emptyActionItem(language)]
          : actionItems,
      engineName: name,
    );
  }

  String _overview(int lineCount, SummaryLanguage language) {
    if (lineCount == 0) {
      return language == SummaryLanguage.zh
          ? '暂无可总结的转写文本。'
          : 'No transcript available.';
    }

    return language == SummaryLanguage.zh
        ? '已在本地整理 $lineCount 段语音转写，并使用极速模板摘要生成会议纪要。'
        : 'Captured $lineCount speech segments locally and generated a fast template summary.';
  }

  String _emptyKeyPoint(SummaryLanguage language) {
    return language == SummaryLanguage.zh
        ? '暂未识别到明确的关键结论。'
        : 'No clear key points detected.';
  }

  String _emptyActionItem(SummaryLanguage language) {
    return language == SummaryLanguage.zh
        ? '暂未识别到明确的待办事项。'
        : 'No clear action items detected.';
  }

  String _generalMarkdown(List<String> lines) {
    final points = _takeOrPlaceholder(lines, 6);
    final actions = _actionLines(lines, 4);
    final quotes = _takeOrPlaceholder(lines, 5);

    return '''
## 一、会面背景（会议信息）
- **会议时间：**未提及
- **参会人员：**
  - **我方：**未提及
  - **对方：**未提及
- **会面目的 / 会议主题：**${_firstOrPlaceholder(lines)}

---

## 二、关键结论总结
${_numbered(points)}

---

## 三、核心议题逐条总结

### **议题1：会议讨论内容**
- **讨论事实与主张：**${_firstOrPlaceholder(lines)}
- **引用关键词：**未提及
- **结论：**${_safeAt(points, 0)}
- **分歧点：**无明显分歧

---

### **议题2：后续推进**
- **讨论事实与主张：**${_safeAt(points, 1)}
- **沟通细节：**${_safeAt(points, 2)}
- **论据与说明：**${_safeAt(points, 3)}
- **分歧点：**无明显分歧

---

### **议题3：风险与约束**
- **讨论事实与主张：**${_safeAt(points, 3)}
- **引用关键词：**未提及
- **论据与说明：**${_safeAt(points, 4)}
- **结论：**${_safeAt(points, 4)}

---

### **议题4：行动安排**
- **讨论事实与主张：**${_safeAt(points, 4)}
- **沟通细节：**${_safeAt(points, 5)}
- **风险点：**如转写中未明确负责人、时间节点或验收口径，需后续补充确认。
- **结论：**${_safeAt(points, 5)}

---

## 四、待定问题 / 风险点
1. **待确认事项** ${_safeAt(points, 4)}
2. **信息缺口** 会议时间、人员角色或责任边界如未在转写中明确，需补充确认。
3. **执行风险** 如转写中未出现明确时间节点，后续推进节奏需确认。
4. **责任边界** 如转写中未说明负责人，需会后补充分工。
5. **指标口径** 如涉及数据、效果或交付标准，需进一步明确衡量方式。

---

## 五、下一步行动

| 负责人 | 任务 | 时间节点 |
|--------|------|----------|
${_actionRows(actions)}

---

## 六、附录：高价值原话 / 片段
${_quoted(quotes)}
'''
        .trim();
  }

  String _businessMarkdown(List<String> lines) {
    final points = _takeOrPlaceholder(lines, 6);
    final actions = _actionLines(lines, 4);

    return '''
## 一、会议信息
- **会议时间：** 未提及
- **参会人员：**
  - **我方：** 未提及
  - **对方：** 未提及
- **会议主题：** ${_firstOrPlaceholder(lines)}

---

## 二、对方公司概况
未提及

---

## 三、合作诉求与意向

### ● 对方诉求
a. ${_safeAt(points, 0)}
b. ${_safeAt(points, 1)}
c. 未提及

### ● 我方诉求
a. ${_safeAt(points, 2)}
b. ${_safeAt(points, 3)}
c. 未提及

---

## 四、核心议题摘要
${_numbered(points)}

---

## 五、风险与限制
- **数据合规风险：** 未提及
- **运营落地风险：** 未提及
- **技术对接风险：** 未提及
- **时效性风险：** 未提及

---

## 六、下一步行动计划

| 负责人 | 任务 | 时间节点 |
|--------|------|----------|
${_actionRows(actions)}

---

## 七、会议结论
${_safeAt(points, 0)}
'''
        .trim();
  }

  List<String> _takeOrPlaceholder(List<String> lines, int count) {
    final values = lines.take(count).toList();
    while (values.length < count) {
      values.add('未提及');
    }
    return values;
  }

  List<String> _actionLines(List<String> lines, int count) {
    final values = lines
        .where(
          (line) =>
              line.contains('需要') ||
              line.contains('负责') ||
              line.contains('跟进') ||
              line.contains('确认') ||
              line.contains('输出') ||
              line.contains('完成'),
        )
        .take(count)
        .toList();
    while (values.length < count) {
      values.add('未提及');
    }
    return values;
  }

  String _firstOrPlaceholder(List<String> lines) {
    return lines.isEmpty ? '未提及' : lines.first;
  }

  String _safeAt(List<String> values, int index) {
    return index < values.length && values[index].trim().isNotEmpty
        ? values[index]
        : '未提及';
  }

  String _numbered(List<String> values) {
    return [
      for (var i = 0; i < values.length; i += 1) '${i + 1}. ${values[i]}',
    ].join('\n');
  }

  String _quoted(List<String> values) {
    return [
      for (var i = 0; i < values.length; i += 1)
        '${i + 1}. **发言方：**“${values[i]}”',
    ].join('\n');
  }

  String _actionRows(List<String> values) {
    return [
      for (var i = 0; i < values.length; i += 1)
        '| ${String.fromCharCode(65 + i)} | ${values[i]} | 未提及 |',
    ].join('\n');
  }
}

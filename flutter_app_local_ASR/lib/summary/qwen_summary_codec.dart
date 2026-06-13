import 'dart:convert';

import 'package:flutter/services.dart';

import 'meeting_summary_service.dart';

Future<String> buildQwenSummaryPrompt(
  String transcript,
  SummaryLanguage language,
  SummaryTemplate summaryTemplate,
) async {
  final trimmed = transcript.trim();
  if (language == SummaryLanguage.zh) {
    final template = await _loadZhTemplate(summaryTemplate);
    return '''
你是一个离线会议纪要助手。请只根据下面的转写文本生成会议纪要。
必须严格按照【会议纪要模板】输出 Markdown。
不要输出 JSON，不要解释，不要输出代码块。
保留模板的标题顺序、分隔线、加粗字段和表格结构。
如果转写文本没有提供某个字段，请写“未提及”，不要编造事实、人物、时间、数字或结论。
参会人员无法判断时，可以使用转写中的 speaker 名称。
当前模板名称：${summaryTemplate.name}
当前模板描述：${summaryTemplate.description}

【会议纪要模板】
$template

转写文本：
$trimmed
''';
  }

  return '''
You are an offline meeting summarizer. Summarize only the transcript below.
Return JSON only. Do not use Markdown or explanations.
JSON format:
{"overview":"one sentence overview","keyPoints":["point 1","point 2","point 3"],"actionItems":["action 1","action 2"]}

Transcript:
$trimmed
''';
}

MeetingSummary parseQwenSummary(
  String raw,
  SummaryLanguage language, {
  required String engineName,
}) {
  if (language == SummaryLanguage.zh) {
    final markdown = _cleanMarkdown(raw);
    return MeetingSummary(
      overview: markdown.isEmpty ? _emptyOverview(language) : markdown,
      keyPoints: const <String>[],
      actionItems: const <String>[],
      engineName: engineName,
      markdown: markdown,
    );
  }

  final jsonText = _extractJsonObject(raw);
  if (jsonText != null) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, Object?>) {
        return MeetingSummary(
          overview: decoded['overview']?.toString().trim() ?? '',
          keyPoints: _stringList(decoded['keyPoints']),
          actionItems: _stringList(decoded['actionItems']),
          engineName: engineName,
        );
      }
    } on FormatException {
      // Fall through to the plain-text fallback below.
    }
  }

  final text = raw.trim();
  return MeetingSummary(
    overview: text.isEmpty ? _emptyOverview(language) : text,
    keyPoints: const <String>[],
    actionItems: const <String>[],
    engineName: engineName,
  );
}

Future<String> _loadZhTemplate(SummaryTemplate summaryTemplate) async {
  try {
    return await rootBundle.loadString(summaryTemplate.assetPath);
  } on Object {
    return _fallbackZhTemplate;
  }
}

String _cleanMarkdown(String raw) {
  var text = raw.trim();
  text = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```(?:markdown)?\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
  }
  return text.trim();
}

String? _extractJsonObject(String value) {
  final start = value.indexOf('{');
  final end = value.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  return value.substring(start, end + 1);
}

String _emptyOverview(SummaryLanguage language) {
  return language == SummaryLanguage.zh
      ? '本地 Qwen 未返回有效会议纪要。'
      : 'Local Qwen did not return a valid meeting summary.';
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

const String _fallbackZhTemplate = '''
## 一、会面背景（会议信息）
- **会议时间：**{会议时间}
- **参会人员：**
  - **我方：**{我方参会人员}
  - **对方：**{对方参会人员}
- **会面目的 / 会议主题：**{会议主题}

---

## 二、关键结论总结
1. {关键结论1}
2. {关键结论2}
3. {关键结论3}

---

## 三、核心议题逐条总结
### **议题1：{议题名称}**
- **讨论事实与主张：**{讨论事实与主张}
- **引用关键词：**{转写中出现的关键词或原话}
- **结论：**{议题结论}
- **分歧点：**{分歧点；如无则写“无明显分歧”}

---

## 四、待定问题 / 风险点
1. **{风险点}**{说明}

---

## 五、下一步行动
| 负责人 | 任务 | 时间节点 |
|--------|------|----------|
| {负责人} | {任务} | {时间节点} |

---

## 六、附录：高价值原话 / 片段
1. **{发言方}：**“{原话或高价值片段}”
''';

import 'dart:convert';

import '../summary/meeting_summary_service.dart';

class MeetingSummaryRecord {
  const MeetingSummaryRecord({
    required this.id,
    required this.recordingId,
    required this.recordingTitle,
    required this.title,
    required this.summaryTemplateId,
    required this.summaryMode,
    required this.engineName,
    required this.overview,
    required this.keyPoints,
    required this.actionItems,
    required this.createdAt,
    this.markdown,
  });

  final int id;
  final int recordingId;
  final String recordingTitle;
  final String title;
  final String summaryTemplateId;
  final SummaryMode summaryMode;
  final String engineName;
  final String overview;
  final List<String> keyPoints;
  final List<String> actionItems;
  final String? markdown;
  final DateTime createdAt;

  SummaryTemplate get summaryTemplate {
    return SummaryTemplate.all.firstWhere(
      (template) => template.id == summaryTemplateId,
      orElse: () => SummaryTemplate.general,
    );
  }

  MeetingSummary toMeetingSummary() {
    return MeetingSummary(
      overview: overview,
      keyPoints: keyPoints,
      actionItems: actionItems,
      engineName: engineName,
      markdown: markdown,
    );
  }

  String get previewText {
    if (markdown?.trim().isNotEmpty == true) {
      final text = markdown!.replaceAll(RegExp(r'[#>*`\-\[\]]'), ' ').trim();
      return text.length > 64 ? '${text.substring(0, 64)}...' : text;
    }
    final overview = this.overview.trim();
    return overview.length > 64 ? '${overview.substring(0, 64)}...' : overview;
  }

  factory MeetingSummaryRecord.fromMap(Map<String, Object?> map) {
    return MeetingSummaryRecord(
      id: map['id']! as int,
      recordingId: map['recording_id']! as int,
      recordingTitle: map['recording_title']! as String,
      title: map['title']! as String,
      summaryTemplateId: map['summary_template_id']! as String,
      summaryMode: map['summary_mode'] == 'detailed'
          ? SummaryMode.detailed
          : SummaryMode.simple,
      engineName: map['engine_name']! as String,
      overview: map['overview']! as String,
      keyPoints: _decodeStringList(map['key_points'] as String?),
      actionItems: _decodeStringList(map['action_items'] as String?),
      markdown: map['markdown'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
      ),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'recording_id': recordingId,
      'recording_title': recordingTitle,
      'title': title,
      'summary_template_id': summaryTemplateId,
      'summary_mode': summaryMode == SummaryMode.detailed ? 'detailed' : 'simple',
      'engine_name': engineName,
      'overview': overview,
      'key_points': jsonEncode(keyPoints),
      'action_items': jsonEncode(actionItems),
      'markdown': markdown,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded.map((item) => '$item').toList();
  }
}

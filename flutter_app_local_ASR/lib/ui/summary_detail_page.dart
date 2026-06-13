import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../l10n/app_strings.dart';
import '../storage/meeting_summary_record.dart';
import '../summary/meeting_summary_service.dart';

class SummaryDetailPage extends StatelessWidget {
  const SummaryDetailPage({
    super.key,
    required this.record,
  });

  final MeetingSummaryRecord record;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final summary = record.toMeetingSummary();
    final template = record.summaryTemplate;

    return Scaffold(
      appBar: AppBar(
        title: Text(record.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          DecoratedBox(
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
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.summaryBasedOn(record.recordingTitle),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${template.name} · ${record.summaryMode == SummaryMode.simple ? strings.summaryModeSimple : strings.summaryModeDetailed}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.engineLabel(record.engineName),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFCBD6EE).withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _SummaryContent(summary: summary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.summary});

  final MeetingSummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (summary.hasMarkdown) {
      return _MarkdownSummary(markdown: summary.markdown!.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary.overview),
        const SizedBox(height: 12),
        Text(
          strings.keyPoints,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final item in summary.keyPoints) Text('- $item'),
        const SizedBox(height: 12),
        Text(
          strings.actionItems,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final item in summary.actionItems) Text('- $item'),
      ],
    );
  }
}

class _MarkdownSummary extends StatelessWidget {
  const _MarkdownSummary({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const textColor = Color(0xFF252A36);
    const mutedColor = Color(0xFF5F6676);

    return SelectionArea(
      child: MarkdownBody(
        data: markdown,
        selectable: false,
        styleSheet: MarkdownStyleSheet(
          h1: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: textColor,
            height: 1.25,
          ),
          h2: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF3150FF),
            height: 1.28,
          ),
          h3: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: textColor,
            height: 1.3,
          ),
          p: textTheme.bodyMedium?.copyWith(color: mutedColor, height: 1.65),
          strong: const TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
          ),
          listBullet: textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF465DFF),
            fontWeight: FontWeight.w900,
          ),
          blockquote: textTheme.bodyMedium?.copyWith(
            color: mutedColor,
            height: 1.6,
          ),
          code: textTheme.bodySmall?.copyWith(
            color: const Color(0xFF3150FF),
            backgroundColor: const Color(0xFFF1F4FF),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

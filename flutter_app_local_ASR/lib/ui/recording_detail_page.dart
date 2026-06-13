import 'package:flutter/material.dart';

import '../asr/asr_engine.dart';
import '../l10n/app_strings.dart';
import '../storage/recording_session.dart';

class RecordingDetailPage extends StatelessWidget {
  const RecordingDetailPage({
    super.key,
    required this.session,
    this.onUseForSummary,
  });

  final RecordingSession session;
  final VoidCallback? onUseForSummary;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final segments = session.asrSegments;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _InfoCard(session: session),
          const SizedBox(height: 14),
          if (onUseForSummary != null) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: onUseForSummary,
                icon: const Icon(Icons.summarize_outlined),
                label: Text(strings.useForSummary),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            strings.transcriptTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (segments.isEmpty)
            _EmptyPanel(text: strings.noSpeechSegments)
          else
            for (final segment in segments.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SegmentCard(segment: segment),
              ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.session});

  final RecordingSession session;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;

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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.recordingTimeLabel(
                _formatDateTime(session.createdAt),
                _formatDateTime(session.endedAt),
              ),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              strings.transcriptCount(session.segments.length),
              style: textTheme.labelLarge,
            ),
            if (session.engineName != null && session.engineName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  strings.engineLabel(session.engineName!),
                  style: textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({required this.segment});

  final AsrSegment segment;

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
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

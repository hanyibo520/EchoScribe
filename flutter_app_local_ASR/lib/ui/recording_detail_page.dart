import 'package:flutter/material.dart';

import '../asr/asr_engine.dart';
import '../l10n/app_strings.dart';
import '../storage/recording_database.dart';
import '../storage/recording_session.dart';

class RecordingDetailPage extends StatefulWidget {
  const RecordingDetailPage({
    super.key,
    required this.session,
    this.onUseForSummary,
    this.onAnalyzeSpeakers,
    this.speakerModelsReady = false,
  });

  final RecordingSession session;
  final VoidCallback? onUseForSummary;
  final Future<void> Function(RecordingSession session)? onAnalyzeSpeakers;
  final bool speakerModelsReady;

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  List<SpeakerTurn> _speakerTurns = const <SpeakerTurn>[];
  bool _isLoadingSpeakerTurns = true;
  bool _isAnalyzingSpeakers = false;
  String? _speakerError;

  @override
  void initState() {
    super.initState();
    _loadSpeakerTurns();
  }

  @override
  void didUpdateWidget(covariant RecordingDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _loadSpeakerTurns();
    }
  }

  Future<void> _loadSpeakerTurns() async {
    setState(() {
      _isLoadingSpeakerTurns = true;
      _speakerError = null;
    });
    try {
      final turns = await RecordingDatabase.instance.listSpeakerTurns(
        widget.session.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _speakerTurns = turns;
        _isLoadingSpeakerTurns = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSpeakerTurns = false;
        _speakerError = error.toString();
      });
    }
  }

  Future<void> _analyzeSpeakers() async {
    final onAnalyzeSpeakers = widget.onAnalyzeSpeakers;
    if (onAnalyzeSpeakers == null ||
        _isAnalyzingSpeakers ||
        !widget.session.hasAudio) {
      return;
    }

    setState(() {
      _isAnalyzingSpeakers = true;
      _speakerError = null;
    });
    try {
      await onAnalyzeSpeakers(widget.session);
      await _loadSpeakerTurns();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAnalyzingSpeakers = false;
        _speakerError = error.toString();
      });
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _isAnalyzingSpeakers = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final segments = widget.session.asrSegments;

    return Scaffold(
      appBar: AppBar(title: Text(widget.session.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _InfoCard(session: widget.session),
          const SizedBox(height: 14),
          if (widget.onUseForSummary != null) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: widget.onUseForSummary,
                icon: const Icon(Icons.summarize_outlined),
                label: Text(strings.useForSummary),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _SpeakerAnalysisAction(
            session: widget.session,
            hasAnalyzer: widget.onAnalyzeSpeakers != null,
            speakerModelsReady: widget.speakerModelsReady,
            isAnalyzing: _isAnalyzingSpeakers,
            onPressed: _analyzeSpeakers,
            errorText: _speakerError,
          ),
          const SizedBox(height: 14),
          _SpeakerTimelinePanel(
            turns: _speakerTurns,
            isLoading: _isLoadingSpeakerTurns,
          ),
          const SizedBox(height: 18),
          Text(
            strings.transcriptTitle,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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

class _SpeakerAnalysisAction extends StatelessWidget {
  const _SpeakerAnalysisAction({
    required this.session,
    required this.hasAnalyzer,
    required this.speakerModelsReady,
    required this.isAnalyzing,
    required this.onPressed,
    required this.errorText,
  });

  final RecordingSession session;
  final bool hasAnalyzer;
  final bool speakerModelsReady;
  final bool isAnalyzing;
  final VoidCallback onPressed;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final canAnalyze =
        hasAnalyzer && session.hasAudio && speakerModelsReady && !isAnalyzing;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: canAnalyze ? onPressed : null,
            icon: isAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.record_voice_over_rounded),
            label: Text(
              isAnalyzing ? strings.analyzingSpeakers : strings.analyzeSpeakers,
            ),
          ),
        ),
        if (!session.hasAudio) ...[
          const SizedBox(height: 8),
          Text(
            strings.missingOriginalAudioForSpeakerAnalysis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ] else if (!speakerModelsReady) ...[
          const SizedBox(height: 8),
          Text(
            strings.speakerModelsUnavailableForAnalysis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (errorText != null && errorText!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            strings.speakerAnalysisFailed(errorText!),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _SpeakerTimelinePanel extends StatelessWidget {
  const _SpeakerTimelinePanel({required this.turns, required this.isLoading});

  final List<SpeakerTurn> turns;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    final speakerCount = turns.map((turn) => turn.speakerLabel).toSet().length;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.speakerAnalysis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (turns.isNotEmpty)
                  Text(
                    strings.speakerCount(speakerCount),
                    style: textTheme.labelMedium,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (!isLoading && turns.isEmpty)
              Text(
                strings.noSpeakerTurns,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final turn in turns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SpeakerTurnRow(turn: turn),
                ),
          ],
        ),
      ),
    );
  }
}

class _SpeakerTurnRow extends StatelessWidget {
  const _SpeakerTurnRow({required this.turn});

  final SpeakerTurn turn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.graphic_eq_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${turn.speakerLabel} · '
            '${_formatDuration(turn.startMs)} - ${_formatDuration(turn.endMs)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
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

String _formatDuration(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final twoDigitMinutes = minutes.toString().padLeft(2, '0');
  final twoDigitSeconds = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$twoDigitMinutes:$twoDigitSeconds';
  }
  return '$twoDigitMinutes:$twoDigitSeconds';
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

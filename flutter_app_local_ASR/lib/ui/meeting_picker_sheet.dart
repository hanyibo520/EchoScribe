import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../storage/recording_session.dart';

class MeetingPickerSheet extends StatelessWidget {
  const MeetingPickerSheet({
    super.key,
    required this.recordings,
  });

  final List<RecordingSession> recordings;

  static Future<RecordingSession?> show({
    required BuildContext context,
    required List<RecordingSession> recordings,
  }) {
    return showModalBottomSheet<RecordingSession>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => MeetingPickerSheet(recordings: recordings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.pickMeetingForSummary,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            if (recordings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    strings.noRecordingsYet,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: recordings.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final recording = recordings[index];
                    final preview = recording.previewText.trim();
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(recording),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(Icons.meeting_room_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      recording.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        preview.length > 56
                                            ? '${preview.substring(0, 56)}...'
                                            : preview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      strings.transcriptCount(
                                        recording.segments.length,
                                      ),
                                      style: Theme.of(context).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../asr/asr_engine.dart';
import '../summary/meeting_summary_service.dart';
import 'meeting_summary_record.dart';
import 'recording_session.dart';

class RecordingDatabase {
  RecordingDatabase._();

  static final RecordingDatabase instance = RecordingDatabase._();

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final opened = await _open();
    _database = opened;
    return opened;
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    final dbPath = p.join(basePath, 'local_meeting_asr.db');
    return openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await _createRecordingTables(db);
        await _createSummaryTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSummaryTable(db);
        }
      },
      onOpen: (db) async {
        await _createSummaryTable(db);
      },
    );
  }

  Future<void> _createRecordingTables(Database db) async {
        await db.execute('''
          CREATE TABLE recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            engine_name TEXT,
            source_type TEXT NOT NULL DEFAULT 'live'
          )
        ''');
        await db.execute('''
          CREATE TABLE recording_segments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recording_id INTEGER NOT NULL,
            segment_index INTEGER NOT NULL,
            text TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            engine_name TEXT NOT NULL,
            FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_recording_segments_recording_id '
          'ON recording_segments(recording_id)',
        );
  }

  Future<void> _createSummaryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meeting_summaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recording_id INTEGER NOT NULL,
        recording_title TEXT NOT NULL,
        title TEXT NOT NULL,
        summary_template_id TEXT NOT NULL,
        summary_mode TEXT NOT NULL,
        engine_name TEXT NOT NULL,
        overview TEXT NOT NULL,
        key_points TEXT NOT NULL,
        action_items TEXT NOT NULL,
        markdown TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_meeting_summaries_created_at '
      'ON meeting_summaries(created_at DESC)',
    );
  }

  Future<int> recordingCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS count FROM recordings');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<String> nextDefaultTitle({required bool isZh}) async {
    final db = await database;
    final result = await db.rawQuery('SELECT MAX(id) AS max_id FROM recordings');
    final maxId = Sqflite.firstIntValue(result) ?? 0;
    final next = maxId + 1;
    return isZh ? '会议$next' : 'Meeting $next';
  }

  Future<List<RecordingSession>> listRecordings() async {
    final db = await database;
    final rows = await db.query(
      'recordings',
      orderBy: 'created_at DESC',
    );
    final sessions = <RecordingSession>[];
    for (final row in rows) {
      final segments = await db.query(
        'recording_segments',
        where: 'recording_id = ?',
        whereArgs: [row['id']],
        orderBy: 'segment_index ASC',
      );
      sessions.add(
        RecordingSession.fromMaps(
          recording: row,
          segmentMaps: segments,
        ),
      );
    }
    return sessions;
  }

  Future<RecordingSession?> getRecording(int id) async {
    final db = await database;
    final rows = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final segments = await db.query(
      'recording_segments',
      where: 'recording_id = ?',
      whereArgs: [id],
      orderBy: 'segment_index ASC',
    );
    return RecordingSession.fromMaps(
      recording: rows.first,
      segmentMaps: segments,
    );
  }

  Future<RecordingSession> saveRecording({
    required String title,
    required List<AsrSegment> segments,
    String? engineName,
    RecordingSourceType sourceType = RecordingSourceType.live,
    DateTime? createdAt,
    DateTime? endedAt,
  }) async {
    if (segments.isEmpty) {
      throw ArgumentError('Cannot save an empty recording');
    }

    final db = await database;
    final startedAt = createdAt ??
        segments
            .map((segment) => segment.createdAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
    final finishedAt = endedAt ?? DateTime.now();

    return db.transaction((txn) async {
      final recordingId = await txn.insert('recordings', {
        'title': title,
        'created_at': startedAt.millisecondsSinceEpoch,
        'ended_at': finishedAt.millisecondsSinceEpoch,
        'engine_name': engineName,
        'source_type': sourceType == RecordingSourceType.import
            ? 'import'
            : 'live',
      });

      final storedSegments = <RecordingSegment>[];
      for (final segment in segments) {
        final stored = RecordingSegment.fromAsr(segment);
        await txn.insert('recording_segments', stored.toMap(recordingId));
        storedSegments.add(stored);
      }

      return RecordingSession(
        id: recordingId,
        title: title,
        createdAt: startedAt,
        endedAt: finishedAt,
        engineName: engineName,
        sourceType: sourceType,
        segments: storedSegments,
      );
    });
  }

  Future<String> nextSummaryTitle({required bool isZh}) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(id) AS max_id FROM meeting_summaries',
    );
    final maxId = Sqflite.firstIntValue(result) ?? 0;
    final next = maxId + 1;
    return isZh ? '总结$next' : 'Summary $next';
  }

  Future<List<MeetingSummaryRecord>> listSummaries() async {
    final db = await database;
    final rows = await db.query(
      'meeting_summaries',
      orderBy: 'created_at DESC',
    );
    return rows.map(MeetingSummaryRecord.fromMap).toList();
  }

  Future<MeetingSummaryRecord?> getSummary(int id) async {
    final db = await database;
    final rows = await db.query(
      'meeting_summaries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return MeetingSummaryRecord.fromMap(rows.first);
  }

  Future<MeetingSummaryRecord> saveSummary({
    required RecordingSession recording,
    required MeetingSummary summary,
    required SummaryTemplate summaryTemplate,
    required SummaryMode summaryMode,
    String? title,
    required bool isZh,
  }) async {
    final db = await database;
    final resolvedTitle =
        title ?? await nextSummaryTitle(isZh: isZh);
    final id = await db.insert('meeting_summaries', {
      'recording_id': recording.id,
      'recording_title': recording.title,
      'title': resolvedTitle,
      'summary_template_id': summaryTemplate.id,
      'summary_mode': summaryMode == SummaryMode.detailed ? 'detailed' : 'simple',
      'engine_name': summary.engineName,
      'overview': summary.overview.trim().isEmpty ? ' ' : summary.overview,
      'key_points': jsonEncode(summary.keyPoints),
      'action_items': jsonEncode(summary.actionItems),
      'markdown': summary.markdown,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final saved = await getSummary(id);
    if (saved == null) {
      throw StateError('Failed to load saved summary $id');
    }
    return saved;
  }
}

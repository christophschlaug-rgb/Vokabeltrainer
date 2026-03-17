// lib/services/database_service.dart
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/vocabulary.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vokabeltrainer.db');
    return await openDatabase(
      path,
      version: 7,
      onCreate: (db, version) => _createTables(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          await db.execute('DROP TABLE IF EXISTS vocabularies');
          await _createUnitTables(db);
          await _createVocabTable(db);
          await db.execute('''CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
          await db.execute('''CREATE TABLE IF NOT EXISTS daily_stats (
              date TEXT PRIMARY KEY,
              cards_reviewed INTEGER DEFAULT 0,
              cards_correct  INTEGER DEFAULT 0,
              cards_wrong    INTEGER DEFAULT 0)''');
        }
      },
    );
  }

  static Future<void> _createVocabTable(Database db) async {
    await db.execute('''
      CREATE TABLE vocabularies (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        word_en          TEXT NOT NULL UNIQUE,
        word_de          TEXT NOT NULL,
        example          TEXT,
        level            TEXT,
        sort_order       INTEGER DEFAULT 9999,
        success_streak   INTEGER DEFAULT 0,
        total_correct    INTEGER DEFAULT 0,
        total_wrong      INTEGER DEFAULT 0,
        next_review_date TEXT NOT NULL,
        last_result      TEXT,
        last_review_date TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_review ON vocabularies(next_review_date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_en ON vocabularies(word_en)');
  }

  static Future<void> _createTables(Database db) async {
    await _createVocabTable(db);
    await db.execute(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.execute('''CREATE TABLE daily_stats (
        date TEXT PRIMARY KEY,
        cards_reviewed INTEGER DEFAULT 0,
        cards_correct  INTEGER DEFAULT 0,
        cards_wrong    INTEGER DEFAULT 0)''');
    await _createUnitTables(db);
  }

  static Future<void> _createUnitTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scan_units (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scan_unit_words (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        unit_id INTEGER NOT NULL,
        word    TEXT NOT NULL,
        FOREIGN KEY (unit_id) REFERENCES scan_units(id) ON DELETE CASCADE
      )
    ''');
  }

  // ─── Vokabeln abrufen ────────────────────────────────────────

  static Future<List<Vocabulary>> getAllVocabulariesSorted() async {
    final db = await database;
    final maps = await db.query('vocabularies',
        orderBy: 'sort_order ASC, word_en ASC');
    return maps.map(Vocabulary.fromMap).toList();
  }

  static Future<List<Vocabulary>> searchVocabularies(String query) async {
    final db = await database;
    final q = '%${query.trim().toLowerCase()}%';
    final maps = await db.rawQuery('''
        SELECT * FROM vocabularies
        WHERE LOWER(word_en) LIKE ? OR LOWER(word_de) LIKE ?
        ORDER BY sort_order ASC, word_en ASC
        LIMIT 1000''', [q, q]);
    return maps.map(Vocabulary.fromMap).toList();
  }


  /// Paginierte Abfrage fuer Dictionary Screen
  static Future<List<Vocabulary>> getVocabulariesPaged({
    required int offset,
    required int limit,
    required String query,
  }) async {
    final db = await database;
    if (query.trim().isEmpty) {
      // Blättern ohne Suche: paginiert laden (jeweils 100)
      final maps = await db.query('vocabularies',
          orderBy: 'sort_order ASC, word_en ASC',
          limit: limit, offset: offset);
      return maps.map(Vocabulary.fromMap).toList();
    } else {
      // Suche: ALLE Treffer aus allen 15000 Einträgen zurückgeben (kein LIMIT)
      final q = '%\${query.trim().toLowerCase()}%';
      final maps = await db.rawQuery(
          'SELECT * FROM vocabularies'
          ' WHERE LOWER(word_en) LIKE ? OR LOWER(word_de) LIKE ?'
          ' ORDER BY sort_order ASC, word_en ASC',
          [q, q]);
      return maps.map(Vocabulary.fromMap).toList();
    }
  }

  static Future<List<Vocabulary>> getDueVocabularies({int limit = 50}) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final maps = await db.rawQuery('''
        SELECT * FROM vocabularies
        WHERE SUBSTR(next_review_date, 1, 10) <= ?
        ORDER BY next_review_date ASC, sort_order ASC
        LIMIT 500''', [today]);

    if (maps.isEmpty) return [];
    final all = maps.map(Vocabulary.fromMap).toList();
    if (all.length <= limit) {
      all.shuffle();
      return all;
    }

    // Mix aus verschiedenen Positionen im fälligen Pool
    // Teile den Pool in Drittel (unabhängig von sort_order-Werten)
    final third = all.length ~/ 3;
    final easy   = all.sublist(0, third).toList()..shuffle();
    final medium = all.sublist(third, third * 2).toList()..shuffle();
    final hard   = all.sublist(third * 2).toList()..shuffle();

    final easyCount  = (limit * 0.40).round();
    final medCount   = (limit * 0.40).round();
    final hardCount  = limit - easyCount - medCount;

    final result = <Vocabulary>[
      ...easy.take(easyCount),
      ...medium.take(medCount),
      ...hard.take(hardCount),
    ];

    // Auffüllen falls eine Gruppe zu klein
    if (result.length < limit) {
      result.addAll(
        all.where((v) => !result.any((r) => r.id == v.id))
           .take(limit - result.length),
      );
    }

    result.shuffle();
    return result.take(limit).toList();
  }

  // ─── Vokabeln speichern ──────────────────────────────────────

  static Future<void> replaceAllVocabularies(List<Vocabulary> vocabs) async {
    final db = await database;
    final rng = Random();

    final existing = await db.query('vocabularies',
        columns: ['word_en', 'success_streak', 'total_correct', 'total_wrong',
                  'next_review_date', 'last_result', 'last_review_date'],
        where: 'total_correct > 0 OR total_wrong > 0');

    final progress = <String, Map<String, dynamic>>{};
    for (final row in existing) {
      progress[row['word_en'] as String] = row;
    }

    await db.delete('vocabularies');

    final today = DateTime.now();
    const chunkSize = 500;

    for (int i = 0; i < vocabs.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, vocabs.length);
      final chunk = vocabs.sublist(i, end);
      final batch = db.batch();

      for (int j = 0; j < chunk.length; j++) {
        final v = chunk[j];
        final sortOrder = i + j;
        final map = v.toMap();
        map['sort_order'] = sortOrder;

        final saved = progress[v.wordEn];
        if (saved != null) {
          map['success_streak']   = saved['success_streak'];
          map['total_correct']    = saved['total_correct'];
          map['total_wrong']      = saved['total_wrong'];
          map['next_review_date'] = saved['next_review_date'];
          map['last_result']      = saved['last_result'];
          map['last_review_date'] = saved['last_review_date'];
        } else {
          if (sortOrder < 1000) {
            map['next_review_date'] = today.toIso8601String();
          } else {
            final daysAhead =
                (sortOrder / 30).round().clamp(1, 365) + rng.nextInt(3);
            map['next_review_date'] =
                today.add(Duration(days: daysAhead)).toIso8601String();
          }
        }

        batch.insert('vocabularies', map,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    }
  }

  static Future<void> updateVocabulary(Vocabulary vocab) async {
    final db = await database;
    await db.update('vocabularies', vocab.toMap(),
        where: 'id = ?', whereArgs: [vocab.id]);
  }


  static Future<void> insertVocabulary(Vocabulary vocab) async {
    final db = await database;
    final map = vocab.toMap();
    map['sort_order'] = 99000; // Neue Scan-Wörter ans Ende
    map['next_review_date'] = DateTime.now().toIso8601String();
    await db.insert('vocabularies', map,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ─── Vokabeln löschen ────────────────────────────────────────

  static Future<void> deleteVocabulary(int id) async {
    final db = await database;
    await db.delete('vocabularies', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteVocabularies(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = ids.map((_) => '?').join(',');
    await db.delete('vocabularies',
        where: 'id IN ($placeholders)', whereArgs: ids);
  }

  // ─── Zähler ──────────────────────────────────────────────────

  static Future<int> getVocabularyCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM vocabularies');
    return r.first['c'] as int;
  }

  static Future<int> getDueCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM vocabularies "
        "WHERE SUBSTR(next_review_date,1,10) <= ?", [today]);
    return r.first['c'] as int;
  }

  // ─── Einstellungen ───────────────────────────────────────────

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getDailyLimit() async =>
      int.tryParse(await getSetting('daily_limit') ?? '50') ?? 50;

  static Future<void> setDailyLimit(int v) => setSetting('daily_limit', '$v');

  // ─── Tagesstatistiken ────────────────────────────────────────

  static Future<void> recordDailyReview({required bool wasCorrect}) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await db.execute('''
      INSERT INTO daily_stats (date, cards_reviewed, cards_correct, cards_wrong)
      VALUES (?, 1, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        cards_reviewed = cards_reviewed + 1,
        cards_correct  = cards_correct  + ?,
        cards_wrong    = cards_wrong    + ?
    ''', [today,
          wasCorrect ? 1 : 0, wasCorrect ? 0 : 1,
          wasCorrect ? 1 : 0, wasCorrect ? 0 : 1]);
  }

  static Future<int> getLearningStreak() async {
    final db = await database;
    final rows = await db.query('daily_stats',
        where: 'cards_reviewed > 0',
        orderBy: 'date DESC', limit: 365);
    if (rows.isEmpty) return 0;
    int streak = 0;
    DateTime check = DateTime.now();
    for (final row in rows) {
      final d = DateTime.parse(row['date'] as String);
      if (check.difference(d).inDays <= 1) { streak++; check = d; }
      else break;
    }
    return streak;
  }

  static Future<Map<String, int>> getTodayStats() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.query('daily_stats',
        where: 'date = ?', whereArgs: [today]);
    if (r.isEmpty) return {'reviewed': 0, 'correct': 0, 'wrong': 0};
    return {
      'reviewed': r.first['cards_reviewed'] as int,
      'correct':  r.first['cards_correct']  as int,
      'wrong':    r.first['cards_wrong']     as int,
    };
  }
  // ─── Scan-Units (Wortlisten aus Buchseiten) ─────────────────

  static Future<int> createUnit(String name) async {
    final db = await database;
    return await db.insert('scan_units', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getAllUnits() async {
    final db = await database;
    final units = await db.query('scan_units', orderBy: 'created_at DESC');
    final result = <Map<String, dynamic>>[];
    for (final u in units) {
      final count = await db.rawQuery(
          'SELECT COUNT(*) as c FROM scan_unit_words WHERE unit_id = ?',
          [u['id']]);
      result.add({...u, 'word_count': count.first['c'] as int});
    }
    return result;
  }

  static Future<List<String>> getUnitWords(int unitId) async {
    final db = await database;
    final rows = await db.query('scan_unit_words',
        where: 'unit_id = ?', whereArgs: [unitId], orderBy: 'word ASC');
    return rows.map((r) => r['word'] as String).toList();
  }

  static Future<void> addWordsToUnit(int unitId, List<String> words) async {
    final db = await database;
    final batch = db.batch();
    for (final w in words) {
      batch.insert('scan_unit_words', {'unit_id': unitId, 'word': w},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> deleteUnit(int unitId) async {
    final db = await database;
    await db.delete('scan_units', where: 'id = ?', whereArgs: [unitId]);
    await db.delete('scan_unit_words',
        where: 'unit_id = ?', whereArgs: [unitId]);
  }

  static Future<void> removeWordFromUnit(int unitId, String word) async {
    final db = await database;
    await db.delete('scan_unit_words',
        where: 'unit_id = ? AND word = ?', whereArgs: [unitId, word]);
  }

  static Future<int> getUnitCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM scan_units');
    return r.first['c'] as int;
  }

  static Future<void> renameUnit(int unitId, String newName) async {
    final db = await database;
    await db.update('scan_units', {'name': newName},
        where: 'id = ?', whereArgs: [unitId]);
  }

}

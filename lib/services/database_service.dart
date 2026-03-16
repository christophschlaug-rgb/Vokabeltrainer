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
      version: 6,
      onCreate: (db, version) => _createTables(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 6) {
          await db.execute('DROP TABLE IF EXISTS vocabularies');
          await _createVocabTable(db);
          // settings und daily_stats erhalten
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS daily_stats (
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
    await db.execute('''
      CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE daily_stats (
        date TEXT PRIMARY KEY,
        cards_reviewed INTEGER DEFAULT 0,
        cards_correct  INTEGER DEFAULT 0,
        cards_wrong    INTEGER DEFAULT 0)''');
  }

  // ─── Vokabeln ────────────────────────────────────────────────

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
        LIMIT 200''', [q, q]);
    return maps.map(Vocabulary.fromMap).toList();
  }

  /// Fällige Vokabeln für heute — gemischter Level-Mix
  static Future<List<Vocabulary>> getDueVocabularies({int limit = 50}) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Alle fälligen Vokabeln laden (max 500 für Performance)
    final maps = await db.rawQuery('''
        SELECT * FROM vocabularies
        WHERE SUBSTR(next_review_date, 1, 10) <= ?
        ORDER BY next_review_date ASC, sort_order ASC
        LIMIT 500''', [today]);

    if (maps.isEmpty) return [];

    final all = maps.map(Vocabulary.fromMap).toList();

    // Wenn weniger als Limit → alle zurückgeben
    if (all.length <= limit) {
      all.shuffle();
      return all;
    }

    // Mix aus verschiedenen Schwierigkeitsstufen:
    // ~40% einfache (sort_order klein), ~40% mittel, ~20% schwer
    // Das sorgt dafür dass man nicht nur die ersten 50 immer wiederholt
    final easy   = all.where((v) => v.sortOrder < 1000).toList();
    final medium = all.where((v) => v.sortOrder >= 1000 && v.sortOrder < 5000).toList();
    final hard   = all.where((v) => v.sortOrder >= 5000).toList();

    easy.shuffle();
    medium.shuffle();
    hard.shuffle();

    final easyCount  = (limit * 0.40).round();
    final medCount   = (limit * 0.40).round();
    final hardCount  = limit - easyCount - medCount;

    final result = <Vocabulary>[];
    result.addAll(easy.take(easyCount));
    result.addAll(medium.take(medCount));
    result.addAll(hard.take(hardCount));

    // Auffüllen falls eine Gruppe zu klein ist
    if (result.length < limit) {
      final remaining = all
          .where((v) => !result.any((r) => r.id == v.id))
          .take(limit - result.length);
      result.addAll(remaining);
    }

    result.shuffle();
    return result.take(limit).toList();
  }

  /// Vokabeln ersetzen — mit gestaffelten Review-Dates für neue Wörter.
  /// Lernfortschritt bereits bekannter Wörter bleibt erhalten.
  static Future<void> replaceAllVocabularies(List<Vocabulary> vocabs) async {
    final db = await database;
    final rng = Random();

    // Lernfortschritt bestehender Vokabeln sichern
    final existing = await db.query('vocabularies',
        columns: [
          'word_en', 'success_streak', 'total_correct', 'total_wrong',
          'next_review_date', 'last_result', 'last_review_date'
        ],
        where: 'total_correct > 0 OR total_wrong > 0');

    final progress = <String, Map<String, dynamic>>{};
    for (final row in existing) {
      progress[row['word_en'] as String] = row;
    }

    await db.delete('vocabularies');

    final today = DateTime.now();

    // In Blöcken einfügen
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
          // Bereits gelernt: Fortschritt wiederherstellen
          map['success_streak']   = saved['success_streak'];
          map['total_correct']    = saved['total_correct'];
          map['total_wrong']      = saved['total_wrong'];
          map['next_review_date'] = saved['next_review_date'];
          map['last_result']      = saved['last_result'];
          map['last_review_date'] = saved['last_review_date'];
        } else {
          // Neue Vokabel: Review-Datum staffeln
          // Erste 300: sofort fällig (Grundvokabular)
          // Ab 300: zufällig über 365 Tage verteilt → täglich neue Wörter
          if (sortOrder < 300) {
            map['next_review_date'] = today.toIso8601String();
          } else {
            // Je höher der sort_order, desto weiter in der Zukunft
            // Damit nicht alles auf einmal fällig wird
            final daysAhead = (sortOrder / 30).round().clamp(1, 365)
                + rng.nextInt(3); // ±3 Tage Zufall damit es nicht zu gleichmäßig ist
            final reviewDate = today.add(Duration(days: daysAhead));
            map['next_review_date'] = reviewDate.toIso8601String();
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

  static Future<int> getVocabularyCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM vocabularies');
    return r.first['c'] as int;
  }

  static Future<int> getDueCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
        "SELECT COUNT(*) as c FROM vocabularies WHERE SUBSTR(next_review_date,1,10) <= ?",
        [today]);
    return r.first['c'] as int;
  }

  // ─── Einstellungen ──────────────────────────────────────────

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

  // ─── Tagesstatistiken ───────────────────────────────────────

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
    ''', [today, wasCorrect?1:0, wasCorrect?0:1, wasCorrect?1:0, wasCorrect?0:1]);
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
    final r = await db.query('daily_stats', where: 'date = ?', whereArgs: [today]);
    if (r.isEmpty) return {'reviewed': 0, 'correct': 0, 'wrong': 0};
    return {
      'reviewed': r.first['cards_reviewed'] as int,
      'correct':  r.first['cards_correct']  as int,
      'wrong':    r.first['cards_wrong']     as int,
    };
  }
}

  // ─── Vokabel löschen ────────────────────────────────────────

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

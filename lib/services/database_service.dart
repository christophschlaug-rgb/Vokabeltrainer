// lib/services/database_service.dart
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
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Neue Spalten für Schwierigkeitsgrad-Sortierung
          await db.execute('ALTER TABLE vocabularies ADD COLUMN sort_order INTEGER DEFAULT 9999');
          await db.execute('UPDATE vocabularies SET sort_order = id');
        }
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE vocabularies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_en TEXT NOT NULL,
        word_de TEXT NOT NULL,
        example TEXT,
        level TEXT,
        sort_order INTEGER DEFAULT 9999,
        success_streak INTEGER DEFAULT 0,
        total_correct INTEGER DEFAULT 0,
        total_wrong INTEGER DEFAULT 0,
        next_review_date TEXT NOT NULL,
        last_result TEXT,
        last_review_date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_stats (
        date TEXT PRIMARY KEY,
        cards_reviewed INTEGER DEFAULT 0,
        cards_correct INTEGER DEFAULT 0,
        cards_wrong INTEGER DEFAULT 0
      )
    ''');
  }

  // ─── Vokabeln ────────────────────────────────────────────────

  static Future<List<Vocabulary>> getAllVocabularies() async {
    final db = await database;
    final maps = await db.query('vocabularies');
    return maps.map((m) => Vocabulary.fromMap(m)).toList();
  }

  /// Alle Vokabeln für die Wörterbuch-Ansicht, sortiert nach sort_order
  static Future<List<Vocabulary>> getAllVocabulariesSorted() async {
    final db = await database;
    final maps = await db.query(
      'vocabularies',
      orderBy: 'sort_order ASC, word_en ASC',
    );
    return maps.map((m) => Vocabulary.fromMap(m)).toList();
  }

  /// Suche in Vokabeln (EN oder DE)
  static Future<List<Vocabulary>> searchVocabularies(String query) async {
    final db = await database;
    final q = '%${query.trim().toLowerCase()}%';
    final maps = await db.rawQuery(
      '''SELECT * FROM vocabularies
         WHERE LOWER(word_en) LIKE ? OR LOWER(word_de) LIKE ?
         ORDER BY sort_order ASC, word_en ASC
         LIMIT 200''',
      [q, q],
    );
    return maps.map((m) => Vocabulary.fromMap(m)).toList();
  }

  /// Heute fällige Vokabeln laden — KEINE Duplikate, nach sort_order sortiert
  static Future<List<Vocabulary>> getDueVocabularies({int limit = 50}) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Nur Vokabeln die heute oder früher fällig sind, geordnet nach Schwierigkeit
    // next_review_date als Datum (erste 10 Zeichen) vergleichen um Duplikate zu vermeiden
    final maps = await db.rawQuery(
      '''SELECT * FROM vocabularies
         WHERE SUBSTR(next_review_date, 1, 10) <= ?
         ORDER BY sort_order ASC, next_review_date ASC
         LIMIT ?''',
      [today, limit],
    );

    final list = maps.map((m) => Vocabulary.fromMap(m)).toList();
    list.shuffle(); // Reihenfolge mischen aber Limit respektieren
    return list;
  }

  static Future<void> insertVocabularies(List<Vocabulary> vocabs) async {
    final db = await database;
    final batch = db.batch();

    for (int i = 0; i < vocabs.length; i++) {
      final v = vocabs[i];
      // sort_order = Position in der Liste = Häufigkeit/Schwierigkeit
      final map = v.toMap();
      map['sort_order'] = i;
      batch.insert(
        'vocabularies',
        map,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> updateVocabulary(Vocabulary vocab) async {
    final db = await database;
    await db.update(
      'vocabularies',
      vocab.toMap(),
      where: 'id = ?',
      whereArgs: [vocab.id],
    );
  }

  static Future<int> getVocabularyCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM vocabularies');
    return result.first['count'] as int;
  }

  static Future<int> getDueCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM vocabularies WHERE SUBSTR(next_review_date,1,10) <= ?",
      [today],
    );
    return result.first['count'] as int;
  }

  // ─── Einstellungen ─────────────────────────────────────────

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (result.isEmpty) return null;
    return result.first['value'] as String;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<int> getDailyLimit() async {
    final val = await getSetting('daily_limit');
    return int.tryParse(val ?? '50') ?? 50;
  }

  static Future<void> setDailyLimit(int limit) async {
    await setSetting('daily_limit', limit.toString());
  }

  // ─── Tagesstatistiken ──────────────────────────────────────

  static Future<void> recordDailyReview({required bool wasCorrect}) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await db.execute('''
      INSERT INTO daily_stats (date, cards_reviewed, cards_correct, cards_wrong)
      VALUES (?, 1, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        cards_reviewed = cards_reviewed + 1,
        cards_correct = cards_correct + ?,
        cards_wrong = cards_wrong + ?
    ''', [today, wasCorrect ? 1 : 0, wasCorrect ? 0 : 1,
          wasCorrect ? 1 : 0, wasCorrect ? 0 : 1]);
  }

  static Future<int> getLearningStreak() async {
    final db = await database;
    final results = await db.query(
      'daily_stats',
      where: 'cards_reviewed > 0',
      orderBy: 'date DESC',
      limit: 365,
    );

    if (results.isEmpty) return 0;

    int streak = 0;
    DateTime checkDate = DateTime.now();

    for (final row in results) {
      final date = DateTime.parse(row['date'] as String);
      final diff = checkDate.difference(date).inDays;
      if (diff <= 1) {
        streak++;
        checkDate = date;
      } else {
        break;
      }
    }
    return streak;
  }

  static Future<Map<String, int>> getTodayStats() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.query('daily_stats', where: 'date = ?', whereArgs: [today]);

    if (result.isEmpty) return {'reviewed': 0, 'correct': 0, 'wrong': 0};

    return {
      'reviewed': result.first['cards_reviewed'] as int,
      'correct': result.first['cards_correct'] as int,
      'wrong': result.first['cards_wrong'] as int,
    };
  }
}

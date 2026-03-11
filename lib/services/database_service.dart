// lib/services/database_service.dart
// Lokale SQLite-Datenbank für Vokabeln und Lernstatus

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/vocabulary.dart';

class DatabaseService {
  static Database? _db;

  // Singleton: nur eine Datenbankinstanz
  static Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vokabeltrainer.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Tabelle für Vokabeln erstellen
        await db.execute('''
          CREATE TABLE vocabularies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word_en TEXT NOT NULL,
            word_de TEXT NOT NULL,
            example TEXT,
            level TEXT,
            success_streak INTEGER DEFAULT 0,
            total_correct INTEGER DEFAULT 0,
            total_wrong INTEGER DEFAULT 0,
            next_review_date TEXT NOT NULL,
            last_result TEXT,
            last_review_date TEXT
          )
        ''');

        // Tabelle für App-Einstellungen (z.B. letzter Lerntag)
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        // Tabelle für Lernstatistiken pro Tag
        await db.execute('''
          CREATE TABLE daily_stats (
            date TEXT PRIMARY KEY,
            cards_reviewed INTEGER DEFAULT 0,
            cards_correct INTEGER DEFAULT 0,
            cards_wrong INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  // ─── Vokabeln ────────────────────────────────────────────────

  /// Alle Vokabeln laden
  static Future<List<Vocabulary>> getAllVocabularies() async {
    final db = await database;
    final maps = await db.query('vocabularies');
    return maps.map((m) => Vocabulary.fromMap(m)).toList();
  }

  /// Heute fällige Vokabeln laden (bis zu [limit] Stück)
  static Future<List<Vocabulary>> getDueVocabularies({int limit = 100}) async {
    final db = await database;
    final today = DateTime.now().toIso8601String();

    // Alle Vokabeln deren nextReviewDate heute oder früher ist
    final maps = await db.query(
      'vocabularies',
      where: 'next_review_date <= ?',
      whereArgs: [today],
      orderBy: 'next_review_date ASC',
      limit: limit,
    );

    final list = maps.map((m) => Vocabulary.fromMap(m)).toList();
    // Reihenfolge mischen
    list.shuffle();
    return list;
  }

  /// Vokabeln massenhaft einfügen (beim ersten Laden)
  static Future<void> insertVocabularies(List<Vocabulary> vocabs) async {
    final db = await database;
    final batch = db.batch();

    for (final vocab in vocabs) {
      // Nur einfügen wenn noch nicht vorhanden (nach englischem Wort prüfen)
      batch.insert(
        'vocabularies',
        vocab.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Vokabel-Lernstatus aktualisieren
  static Future<void> updateVocabulary(Vocabulary vocab) async {
    final db = await database;
    await db.update(
      'vocabularies',
      vocab.toMap(),
      where: 'id = ?',
      whereArgs: [vocab.id],
    );
  }

  /// Anzahl aller gespeicherten Vokabeln
  static Future<int> getVocabularyCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM vocabularies');
    return result.first['count'] as int;
  }

  /// Anzahl heute fälliger Vokabeln
  static Future<int> getDueCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM vocabularies WHERE next_review_date <= ?',
      [today],
    );
    return result.first['count'] as int;
  }

  // ─── Einstellungen ─────────────────────────────────────────

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
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

  // ─── Tagesstatistiken ──────────────────────────────────────

  static Future<void> recordDailyReview({
    required bool wasCorrect,
  }) async {
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

  /// Lerntage in Folge berechnen (Streak)
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
      final dateStr = row['date'] as String;
      final date = DateTime.parse(dateStr);
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

  /// Statistiken für heute
  static Future<Map<String, int>> getTodayStats() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.query(
      'daily_stats',
      where: 'date = ?',
      whereArgs: [today],
    );

    if (result.isEmpty) {
      return {'reviewed': 0, 'correct': 0, 'wrong': 0};
    }

    return {
      'reviewed': result.first['cards_reviewed'] as int,
      'correct': result.first['cards_correct'] as int,
      'wrong': result.first['cards_wrong'] as int,
    };
  }
}

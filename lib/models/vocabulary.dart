// lib/models/vocabulary.dart
// Datenmodell für eine Vokabel mit allen SRS-Feldern

class Vocabulary {
  final int? id;
  final String wordEn;        // Englisches Wort
  final String wordDe;        // Deutsche Übersetzung(en), durch | getrennt
  final String? example;      // Beispielsatz (optional)
  final String? level;        // z.B. "C1"

  // --- SRS-Felder (Spaced Repetition System) ---
  final int successStreak;    // Wie viele Male in Folge richtig beantwortet
  final int totalCorrect;     // Gesamt richtige Antworten
  final int totalWrong;       // Gesamt falsche Antworten
  final String nextReviewDate; // ISO-Datum: wann nächste Wiederholung fällig
  final String? lastResult;   // "correct" oder "wrong"
  final String? lastReviewDate; // Wann zuletzt abgefragt

  Vocabulary({
    this.id,
    required this.wordEn,
    required this.wordDe,
    this.example,
    this.level,
    this.successStreak = 0,
    this.totalCorrect = 0,
    this.totalWrong = 0,
    String? nextReviewDate,
    this.lastResult,
    this.lastReviewDate,
  }) : nextReviewDate = nextReviewDate ?? DateTime.now().toIso8601String();

  // Alle möglichen deutschen Übersetzungen als Liste zurückgeben
  List<String> get germanTranslations =>
      wordDe.split('|').map((s) => s.trim().toLowerCase()).toList();

  // Alle möglichen englischen Varianten als Liste zurückgeben
  List<String> get englishVariants =>
      wordEn.split('|').map((s) => s.trim().toLowerCase()).toList();

  // Aus SQLite-Map laden
  factory Vocabulary.fromMap(Map<String, dynamic> map) {
    return Vocabulary(
      id: map['id'] as int?,
      wordEn: map['word_en'] as String,
      wordDe: map['word_de'] as String,
      example: map['example'] as String?,
      level: map['level'] as String?,
      successStreak: (map['success_streak'] as int?) ?? 0,
      totalCorrect: (map['total_correct'] as int?) ?? 0,
      totalWrong: (map['total_wrong'] as int?) ?? 0,
      nextReviewDate: map['next_review_date'] as String? ?? DateTime.now().toIso8601String(),
      lastResult: map['last_result'] as String?,
      lastReviewDate: map['last_review_date'] as String?,
    );
  }

  // Für SQLite-Speicherung in Map umwandeln
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'word_en': wordEn,
      'word_de': wordDe,
      'example': example,
      'level': level,
      'success_streak': successStreak,
      'total_correct': totalCorrect,
      'total_wrong': totalWrong,
      'next_review_date': nextReviewDate,
      'last_result': lastResult,
      'last_review_date': lastReviewDate,
    };
  }

  // Kopie mit geänderten Feldern erstellen
  Vocabulary copyWith({
    int? successStreak,
    int? totalCorrect,
    int? totalWrong,
    String? nextReviewDate,
    String? lastResult,
    String? lastReviewDate,
  }) {
    return Vocabulary(
      id: id,
      wordEn: wordEn,
      wordDe: wordDe,
      example: example,
      level: level,
      successStreak: successStreak ?? this.successStreak,
      totalCorrect: totalCorrect ?? this.totalCorrect,
      totalWrong: totalWrong ?? this.totalWrong,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      lastResult: lastResult ?? this.lastResult,
      lastReviewDate: lastReviewDate ?? this.lastReviewDate,
    );
  }
}

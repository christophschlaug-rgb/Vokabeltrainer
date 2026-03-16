// lib/models/vocabulary.dart
class Vocabulary {
  final int?    id;
  final String  wordEn;
  final String  wordDe;
  final String? example;
  final String? level;
  final int     sortOrder;
  final int     successStreak;
  final int     totalCorrect;
  final int     totalWrong;
  final String  nextReviewDate;
  final String? lastResult;
  final String? lastReviewDate;

  Vocabulary({
    this.id,
    required this.wordEn,
    required this.wordDe,
    this.example,
    this.level,
    this.sortOrder    = 9999,
    this.successStreak = 0,
    this.totalCorrect  = 0,
    this.totalWrong    = 0,
    String? nextReviewDate,
    this.lastResult,
    this.lastReviewDate,
  }) : nextReviewDate = nextReviewDate ?? DateTime.now().toIso8601String();

  List<String> get germanTranslations =>
      wordDe.split('|').map((s) => s.trim().toLowerCase()).toList();

  List<String> get englishVariants =>
      wordEn.split('|').map((s) => s.trim().toLowerCase()).toList();

  factory Vocabulary.fromMap(Map<String, dynamic> m) => Vocabulary(
    id:             m['id']             as int?,
    wordEn:         m['word_en']        as String,
    wordDe:         m['word_de']        as String,
    example:        m['example']        as String?,
    level:          m['level']          as String?,
    sortOrder:      (m['sort_order']    as int?) ?? 9999,
    successStreak:  (m['success_streak'] as int?) ?? 0,
    totalCorrect:   (m['total_correct'] as int?) ?? 0,
    totalWrong:     (m['total_wrong']   as int?) ?? 0,
    nextReviewDate: m['next_review_date'] as String? ??
                    DateTime.now().toIso8601String(),
    lastResult:     m['last_result']    as String?,
    lastReviewDate: m['last_review_date'] as String?,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'word_en':          wordEn,
    'word_de':          wordDe,
    'example':          example,
    'level':            level,
    'sort_order':       sortOrder,
    'success_streak':   successStreak,
    'total_correct':    totalCorrect,
    'total_wrong':      totalWrong,
    'next_review_date': nextReviewDate,
    'last_result':      lastResult,
    'last_review_date': lastReviewDate,
  };

  Vocabulary copyWith({
    int?    successStreak,
    int?    totalCorrect,
    int?    totalWrong,
    String? nextReviewDate,
    String? lastResult,
    String? lastReviewDate,
  }) => Vocabulary(
    id:             id,
    wordEn:         wordEn,
    wordDe:         wordDe,
    example:        example,
    level:          level,
    sortOrder:      sortOrder,
    successStreak:  successStreak  ?? this.successStreak,
    totalCorrect:   totalCorrect   ?? this.totalCorrect,
    totalWrong:     totalWrong     ?? this.totalWrong,
    nextReviewDate: nextReviewDate ?? this.nextReviewDate,
    lastResult:     lastResult     ?? this.lastResult,
    lastReviewDate: lastReviewDate ?? this.lastReviewDate,
  );
}

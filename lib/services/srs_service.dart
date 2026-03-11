// lib/services/srs_service.dart
// Spaced-Repetition-Logik
//
// Wie funktioniert das SRS-System?
// ─────────────────────────────────
// Idee: Vokabeln, die du gut kennst, werden seltener wiederholt.
// Vokabeln, die du nicht weißt, kommen schneller wieder.
//
//   successStreak = 1 → nächste Wiederholung in 1 Tag
//   successStreak = 2 → nächste Wiederholung in 3 Tagen
//   successStreak = 3 → nächste Wiederholung in 10 Tagen
//   successStreak = 4 → nächste Wiederholung in 30 Tagen
//   successStreak = 5 → nächste Wiederholung in 90 Tagen
//   successStreak ≥ 6 → nächste Wiederholung in 180 Tagen
//
//   Bei falscher Antwort:
//     successStreak wird auf 0 zurückgesetzt
//     → Vokabel erscheint morgen wieder

import '../models/vocabulary.dart';

class SrsService {
  // Intervalle in Tagen basierend auf successStreak (Index = Streak)
  // Index 0 wird nie verwendet (neues Wort, noch nie beantwortet)
  static const List<int> _intervals = [1, 1, 3, 10, 30, 90, 180];

  /// Berechnet das nächste Wiederholungsdatum basierend auf richtig/falsch
  static Vocabulary updateAfterReview({
    required Vocabulary vocab,
    required bool wasCorrect,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (wasCorrect) {
      // Richtig: Streak erhöhen, längeres Intervall
      final newStreak = vocab.successStreak + 1;
      final intervalIndex = newStreak.clamp(0, _intervals.length - 1);
      final intervalDays = _intervals[intervalIndex];
      // Intervallfolge: 1 → 3 → 10 → 30 → 90 → 180 Tage
      final nextDate = today.add(Duration(days: intervalDays));

      return vocab.copyWith(
        successStreak: newStreak,
        totalCorrect: vocab.totalCorrect + 1,
        nextReviewDate: nextDate.toIso8601String(),
        lastResult: 'correct',
        lastReviewDate: now.toIso8601String(),
      );
    } else {
      // Falsch: Streak zurücksetzen, morgen wieder abfragen
      final nextDate = today.add(const Duration(days: 1));

      return vocab.copyWith(
        successStreak: 0,
        totalWrong: vocab.totalWrong + 1,
        nextReviewDate: nextDate.toIso8601String(),
        lastResult: 'wrong',
        lastReviewDate: now.toIso8601String(),
      );
    }
  }

  /// Gibt zurück wie viele Tage bis zur nächsten Wiederholung
  static String getIntervalDescription(int successStreak) {
    final index = successStreak.clamp(0, _intervals.length - 1);
    final days = _intervals[index];
    if (days == 1) return 'morgen';
    if (days < 7) return 'in $days Tagen';
    if (days == 10) return 'in 10 Tagen';
    if (days == 30) return 'in einem Monat';
    if (days == 90) return 'in 3 Monaten';
    return 'in 6 Monaten';
  }

  /// Prüft ob eine Antwort korrekt ist.
  ///
  /// Regeln:
  ///   - Groß/Kleinschreibung wird ignoriert (auch im Englischen)
  ///   - Führende/nachfolgende Leerzeichen werden ignoriert
  ///   - "to" vor englischen Verben ist optional:
  ///       Eingabe "achieve" gilt als richtig wenn Lösung "to achieve" ist
  ///       Eingabe "to achieve" gilt als richtig wenn Lösung "achieve" ist
  static bool checkAnswer({
    required String userInput,
    required List<String> correctAnswers,
  }) {
    final cleaned = userInput.trim().toLowerCase();
    if (cleaned.isEmpty) return false;

    // Version ohne "to " am Anfang (falls vorhanden)
    final cleanedWithoutTo =
        cleaned.startsWith('to ') ? cleaned.substring(3).trim() : null;
    // Version mit "to " am Anfang (falls nicht vorhanden)
    final cleanedWithTo =
        !cleaned.startsWith('to ') ? 'to $cleaned' : null;

    for (final answer in correctAnswers) {
      final cleanAnswer = answer.trim().toLowerCase();

      // 1. Direkte Übereinstimmung (case-insensitive)
      if (cleaned == cleanAnswer) return true;

      // 2. Eingabe ohne "to", Antwort hat "to" → "achieve" == "to achieve"
      if (cleanedWithoutTo != null && cleanAnswer == cleanedWithoutTo) return true;

      // 3. Antwort ohne "to", Eingabe hat "to" → "to achieve" == "achieve"
      if (cleanedWithTo != null && cleanAnswer == cleanedWithTo) return true;

      // 4. Beide ohne "to" vergleichen (Normalisierung)
      final answerWithoutTo = cleanAnswer.startsWith('to ')
          ? cleanAnswer.substring(3).trim()
          : cleanAnswer;
      final inputBase = cleanedWithoutTo ?? cleaned;
      if (inputBase == answerWithoutTo) return true;
    }
    return false;
  }

  /// Berechnet Ähnlichkeit mit Levenshtein-Distanz (für "fast richtig"-Erkennung)
  /// Gibt true zurück wenn Eingabe sehr nah an einer Lösung ist
  static bool isNearlyCorrect({
    required String userInput,
    required List<String> correctAnswers,
  }) {
    final cleaned = userInput.trim().toLowerCase();
    for (final answer in correctAnswers) {
      final dist = _levenshtein(cleaned, answer.trim().toLowerCase());
      // Maximal 2 Tippfehler erlaubt bei Wörtern ≥ 5 Zeichen
      if (dist <= 2 && answer.length >= 5) return true;
    }
    return false;
  }

  /// Levenshtein-Distanz: misst wie viele Buchstaben man ändern müsste
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> row = List.generate(b.length + 1, (i) => i);

    for (int i = 1; i <= a.length; i++) {
      int prev = i;
      for (int j = 1; j <= b.length; j++) {
        int val = a[i - 1] == b[j - 1]
            ? row[j - 1]
            : 1 + [prev, row[j], row[j - 1]].reduce((x, y) => x < y ? x : y);
        row[j - 1] = prev;
        prev = val;
      }
      row[b.length] = prev;
    }
    return row[b.length];
  }
}

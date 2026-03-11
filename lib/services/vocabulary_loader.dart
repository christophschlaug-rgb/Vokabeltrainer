// lib/services/vocabulary_loader.dart
//
// DATENQUELLE: TU Chemnitz Deutsch-Englisch Wörterbuch
// ─────────────────────────────────────────────────────
// Urheber: Frank Richter, TU Chemnitz (seit 1995)
// Lizenz:  GNU GPL 2.0+ — kostenlos und rechtlich einwandfrei
// URL:     https://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en/
// Roheinträge: ~400.000 — die App filtert auf die besten ~15.000
//
// Ablauf beim ersten Start:
//   1. Wörterbuchdatei (~8 MB) wird heruntergeladen
//   2. Einträge werden gefiltert und bereinigt
//   3. Maximal 15.000 Einträge werden lokal in SQLite gespeichert
//   4. Danach funktioniert die App vollständig offline
//
// Filter-Kriterien (was behalten wird):
//   - Einfache Wörter oder kurze Phrasen (max. 4 Wörter)
//   - Keine reinen Abkürzungen
//   - Keine Einträge mit Sonderzeichen wie / < > =
//   - Keine zu kurzen Einträge (unter 3 Zeichen)
//   - Häufige Wörter zuerst (Reihenfolge in der Quelldatei)

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vocabulary.dart';
import 'database_service.dart';

class VocabularyLoader {
  // URL zur Wörterbuchdatei der TU Chemnitz (GNU GPL 2.0+)
  static const String _dictUrl =
      'https://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en/de-en.txt';

  // Maximale Anzahl zu speichernder Einträge
  static const int _maxEntries = 15000;

  /// Hauptfunktion: Vokabeln laden und in lokaler Datenbank speichern
  static Future<int> loadAndSaveVocabularies({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Verbinde mit TU Chemnitz Wörterbuch...');

    List<Vocabulary> vocabs = [];

    try {
      vocabs = await _loadFromTuChemnitz(onStatus: onStatus);
    } catch (e) {
      onStatus?.call(
        'Online-Laden fehlgeschlagen.\n'
        'Bitte Internetverbindung prüfen und\n'
        '"Aktualisieren" erneut antippen.',
      );
      // Eingebettete Notfall-Liste als Fallback
      vocabs = _getBuiltinFallback();
    }

    if (vocabs.isEmpty) {
      vocabs = _getBuiltinFallback();
    }

    onStatus?.call('Speichere ${vocabs.length} Vokabeln lokal...');
    await DatabaseService.insertVocabularies(vocabs);

    final total = await DatabaseService.getVocabularyCount();
    onStatus?.call('✅ Fertig! $total Vokabeln verfügbar.');
    return vocabs.length;
  }

  /// Wörterbuch von TU Chemnitz herunterladen und auf beste Einträge filtern
  static Future<List<Vocabulary>> _loadFromTuChemnitz({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Lade Wörterbuch herunter (~8 MB)...\nBitte 1-2 Minuten warten.');

    final response = await http.get(
      Uri.parse(_dictUrl),
    ).timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    // TU Chemnitz Datei ist in Latin-1 kodiert
    String rawText;
    try {
      rawText = latin1.decode(response.bodyBytes);
    } catch (_) {
      rawText = utf8.decode(response.bodyBytes, allowMalformed: true);
    }

    onStatus?.call('Verarbeite und filtere Einträge...');
    return _parseDingFormat(rawText, onStatus: onStatus);
  }

  /// Parst das Ding-Format und filtert auf die besten Einträge
  static List<Vocabulary> _parseDingFormat(
    String text, {
    void Function(String status)? onStatus,
  }) {
    final vocabs = <Vocabulary>[];
    final lines = text.split('\n');
    int processed = 0;
    int skipped = 0;

    for (final rawLine in lines) {
      // Sobald wir genug haben, aufhören
      if (vocabs.length >= _maxEntries) break;

      final line = rawLine.trim();

      // Kommentare und leere Zeilen überspringen
      if (line.isEmpty || line.startsWith('#')) continue;

      // Trennzeichen " :: " finden
      final sepIdx = line.indexOf(' :: ');
      if (sepIdx < 0) continue;

      final dePart = line.substring(0, sepIdx).trim();
      final enPart = line.substring(sepIdx + 4).trim();

      if (dePart.isEmpty || enPart.isEmpty) continue;

      // Eintrag bereinigen
      final wordDe = _extractBestTerm(dePart);
      final wordEn = _extractBestTerm(enPart);

      if (wordDe.isEmpty || wordEn.isEmpty) {
        skipped++;
        continue;
      }

      // Qualitätsfilter
      if (!_passesQualityFilter(wordEn, wordDe)) {
        skipped++;
        continue;
      }

      vocabs.add(Vocabulary(
        wordEn: wordEn,
        wordDe: wordDe,
        level: 'DE-EN',
      ));

      processed++;
      if (processed % 2000 == 0) {
        onStatus?.call(
          '${vocabs.length} von $_maxEntries Einträgen gesammelt...',
        );
      }
    }

    onStatus?.call('${vocabs.length} Einträge ausgewählt (${skipped} übersprungen).');
    return vocabs;
  }

  /// Qualitätsfilter: Gibt true zurück wenn der Eintrag sinnvoll ist
  static bool _passesQualityFilter(String en, String de) {
    // Zu kurze Einträge ablehnen
    final enFirst = en.split('|').first;
    final deFirst = de.split('|').first;
    if (enFirst.length < 3 || deFirst.length < 3) return false;

    // Einträge mit Sonderzeichen ablehnen (technische/math. Symbole)
    final badChars = RegExp(r'[<>=\+\*\^\$\\]');
    if (badChars.hasMatch(enFirst) || badChars.hasMatch(deFirst)) return false;

    // Reine Abkürzungen überspringen (z.B. "USA", "NATO")
    // Erlaubt: "DNA", "GPS" wenn auch eine Beschreibung da ist
    if (enFirst == enFirst.toUpperCase() && enFirst.length <= 4 &&
        !enFirst.contains(' ')) {
      return false;
    }

    // Einträge die nur Zahlen sind ablehnen
    if (RegExp(r'^\d+$').hasMatch(enFirst)) return false;

    // Zu lange Phrasen ablehnen (mehr als 5 Wörter)
    if (enFirst.split(' ').length > 5) return false;

    return true;
  }

  /// Bereinigt einen Ding-Format-Eintrag und gibt die besten Varianten zurück
  static String _extractBestTerm(String raw) {
    // Inhalt in eckigen Klammern entfernen: [Am.], [Br.], [Plural]
    var cleaned = raw.replaceAll(RegExp(r'\[.*?\]'), '');

    // Inhalt in geschweiften Klammern entfernen: {sth.}, {etw.}
    cleaned = cleaned.replaceAll(RegExp(r'\{.*?\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\{[^}]*\}'), '');

    // Inhalt in runden Klammern entfernen: (ugs.), (fam.)
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');

    // Mehrfacheinträge durch Semikolon aufteilen
    final parts = cleaned
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 2)
        .where((s) => s.split(' ').length <= 4) // max 4 Wörter pro Begriff
        .where((s) => !s.contains('/'))
        .where((s) => !s.contains('\\'))
        .take(3) // max 3 Synonyme
        .toList();

    if (parts.isEmpty) return '';
    return parts.join('|');
  }

  // ── Eingebettete Notfall-Liste (50 Wörter) ────────────────────────────────
  // Wird nur angezeigt wenn kein Internet verfügbar ist
  static List<Vocabulary> _getBuiltinFallback() {
    return [
      Vocabulary(wordEn: 'to achieve', wordDe: 'erreichen|erzielen', level: 'C1'),
      Vocabulary(wordEn: 'to acknowledge', wordDe: 'anerkennen|bestätigen', level: 'C1'),
      Vocabulary(wordEn: 'adequate', wordDe: 'angemessen|ausreichend', level: 'C1'),
      Vocabulary(wordEn: 'to advocate', wordDe: 'befürworten|eintreten für', level: 'C1'),
      Vocabulary(wordEn: 'ambiguous', wordDe: 'mehrdeutig|zweideutig', level: 'C1'),
      Vocabulary(wordEn: 'to analyze', wordDe: 'analysieren|untersuchen', level: 'C1'),
      Vocabulary(wordEn: 'to anticipate', wordDe: 'vorwegnehmen|erwarten', level: 'C1'),
      Vocabulary(wordEn: 'compelling', wordDe: 'überzeugend|zwingend', level: 'C1'),
      Vocabulary(wordEn: 'comprehensive', wordDe: 'umfassend|vollständig', level: 'C1'),
      Vocabulary(wordEn: 'crucial', wordDe: 'entscheidend|wesentlich', level: 'C1'),
      Vocabulary(wordEn: 'to enhance', wordDe: 'verbessern|steigern', level: 'C1'),
      Vocabulary(wordEn: 'to evaluate', wordDe: 'auswerten|bewerten', level: 'C1'),
      Vocabulary(wordEn: 'to facilitate', wordDe: 'erleichtern|fördern', level: 'C1'),
      Vocabulary(wordEn: 'fundamental', wordDe: 'grundlegend|fundamental', level: 'C1'),
      Vocabulary(wordEn: 'to implement', wordDe: 'umsetzen|implementieren', level: 'C1'),
      Vocabulary(wordEn: 'inevitable', wordDe: 'unvermeidlich|unvermeidbar', level: 'C1'),
      Vocabulary(wordEn: 'to integrate', wordDe: 'integrieren|eingliedern', level: 'C1'),
      Vocabulary(wordEn: 'to maintain', wordDe: 'aufrechterhalten|pflegen', level: 'C1'),
      Vocabulary(wordEn: 'to mitigate', wordDe: 'abschwächen|lindern', level: 'C1'),
      Vocabulary(wordEn: 'to perceive', wordDe: 'wahrnehmen|erkennen', level: 'C1'),
      Vocabulary(wordEn: 'perspective', wordDe: 'Perspektive|Sichtweise', level: 'C1'),
      Vocabulary(wordEn: 'to prioritize', wordDe: 'priorisieren|vorrangig behandeln', level: 'C1'),
      Vocabulary(wordEn: 'to regulate', wordDe: 'regulieren|kontrollieren', level: 'C1'),
      Vocabulary(wordEn: 'significant', wordDe: 'bedeutend|erheblich', level: 'C1'),
      Vocabulary(wordEn: 'sophisticated', wordDe: 'ausgereift|anspruchsvoll', level: 'C1'),
      Vocabulary(wordEn: 'to sustain', wordDe: 'aufrechterhalten|stützen', level: 'C1'),
      Vocabulary(wordEn: 'systematic', wordDe: 'systematisch|methodisch', level: 'C1'),
      Vocabulary(wordEn: 'to tackle', wordDe: 'angehen|bewältigen', level: 'C1'),
      Vocabulary(wordEn: 'to transform', wordDe: 'verwandeln|umgestalten', level: 'C1'),
      Vocabulary(wordEn: 'underlying', wordDe: 'zugrunde liegend|ursächlich', level: 'C1'),
      Vocabulary(wordEn: 'to undermine', wordDe: 'untergraben|schwächen', level: 'C1'),
      Vocabulary(wordEn: 'viable', wordDe: 'machbar|lebensfähig', level: 'C1'),
      Vocabulary(wordEn: 'widespread', wordDe: 'weit verbreitet|weitreichend', level: 'C1'),
      Vocabulary(wordEn: 'to yield', wordDe: 'ergeben|nachgeben', level: 'C1'),
      Vocabulary(wordEn: 'coherent', wordDe: 'kohärent|schlüssig', level: 'C1'),
      Vocabulary(wordEn: 'to contribute', wordDe: 'beitragen|beisteuern', level: 'C1'),
      Vocabulary(wordEn: 'controversial', wordDe: 'umstritten|kontrovers', level: 'C1'),
      Vocabulary(wordEn: 'empirical', wordDe: 'empirisch|erfahrungsbasiert', level: 'C1'),
      Vocabulary(wordEn: 'to establish', wordDe: 'gründen|einrichten', level: 'C1'),
      Vocabulary(wordEn: 'to overcome', wordDe: 'überwinden|bewältigen', level: 'C1'),
      Vocabulary(wordEn: 'phenomenon', wordDe: 'Phänomen|Erscheinung', level: 'C1'),
      Vocabulary(wordEn: 'to promote', wordDe: 'fördern|bewerben', level: 'C1'),
      Vocabulary(wordEn: 'relevant', wordDe: 'relevant|bedeutsam', level: 'C1'),
      Vocabulary(wordEn: 'to reinforce', wordDe: 'verstärken|bekräftigen', level: 'C1'),
      Vocabulary(wordEn: 'to resolve', wordDe: 'lösen|klären', level: 'C1'),
      Vocabulary(wordEn: 'rigorous', wordDe: 'streng|gründlich', level: 'C1'),
      Vocabulary(wordEn: 'to seek', wordDe: 'suchen|anstreben', level: 'C1'),
      Vocabulary(wordEn: 'to utilize', wordDe: 'nutzen|verwenden', level: 'C1'),
      Vocabulary(wordEn: 'to validate', wordDe: 'bestätigen|validieren', level: 'C1'),
      Vocabulary(wordEn: 'to verify', wordDe: 'überprüfen|bestätigen', level: 'C1'),
    ];
  }
}

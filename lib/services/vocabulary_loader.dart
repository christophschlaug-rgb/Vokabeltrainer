// lib/services/vocabulary_loader.dart
//
// DATENQUELLE: TU Chemnitz Deutsch-Englisch Wörterbuch
// Lizenz: GNU GPL 2.0+
// URL: https://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en/

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vocabulary.dart';
import 'database_service.dart';

class VocabularyLoader {
  static const String _dictUrl =
      'https://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en/de-en.txt';

  static const int _maxEntries = 15000;

  // Maximale Dateigröße: 20 MB (Schutz vor zu großen Antworten)
  static const int _maxResponseBytes = 20 * 1024 * 1024;

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

  static Future<List<Vocabulary>> _loadFromTuChemnitz({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Lade Wörterbuch herunter (~8 MB)...\nBitte 1-2 Minuten warten.');

    // Sicherheit: Timeout und Größenbeschränkung
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(_dictUrl));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      // Größenbeschränkung: max 20 MB einlesen
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length > _maxResponseBytes) {
          break; // Genug geladen, Rest ignorieren
        }
      }

      // TU Chemnitz Datei ist in Latin-1 kodiert
      String rawText;
      try {
        rawText = latin1.decode(bytes);
      } catch (_) {
        rawText = utf8.decode(bytes, allowMalformed: true);
      }

      onStatus?.call('Verarbeite und filtere Einträge...');
      return _parseDingFormat(rawText, onStatus: onStatus);
    } finally {
      client.close();
    }
  }

  static List<Vocabulary> _parseDingFormat(
    String text, {
    void Function(String status)? onStatus,
  }) {
    final vocabs = <Vocabulary>[];
    final lines = text.split('\n');
    int skipped = 0;

    for (final rawLine in lines) {
      if (vocabs.length >= _maxEntries) break;

      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final sepIdx = line.indexOf(' :: ');
      if (sepIdx < 0) continue;

      final dePart = line.substring(0, sepIdx).trim();
      final enPart = line.substring(sepIdx + 4).trim();

      if (dePart.isEmpty || enPart.isEmpty) continue;

      final wordDe = _extractBestTerm(dePart);
      final wordEn = _extractBestTerm(enPart);

      if (wordDe.isEmpty || wordEn.isEmpty) {
        skipped++;
        continue;
      }

      if (!_passesQualityFilter(wordEn, wordDe)) {
        skipped++;
        continue;
      }

      vocabs.add(Vocabulary(wordEn: wordEn, wordDe: wordDe, level: 'DE-EN'));

      if (vocabs.length % 2000 == 0) {
        onStatus?.call('${vocabs.length} von $_maxEntries Einträgen gesammelt...');
      }
    }

    onStatus?.call('${vocabs.length} Einträge ausgewählt.');
    return vocabs;
  }

  static bool _passesQualityFilter(String en, String de) {
    final enFirst = en.split('|').first;
    final deFirst = de.split('|').first;
    if (enFirst.length < 3 || deFirst.length < 3) return false;

    final badChars = RegExp(r'[<>=\+\*\^\$\\]');
    if (badChars.hasMatch(enFirst) || badChars.hasMatch(deFirst)) return false;

    if (enFirst == enFirst.toUpperCase() &&
        enFirst.length <= 4 &&
        !enFirst.contains(' ')) {
      return false;
    }

    if (RegExp(r'^\d+$').hasMatch(enFirst)) return false;
    if (enFirst.split(' ').length > 5) return false;

    return true;
  }

  static String _extractBestTerm(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'\[.*?\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\{[^}]*\}'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');

    final parts = cleaned
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 2)
        .where((s) => s.split(' ').length <= 4)
        .where((s) => !s.contains('/'))
        .where((s) => !s.contains('\\'))
        .take(3)
        .toList();

    if (parts.isEmpty) return '';
    return parts.join('|');
  }

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

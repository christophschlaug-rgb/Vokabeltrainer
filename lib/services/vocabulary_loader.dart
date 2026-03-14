// lib/services/vocabulary_loader.dart
// Lädt das TU Chemnitz Wörterbuch (GNU GPL 2.0+)
//
// WICHTIG zur URL:
//   ftp.tu-chemnitz.de ist ein FTP-Spiegel ohne HTTPS-Zertifikat.
//   Die URL muss http:// sein — HTTPS schlägt mit SSL-Fehler fehl.
//   HTTP ist in network_security_config.xml für diese Domain explizit erlaubt.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vocabulary.dart';
import 'database_service.dart';

class VocabularyLoader {
  // HTTP (nicht HTTPS) — ftp.tu-chemnitz.de hat kein HTTPS-Zertifikat
  static const String _dictUrl =
      'http://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en/de-en.txt';

  // Fallback-URL falls der Hauptserver nicht erreichbar ist
  static const String _mirrorUrl =
      'http://www.dict.cc/translation_files/download_ding.php';

  static const int _maxEntries = 15000;
  static const int _maxResponseBytes = 25 * 1024 * 1024; // 25 MB Sicherheitslimit

  /// Vokabeln laden, deduplizieren und speichern.
  /// Bestehender Lernfortschritt bleibt erhalten.
  static Future<int> loadAndSaveVocabularies({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Verbinde mit Wörterbuch-Server...');

    List<Vocabulary> vocabs = [];
    String? errorMsg;

    // Versuch 1: TU Chemnitz (primär)
    try {
      vocabs = await _downloadAndParse(_dictUrl, onStatus: onStatus);
    } catch (e) {
      errorMsg = e.toString();
      onStatus?.call('Primärer Server nicht erreichbar.\nPrüfe Internetverbindung...');
    }

    // Wenn Download fehlgeschlagen: vorhandene DB behalten
    if (vocabs.isEmpty) {
      final existing = await DatabaseService.getVocabularyCount();
      if (existing > 0) {
        onStatus?.call(
          '⚠️ Download fehlgeschlagen ($errorMsg).\n'
          'Vorhandene $existing Vokabeln bleiben erhalten.\n'
          'Bitte "Neu laden" antippen wenn WLAN verfügbar.',
        );
        return existing;
      }
      // Absoluter Notfall: noch keine DB und kein Netz
      onStatus?.call('Kein Internet — lade 50 Offline-Vokabeln...');
      vocabs = _getBuiltinFallback();
    }

    onStatus?.call('Speichere ${vocabs.length} Vokabeln (ohne Duplikate)...');
    await DatabaseService.replaceAllVocabularies(vocabs);

    final total = await DatabaseService.getVocabularyCount();
    onStatus?.call('✅ Fertig! $total Vokabeln verfügbar.');
    return total;
  }

  static Future<List<Vocabulary>> _downloadAndParse(
    String url, {
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Lade Wörterbuch herunter (~8 MB)...\nBitte 1–2 Minuten warten.');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      // Kein Accept-Encoding: verhindert Probleme mit komprimierten Antworten
      request.headers['Accept-Encoding'] = 'identity';

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 180));

      if (response.statusCode != 200) {
        throw Exception('HTTP-Fehler: ${response.statusCode}');
      }

      // Sicherheit: max. 25 MB einlesen
      final bytes = <int>[];
      int lastReport = 0;
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        // Fortschritt melden
        final mb = bytes.length ~/ (1024 * 1024);
        if (mb > lastReport) {
          lastReport = mb;
          onStatus?.call('Lade Wörterbuch... ${mb} MB heruntergeladen');
        }
        if (bytes.length > _maxResponseBytes) break;
      }

      onStatus?.call('${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB geladen. Verarbeite...');

      // Datei ist Latin-1 kodiert
      String rawText;
      try {
        rawText = latin1.decode(bytes);
      } catch (_) {
        rawText = utf8.decode(bytes, allowMalformed: true);
      }

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
    final seenEn = <String>{};  // Duplikat-Prüfung
    int skipped = 0;

    final lines = text.split('\n');
    onStatus?.call('Verarbeite ${lines.length} Zeilen...');

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
      if (wordDe.isEmpty || wordEn.isEmpty) { skipped++; continue; }

      if (!_passesQualityFilter(wordEn, wordDe)) { skipped++; continue; }

      // Duplikat-Check per normalisiertem Schlüssel
      final key = wordEn.split('|').first.trim().toLowerCase();
      if (seenEn.contains(key)) { skipped++; continue; }
      seenEn.add(key);

      vocabs.add(Vocabulary(wordEn: wordEn, wordDe: wordDe, level: 'DE-EN'));

      if (vocabs.length % 2000 == 0) {
        onStatus?.call('${vocabs.length} Einträge gesammelt...');
      }
    }

    onStatus?.call('${vocabs.length} Einträge ausgewählt ($skipped gefiltert/übersprungen).');
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
        !enFirst.contains(' ')) return false;

    if (RegExp(r'^\d+$').hasMatch(enFirst)) return false;
    if (enFirst.split(' ').length > 5) return false;

    return true;
  }

  static String _extractBestTerm(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '');

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

  // 50 Offline-Vokabeln — NUR wenn absolut kein Internet vorhanden
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

// lib/services/vocabulary_loader.dart
//
// Die TU-Chemnitz-Datei ist UTF-8 kodiert (nicht Latin-1).
// Sie enthält ~400.000 Einträge. Der Filter wählt ~15.000 alltagstaugliche aus.

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/vocabulary.dart';
import 'database_service.dart';
import 'builtin_vocabulary.dart';

class VocabularyLoader {
  // HTTP — ftp.tu-chemnitz.de hat kein gültiges HTTPS-Zertifikat
  // HTTP ist in network_security_config.xml für diese Domain explizit erlaubt
  static const _url =
      'http://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en-devel/de-en.txt';
  static const _max = 15000;
  static const _maxBytes = 25 * 1024 * 1024;

  static Future<int> loadAndSaveVocabularies({
    void Function(String)? onStatus,
  }) async {
    // Schritt 1: Eingebettete Wörter sofort laden (offline-sicher)
    onStatus?.call('Lade ${BuiltinVocabulary.entries.length} eingebettete Vokabeln...');
    final builtin = BuiltinVocabulary.entries
        .map((e) => Vocabulary(wordEn: e[0], wordDe: e[1], level: 'builtin'))
        .toList();
    await DatabaseService.replaceAllVocabularies(builtin);
    final builtinCount = await DatabaseService.getVocabularyCount();
    onStatus?.call('$builtinCount Vokabeln geladen. Starte Online-Download...');

    // Schritt 2: Online-Download
    try {
      final count = await _downloadAndSave(onStatus: onStatus);
      onStatus?.call('✅ $count Vokabeln verfügbar (Online-Wörterbuch).');
      return count;
    } catch (e) {
      onStatus?.call(
        '⚠️ Online-Download fehlgeschlagen:\n$e\n\n'
        'App läuft mit $builtinCount eingebetteten Vokabeln.\n'
        'Tippe "Download erneut versuchen" bei aktiver Internetverbindung.',
      );
      return builtinCount;
    }
  }

  static Future<int> _downloadAndSave({void Function(String)? onStatus}) async {
    onStatus?.call('Verbinde mit ftp.tu-chemnitz.de...');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(_url));
      req.headers['Accept-Encoding'] = 'identity';
      req.headers['User-Agent'] = 'VokabelTrainer/1.0';

      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      onStatus?.call('Verbunden. Lade Datei (~8 MB)...');
      final builder = BytesBuilder(copy: false);
      int lastMb = 0;

      await resp.stream
          .timeout(const Duration(seconds: 120))
          .forEach((chunk) {
        builder.add(chunk);
        final mb = builder.length ~/ (1024 * 1024);
        if (mb > lastMb) {
          lastMb = mb;
          onStatus?.call('$mb MB heruntergeladen...');
        }
      });

      final bytes = builder.toBytes();
      if (bytes.isEmpty) throw Exception('Leere Antwort');

      onStatus?.call('${bytes.length ~/ (1024 * 1024)} MB geladen. Verarbeite...');

      // Datei ist UTF-8 (nicht Latin-1) — direkt als UTF-8 dekodieren
      final text = utf8.decode(bytes, allowMalformed: true);

      onStatus?.call('Filtere Einträge...');
      final vocabs = _parse(text, onStatus: onStatus);

      if (vocabs.length < 500) {
        throw Exception('Zu wenige brauchbare Einträge: ${vocabs.length}');
      }

      onStatus?.call('Speichere ${vocabs.length} Vokabeln...');
      await DatabaseService.replaceAllVocabularies(vocabs);
      return await DatabaseService.getVocabularyCount();
    } finally {
      client.close();
    }
  }

  static List<Vocabulary> _parse(String text, {void Function(String)? onStatus}) {
    final list = <Vocabulary>[];
    final seen = <String>{};
    int filtered = 0;

    for (final raw in text.split('\n')) {
      if (list.length >= _max) break;
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final i = line.indexOf(' :: ');
      if (i < 0) continue;

      // TU Chemnitz Format: DE :: EN (Deutsch auf der linken Seite!)
      final deRaw = line.substring(0, i);
      final enRaw = line.substring(i + 4);

      final de = _clean(deRaw);
      final en = _clean(enRaw);
      if (de.isEmpty || en.isEmpty) { filtered++; continue; }

      if (!_ok(en, de)) { filtered++; continue; }

      final key = en.split('|').first.trim().toLowerCase();
      if (seen.contains(key)) { filtered++; continue; }
      seen.add(key);

      list.add(Vocabulary(wordEn: en, wordDe: de, level: 'DE-EN'));

      if (list.length % 3000 == 0) {
        onStatus?.call('${list.length} Einträge ausgewählt...');
      }
    }
    onStatus?.call('${list.length} Einträge ausgewählt ($filtered gefiltert).');
    return list;
  }

  /// Verschärfter Qualitätsfilter
  static bool _ok(String en, String de) {
    final e = en.split('|').first.trim();
    final d = de.split('|').first.trim();

    // Länge
    if (e.length < 3 || d.length < 3) return false;
    if (e.length > 50 || d.length > 50) return false;

    // Zu viele Wörter (Phrasen/Sätze)
    if (e.split(' ').length > 4) return false;

    // Sonderzeichen die auf Fachjargon/Formeln hinweisen
    if (RegExp(r'[<>=+*^$\\|@#~`]').hasMatch(e)) return false;

    // Schrägstrich = technische Alternativen (abachi/obeche/samba)
    if (e.contains('/') || d.contains('/')) return false;

    // Apostroph + Großbuchstabe am Wortanfang = Eigenname (Abadie's, O'Brien)
    if (e.contains("'") && e[0].toUpperCase() == e[0]) return false;

    // 'n = Slang/Eigennamen (Chip 'n Dale, rock 'n roll)
    if (e.toLowerCase().contains("'n ") || e.toLowerCase().contains(" 'n")) return false;

    // Fachjargon mit Bindestrich-Klassifikator: "class-A", "type-II", "grade-B"
    if (RegExp(r'-[A-Z0-9]{1,3}\b').hasMatch(e) && e.split(' ').length >= 2) return false;

    // Reine Großbuchstaben-Abkürzungen (NATO, DNA, USA als Einzelwort)
    if (e == e.toUpperCase() && e.length <= 5 && !e.contains(' ')) return false;

    // Beginnt mit Zahl
    if (RegExp(r'^\d').hasMatch(e)) return false;

    // Kodierungsfehler: Diese Zeichen sollten nach korrekter UTF-8 Dekodierung
    // nicht mehr vorkommen — wenn doch, war die Datei fehlerhaft
    if (e.contains('\uFFFD') || d.contains('\uFFFD')) return false;

    return true;
  }

  static String _clean(String raw) {
    // Klammern entfernen: [Am.] {sth.} (ugs.)
    String s = raw
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '');

    // Einträge aufteilen und bereinigen
    final parts = s
        .split(';')
        .map((x) => x.trim())
        .where((x) =>
            x.length >= 2 &&
            x.split(' ').length <= 4 &&
            !x.contains('/') &&
            !x.contains('\\'))
        .take(3)
        .toList();

    return parts.join('|');
  }
}

// lib/services/vocabulary_loader.dart
//
// STRATEGIE:
//   1. App startet sofort mit 2296 eingebetteten Vokabeln (kein Internet nötig)
//   2. Im Hintergrund wird das TU Chemnitz Wörterbuch geladen (15000 Einträge)
//   3. URL ist HTTP — ftp.tu-chemnitz.de hat kein HTTPS-Zertifikat
//   4. HTTP ist in network_security_config.xml für diese Domain explizit erlaubt

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vocabulary.dart';
import 'database_service.dart';
import 'builtin_vocabulary.dart';

class VocabularyLoader {
  // HTTP — ftp.tu-chemnitz.de unterstützt kein HTTPS
  static const String _dictUrl =
      'http://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en/de-en.txt';

  static const int _maxEntries = 15000;
  static const int _maxBytes = 25 * 1024 * 1024;

  /// Hauptfunktion: erst eingebettete Wörter laden, dann Online-Download.
  static Future<int> loadAndSaveVocabularies({
    void Function(String status)? onStatus,
  }) async {
    // Schritt 1: Eingebettete Wörter sofort speichern (offline-sicher)
    final builtinCount = await _saveBuiltin(onStatus: onStatus);

    // Schritt 2: Online-Download versuchen (erweitert auf 15000)
    onStatus?.call('Versuche Online-Download (~8 MB)...');
    try {
      final downloaded = await _downloadAndSave(onStatus: onStatus);
      if (downloaded > builtinCount) {
        onStatus?.call('✅ $downloaded Vokabeln verfügbar (Online-Wörterbuch).');
        return downloaded;
      }
    } catch (e) {
      onStatus?.call(
        '⚠️ Online-Download fehlgeschlagen: $e\n'
        'Die App läuft mit $builtinCount eingebetteten Vokabeln.\n'
        'Tippe "Neu laden" wenn WLAN verfügbar.',
      );
    }

    final total = await DatabaseService.getVocabularyCount();
    onStatus?.call('✅ $total Vokabeln verfügbar.');
    return total;
  }

  /// Eingebettete Wörter aus builtin_vocabulary.dart speichern
  static Future<int> _saveBuiltin({void Function(String)? onStatus}) async {
    onStatus?.call('Lade eingebettete Vokabeln...');
    final vocabs = BuiltinVocabulary.entries.map((e) =>
      Vocabulary(wordEn: e[0], wordDe: e[1], level: 'builtin')
    ).toList();

    await DatabaseService.replaceAllVocabularies(vocabs);
    final count = await DatabaseService.getVocabularyCount();
    onStatus?.call('$count eingebettete Vokabeln geladen.');
    return count;
  }

  /// Online-Download vom TU Chemnitz Server
  static Future<int> _downloadAndSave({void Function(String)? onStatus}) async {
    onStatus?.call('Verbinde mit ftp.tu-chemnitz.de (HTTP)...');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(_dictUrl));
      request.headers['Accept-Encoding'] = 'identity';
      request.headers['User-Agent'] = 'VokabelTrainer/1.0';

      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 180));

      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}');
      }

      final bytes = <int>[];
      int lastMb = 0;
      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
        final mb = bytes.length ~/ (1024 * 1024);
        if (mb > lastMb) {
          lastMb = mb;
          onStatus?.call('Lade... $mb MB');
        }
        if (bytes.length > _maxBytes) break;
      }

      onStatus?.call('${lastMb} MB geladen. Verarbeite Einträge...');

      String text;
      try {
        text = latin1.decode(bytes);
      } catch (_) {
        text = utf8.decode(bytes, allowMalformed: true);
      }

      final vocabs = _parse(text, onStatus: onStatus);
      if (vocabs.length < 100) {
        throw Exception('Zu wenige Einträge: ${vocabs.length}');
      }

      await DatabaseService.replaceAllVocabularies(vocabs);
      final total = await DatabaseService.getVocabularyCount();
      return total;
    } finally {
      client.close();
    }
  }

  static List<Vocabulary> _parse(String text, {void Function(String)? onStatus}) {
    final vocabs = <Vocabulary>[];
    final seen = <String>{};

    for (final raw in text.split('\n')) {
      if (vocabs.length >= _maxEntries) break;
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final sep = line.indexOf(' :: ');
      if (sep < 0) continue;

      final de = _clean(line.substring(0, sep));
      final en = _clean(line.substring(sep + 4));
      if (de.isEmpty || en.isEmpty) continue;
      if (!_ok(en, de)) continue;

      final key = en.split('|').first.trim().toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);

      vocabs.add(Vocabulary(wordEn: en, wordDe: de, level: 'DE-EN'));

      if (vocabs.length % 3000 == 0) {
        onStatus?.call('${vocabs.length} Einträge verarbeitet...');
      }
    }
    return vocabs;
  }

  static bool _ok(String en, String de) {
    final e = en.split('|').first;
    final d = de.split('|').first;
    if (e.length < 3 || d.length < 3) return false;
    if (RegExp(r'[<>=+*^$\\]').hasMatch(e)) return false;
    if (e == e.toUpperCase() && e.length <= 4 && !e.contains(' ')) return false;
    if (RegExp(r'^\d+$').hasMatch(e)) return false;
    if (e.split(' ').length > 5) return false;
    return true;
  }

  static String _clean(String raw) {
    var s = raw
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .replaceAll(RegExp(r'\([^)]*\)'), '');
    final parts = s.split(';')
      .map((x) => x.trim())
      .where((x) => x.length >= 2 && x.split(' ').length <= 4
                    && !x.contains('/') && !x.contains('\\'))
      .take(3).toList();
    return parts.join('|');
  }
}

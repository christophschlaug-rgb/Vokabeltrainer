// lib/services/vocabulary_loader.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vocabulary.dart';
import 'database_service.dart';
import 'builtin_vocabulary.dart';

class VocabularyLoader {
  // HTTP — ftp.tu-chemnitz.de hat kein gültiges HTTPS-Zertifikat
  // HTTP ist in network_security_config.xml für diese Domain erlaubt
  static const _url = 'http://ftp.tu-chemnitz.de/pub/Local/urz/ding/de-en/de-en.txt';
  static const _max = 15000;
  static const _maxBytes = 25 * 1024 * 1024;

  static Future<int> loadAndSaveVocabularies({
    void Function(String)? onStatus,
  }) async {
    // Schritt 1: Eingebettete Wörter sofort laden (offline, garantiert)
    onStatus?.call('Lade ${BuiltinVocabulary.entries.length} eingebettete Vokabeln...');
    final builtin = BuiltinVocabulary.entries
        .map((e) => Vocabulary(wordEn: e[0], wordDe: e[1], level: 'builtin'))
        .toList();
    await DatabaseService.replaceAllVocabularies(builtin);
    final builtinCount = await DatabaseService.getVocabularyCount();
    onStatus?.call('$builtinCount Vokabeln geladen.');

    // Schritt 2: Online-Download (erweitert auf 15000)
    onStatus?.call('Versuche Online-Download (http://ftp.tu-chemnitz.de)...');
    try {
      final count = await _downloadAndSave(onStatus: onStatus);
      onStatus?.call('✅ $count Vokabeln verfügbar (Online-Wörterbuch).');
      return count;
    } catch (e) {
      onStatus?.call(
        '⚠️ Online-Download fehlgeschlagen:\n$e\n\n'
        'Die App läuft mit $builtinCount eingebetteten Vokabeln.\n'
        'Tippe "Vokabeln neu laden" wenn WLAN verfügbar ist.',
      );
      return builtinCount;
    }
  }

  static Future<int> _downloadAndSave({void Function(String)? onStatus}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(_url));
      req.headers['Accept-Encoding'] = 'identity';
      req.headers['User-Agent'] = 'VokabelTrainer/1.0 Flutter';

      final resp = await client.send(req).timeout(const Duration(seconds: 180));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final bytes = <int>[];
      int lastMb = 0;
      await for (final chunk in resp.stream) {
        bytes.addAll(chunk);
        final mb = bytes.length ~/ (1024 * 1024);
        if (mb > lastMb) { lastMb = mb; onStatus?.call('Lade... $mb MB'); }
        if (bytes.length > _maxBytes) break;
      }

      onStatus?.call('${lastMb} MB geladen. Verarbeite...');
      String text;
      try { text = latin1.decode(bytes); }
      catch (_) { text = utf8.decode(bytes, allowMalformed: true); }

      final vocabs = _parse(text, onStatus: onStatus);
      if (vocabs.length < 500) throw Exception('Zu wenige Einträge: ${vocabs.length}');

      await DatabaseService.replaceAllVocabularies(vocabs);
      return await DatabaseService.getVocabularyCount();
    } finally {
      client.close();
    }
  }

  static List<Vocabulary> _parse(String text, {void Function(String)? onStatus}) {
    final list = <Vocabulary>[];
    final seen = <String>{};
    for (final raw in text.split('\n')) {
      if (list.length >= _max) break;
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final i = line.indexOf(' :: ');
      if (i < 0) continue;
      final de = _clean(line.substring(0, i));
      final en = _clean(line.substring(i + 4));
      if (de.isEmpty || en.isEmpty) continue;
      if (!_ok(en, de)) continue;
      final key = en.split('|').first.trim().toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      list.add(Vocabulary(wordEn: en, wordDe: de, level: 'DE-EN'));
      if (list.length % 3000 == 0) onStatus?.call('${list.length} Einträge...');
    }
    return list;
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
    final s = raw
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

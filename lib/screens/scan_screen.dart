// lib/screens/scan_screen.dart
// Scannt Text aus Fotos und ergänzt neue Wörter im Wörterbuch

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/database_service.dart';
import '../models/vocabulary.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isProcessing = false;
  String _status = '';
  List<_ScanResult> _results = [];
  File? _lastImage;

  final _picker = ImagePicker();

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _isProcessing = true;
      _status = 'Wähle Bild...';
      _results = [];
    });

    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2000,
      );
      if (picked == null) {
        setState(() { _isProcessing = false; _status = ''; });
        return;
      }

      _lastImage = File(picked.path);
      setState(() => _status = 'Erkenne Text...');

      // OCR mit ML Kit
      final inputImage = InputImage.fromFile(_lastImage!);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      final rawText = recognized.text;
      if (rawText.trim().isEmpty) {
        setState(() {
          _isProcessing = false;
          _status = '⚠️ Kein Text erkannt. Bitte ein schärferes Foto aufnehmen.';
        });
        return;
      }

      setState(() => _status = 'Analysiere Wörter...');

      // Wörter aus Text extrahieren
      final words = _extractWords(rawText);
      setState(() => _status = 'Gleiche mit Wörterbuch ab (${words.length} Wörter)...');

      // Jedes Wort mit der Datenbank abgleichen
      final results = <_ScanResult>[];
      for (final word in words) {
        final found = await DatabaseService.searchVocabularies(word);
        final inDict = found.any(
          (v) => v.wordEn.toLowerCase().contains(word.toLowerCase()) ||
                 v.wordDe.toLowerCase().contains(word.toLowerCase()),
        );
        results.add(_ScanResult(word: word, inDictionary: inDict));
      }

      setState(() {
        _results = results;
        _isProcessing = false;
        final newCount = results.where((r) => !r.inDictionary).length;
        _status = '${results.length} Wörter gefunden, $newCount noch nicht im Wörterbuch.';
      });

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _status = '⚠️ Fehler: $e';
      });
    }
  }

  // Wörter aus erkanntem Text extrahieren (nur sinnvolle englische Wörter)
  List<String> _extractWords(String text) {
    // Alle Wörter rausziehen
    final raw = text
        .replaceAll(RegExp(r'[^a-zA-Z\s\-]'), ' ')
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().toLowerCase())
        .where((w) =>
            w.length >= 3 &&       // mindestens 3 Buchstaben
            w.length <= 25 &&      // nicht zu lang
            RegExp(r'^[a-z]').hasMatch(w) && // beginnt mit Kleinbuchstabe
            !_isStopWord(w))       // kein Füllwort
        .toSet()                   // Duplikate entfernen
        .toList();
    raw.sort();
    return raw;
  }

  // Häufige englische Füllwörter überspringen
  static const _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
    'of', 'with', 'by', 'from', 'up', 'about', 'into', 'through', 'during',
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
    'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might',
    'this', 'that', 'these', 'those', 'i', 'you', 'he', 'she', 'it', 'we',
    'they', 'what', 'which', 'who', 'when', 'where', 'why', 'how',
    'not', 'no', 'nor', 'so', 'yet', 'both', 'either', 'neither',
    'than', 'then', 'its', 'our', 'your', 'his', 'her', 'their', 'my',
  };

  bool _isStopWord(String w) => _stopWords.contains(w);

  // Wort manuell zum Wörterbuch hinzufügen (ohne deutsche Übersetzung)
  Future<void> _addToDict(String word) async {
    // Prüfen ob schon vorhanden
    final existing = await DatabaseService.searchVocabularies(word);
    if (existing.any((v) => v.wordEn.toLowerCase() == word.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Wort bereits im Wörterbuch'),
          backgroundColor: Color(0xFF4ECDC4),
        ));
      }
      return;
    }

    // Hinzufügen mit leerem deutschen Feld (Platzhalter)
    final vocab = Vocabulary(
      wordEn: word,
      wordDe: '(keine Übersetzung)',
      level: 'scan',
    );
    await DatabaseService.insertVocabulary(vocab);

    setState(() {
      final idx = _results.indexWhere((r) => r.word == word);
      if (idx >= 0) _results[idx] = _ScanResult(word: word, inDictionary: true, justAdded: true);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('„$word" zum Wörterbuch hinzugefügt'),
        backgroundColor: const Color(0xFF2ECC71),
      ));
    }
  }

  // Alle neuen Wörter auf einmal hinzufügen
  Future<void> _addAllNew() async {
    final newWords = _results.where((r) => !r.inDictionary).toList();
    if (newWords.isEmpty) return;

    int added = 0;
    for (final r in newWords) {
      final existing = await DatabaseService.searchVocabularies(r.word);
      if (!existing.any((v) => v.wordEn.toLowerCase() == r.word.toLowerCase())) {
        await DatabaseService.insertVocabulary(Vocabulary(
          wordEn: r.word,
          wordDe: '(keine Übersetzung)',
          level: 'scan',
        ));
        added++;
      }
    }

    setState(() {
      for (int i = 0; i < _results.length; i++) {
        if (!_results[i].inDictionary) {
          _results[i] = _ScanResult(
              word: _results[i].word,
              inDictionary: true,
              justAdded: true);
        }
      }
      _status = '✅ $added Wörter zum Wörterbuch hinzugefügt.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final newWords = _results.where((r) => !r.inDictionary).length;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('📷 Seite scannen',
            style: TextStyle(color: Colors.white, fontSize: 18)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // Erklärungstext
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF4ECDC4).withOpacity(0.2)),
            ),
            child: const Text(
              '📖 Fotografiere eine Seite aus einem Englischbuch. '
              'Die App erkennt den Text, gleicht alle Wörter mit dem '
              'Wörterbuch ab und zeigt dir welche noch nicht enthalten sind.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          const SizedBox(height: 14),

          // Scan-Buttons
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _scan(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Foto aufnehmen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ECDC4),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _scan(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Aus Galerie'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // Vorschau des Fotos
          if (_lastImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                _lastImage!,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),

          // Status
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (_isProcessing) ...[
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF4ECDC4))),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(_status,
                  style: TextStyle(
                      color: _status.startsWith('⚠️')
                          ? const Color(0xFFFF6B6B)
                          : Colors.white70,
                      fontSize: 13))),
            ]),
          ],

          // "Alle hinzufügen" Button
          if (_results.isNotEmpty && newWords > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _addAllNew,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2ECC71),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Alle $newWords neuen Wörter hinzufügen'),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Ergebnisliste
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: r.inDictionary
                          ? Colors.white.withOpacity(0.03)
                          : const Color(0xFFFF6B35).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: r.inDictionary
                              ? Colors.white.withOpacity(0.06)
                              : const Color(0xFFFF6B35).withOpacity(0.3)),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(r.word,
                          style: TextStyle(
                              color: r.inDictionary
                                  ? Colors.white54
                                  : Colors.white,
                              fontSize: 14,
                              fontWeight: r.inDictionary
                                  ? FontWeight.normal
                                  : FontWeight.w600)),
                      trailing: r.justAdded
                          ? const Text('✅ Hinzugefügt',
                              style: TextStyle(
                                  color: Color(0xFF2ECC71), fontSize: 11))
                          : r.inDictionary
                              ? const Text('Im Wörterbuch',
                                  style: TextStyle(
                                      color: Colors.white24, fontSize: 11))
                              : TextButton(
                                  onPressed: () => _addToDict(r.word),
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(60, 28)),
                                  child: const Text('+ Hinzufügen',
                                      style: TextStyle(
                                          color: Color(0xFFFF6B35),
                                          fontSize: 11)),
                                ),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _ScanResult {
  final String word;
  final bool inDictionary;
  final bool justAdded;
  const _ScanResult({
    required this.word,
    required this.inDictionary,
    this.justAdded = false,
  });
}

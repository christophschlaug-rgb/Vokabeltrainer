// lib/screens/scan_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/database_service.dart';
import '../models/vocabulary.dart';

class ScanScreen extends StatefulWidget {
  final int? targetUnitId;
  final String? targetUnitName;
  const ScanScreen({super.key, this.targetUnitId, this.targetUnitName});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isProcessing = false;
  String _status = '';
  List<_ScanResult> _results = [];
  File? _lastImage;
  final _picker = ImagePicker();

  bool get _hasUnit => widget.targetUnitId != null;

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _isProcessing = true;
      _status = 'Wähle Bild...';
      _results = [];
    });

    try {
      final picked = await _picker.pickImage(
          source: source, imageQuality: 90, maxWidth: 2000);
      if (picked == null) {
        setState(() { _isProcessing = false; _status = ''; });
        return;
      }
      _lastImage = File(picked.path);
      setState(() => _status = 'Erkenne Text...');

      final inputImage = InputImage.fromFile(_lastImage!);
      final recognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      if (recognized.text.trim().isEmpty) {
        setState(() {
          _isProcessing = false;
          _status = '⚠️ Kein Text erkannt. Bitte schärferes Foto aufnehmen.';
        });
        return;
      }

      setState(() => _status = 'Analysiere Wörter...');
      final words = _extractWords(recognized.text);
      setState(() =>
          _status = 'Gleiche ${words.length} Wörter mit Wörterbuch ab...');

      final results = <_ScanResult>[];
      for (final word in words) {
        final found = await DatabaseService.searchVocabularies(word);
        final inDict = found.any(
          (v) =>
              v.wordEn.toLowerCase().split('|').any((e) =>
                  e.trim() == word.toLowerCase()) ||
              v.wordDe.toLowerCase().split('|').any((d) =>
                  d.trim() == word.toLowerCase()),
        );
        // Bereits in Unit?
        bool inUnit = false;
        if (_hasUnit) {
          final unitWords =
              await DatabaseService.getUnitWords(widget.targetUnitId!);
          inUnit = unitWords.any(
              (w) => w.toLowerCase() == word.toLowerCase());
        }
        results.add(_ScanResult(
            word: word, inDictionary: inDict, inUnit: inUnit));
      }

      final newCount = results.where((r) => !r.inUnit).length;
      setState(() {
        _results = results;
        _isProcessing = false;
        _status = _hasUnit
            ? '${results.length} Wörter · $newCount neu für „${widget.targetUnitName}"'
            : '${results.length} Wörter · ${results.where((r) => !r.inDictionary).length} nicht im Wörterbuch';
      });
    } catch (e) {
      setState(() { _isProcessing = false; _status = '⚠️ Fehler: $e'; });
    }
  }

  List<String> _extractWords(String text) {
    // Erlaubt: a-z, A-Z, Umlaute (ä,ö,ü,ß etc.), Leerzeichen, Bindestrich
    final cleaned =
        text.replaceAll(RegExp(r'[^a-zA-Z\u00C0-\u024F\s-]'), ' ');
    final words = cleaned
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.length >= 3 && w.length <= 25 && !_isStopWord(w))
        .toSet()
        .toList();
    words.sort();
    return words;
  }

  static const _stopWords = {
    'the','a','an','and','or','but','in','on','at','to','for','of','with',
    'by','from','up','about','into','through','during','is','are','was',
    'were','be','been','being','have','has','had','do','does','did','will',
    'would','could','should','may','might','this','that','these','those',
    'i','you','he','she','it','we','they','what','which','who','when',
    'where','why','how','not','no','nor','so','yet','both','either',
    'neither','than','then','its','our','your','his','her','their','my',
  };
  bool _isStopWord(String w) => _stopWords.contains(w);

  Future<void> _addToUnit(String word) async {
    if (!_hasUnit) return;
    await DatabaseService.addWordsToUnit(widget.targetUnitId!, [word]);
    setState(() {
      final idx = _results.indexWhere((r) => r.word == word);
      if (idx >= 0) {
        _results[idx] = _ScanResult(
            word: word,
            inDictionary: _results[idx].inDictionary,
            inUnit: true,
            justAdded: true);
      }
    });
  }

  Future<void> _addAllToUnit() async {
    if (!_hasUnit) return;
    final newWords =
        _results.where((r) => !r.inUnit).map((r) => r.word).toList();
    if (newWords.isEmpty) return;
    await DatabaseService.addWordsToUnit(widget.targetUnitId!, newWords);
    setState(() {
      for (int i = 0; i < _results.length; i++) {
        if (!_results[i].inUnit) {
          _results[i] = _ScanResult(
              word: _results[i].word,
              inDictionary: _results[i].inDictionary,
              inUnit: true,
              justAdded: true);
        }
      }
      _status = '✅ ${newWords.length} Wörter zu „${widget.targetUnitName}" hinzugefügt';
    });
  }

  Future<void> _addToDict(String word) async {
    final existing = await DatabaseService.searchVocabularies(word);
    if (existing.any(
        (v) => v.wordEn.toLowerCase() == word.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Wort bereits im Wörterbuch'),
          backgroundColor: Color(0xFF4ECDC4),
        ));
      }
      return;
    }
    await DatabaseService.insertVocabulary(
        Vocabulary(wordEn: word, wordDe: '(keine Übersetzung)', level: 'scan'));
    setState(() {
      final idx = _results.indexWhere((r) => r.word == word);
      if (idx >= 0) {
        _results[idx] = _ScanResult(
            word: word, inDictionary: true, inUnit: _results[idx].inUnit, justAdded: true);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('„$word" zum Wörterbuch hinzugefügt'),
        backgroundColor: const Color(0xFF2ECC71),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final newCount = _results.where((r) => _hasUnit ? !r.inUnit : !r.inDictionary).length;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📷 Buchseite scannen',
              style: TextStyle(color: Colors.white, fontSize: 17)),
          if (_hasUnit)
            Text('→ ${widget.targetUnitName}',
                style: const TextStyle(
                    color: Color(0xFF4ECDC4), fontSize: 12)),
        ]),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          // Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF4ECDC4).withOpacity(0.2)),
            ),
            child: Text(
              _hasUnit
                  ? '📖 Fotografiere eine Buchseite. Erkannte Wörter werden mit „${widget.targetUnitName}" verknüpft.'
                  : '📖 Fotografiere eine Buchseite. Die App gleicht alle Wörter mit dem Wörterbuch ab.',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Scan-Buttons
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isProcessing ? null : () => _scan(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Foto aufnehmen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ECDC4),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _scan(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Aus Galerie'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),

          // Vorschau
          if (_lastImage != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(_lastImage!,
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover),
            ),
          ],

          // Status
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (_isProcessing) ...[
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF4ECDC4))),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(_status,
                    style: TextStyle(
                        color: _status.startsWith('⚠️')
                            ? const Color(0xFFFF6B6B)
                            : Colors.white60,
                        fontSize: 12)),
              ),
            ]),
          ],

          // "Alle hinzufügen"
          if (_results.isNotEmpty && newCount > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _hasUnit ? _addAllToUnit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2ECC71),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(_hasUnit
                    ? 'Alle $newCount Wörter zu „${widget.targetUnitName}" hinzufügen'
                    : 'Unit auswählen um Wörter zu speichern'),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Ergebnisliste
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  final isNew = _hasUnit ? !r.inUnit : !r.inDictionary;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isNew
                          ? const Color(0xFFFF6B35).withOpacity(0.08)
                          : Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isNew
                              ? const Color(0xFFFF6B35).withOpacity(0.3)
                              : Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(r.word,
                            style: TextStyle(
                                color:
                                    isNew ? Colors.white : Colors.white54,
                                fontSize: 14,
                                fontWeight: isNew
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ),
                      if (r.justAdded)
                        const Text('✅',
                            style: TextStyle(fontSize: 14))
                      else if (_hasUnit && r.inUnit)
                        const Text('In Unit',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 11))
                      else if (!_hasUnit && r.inDictionary)
                        const Text('Im WB',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 11))
                      else if (_hasUnit)
                        GestureDetector(
                          onTap: () => _addToUnit(r.word),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ECDC4)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFF4ECDC4)
                                      .withOpacity(0.4)),
                            ),
                            child: const Text('+ Unit',
                                style: TextStyle(
                                    color: Color(0xFF4ECDC4),
                                    fontSize: 11)),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () => _addToDict(r.word),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFFFF6B35)
                                      .withOpacity(0.4)),
                            ),
                            child: const Text('+ WB',
                                style: TextStyle(
                                    color: Color(0xFFFF6B35),
                                    fontSize: 11)),
                          ),
                        ),
                    ]),
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
  final bool inUnit;
  final bool justAdded;
  const _ScanResult({
    required this.word,
    required this.inDictionary,
    this.inUnit = false,
    this.justAdded = false,
  });
}

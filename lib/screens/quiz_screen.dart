// lib/screens/quiz_screen.dart
// Abfragebildschirm – hier werden Vokabeln abgefragt

import 'dart:math';
import 'package:flutter/material.dart';
import '../models/vocabulary.dart';
import '../services/database_service.dart';
import '../services/srs_service.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Vocabulary> _queue = [];         // Heutige Vokabeln
  int _currentIndex = 0;               // Aktuelle Position
  bool _askGermanToEnglish = true;     // Abfragerichtung
  bool _answered = false;              // Wurde bereits geantwortet?
  bool _wasCorrect = false;            // War die Antwort richtig?
  bool _isNearlyCorrect = false;       // War die Antwort fast richtig?
  String _userInput = '';              // Eingabe des Benutzers
  int _correctCount = 0;
  int _wrongCount = 0;
  bool _isLoading = true;

  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    final vocabs = await DatabaseService.getDueVocabularies(limit: 100);
    setState(() {
      _queue = vocabs;
      _isLoading = false;
      if (vocabs.isNotEmpty) _randomizeDirection();
    });
  }

  void _randomizeDirection() {
    // Zufällig DE→EN oder EN→DE
    _askGermanToEnglish = _random.nextBool();
  }

  Vocabulary get _current => _queue[_currentIndex];

  String get _question {
    return _askGermanToEnglish
        ? _current.wordDe.split('|').first // Erste deutsche Übersetzung anzeigen
        : _current.wordEn.split('|').first; // Erstes englisches Wort anzeigen
  }

  List<String> get _correctAnswers {
    return _askGermanToEnglish
        ? _current.englishVariants
        : _current.germanTranslations;
  }

  String get _directionLabel {
    return _askGermanToEnglish ? '🇩🇪 → 🇬🇧' : '🇬🇧 → 🇩🇪';
  }

  String get _inputHint {
    return _askGermanToEnglish
        ? 'Englische Übersetzung eingeben...'
        : 'Deutsche Übersetzung eingeben...';
  }

  void _checkAnswer() {
    if (_userInput.trim().isEmpty) return;

    final correct = SrsService.checkAnswer(
      userInput: _userInput,
      correctAnswers: _correctAnswers,
    );

    final nearly = !correct && SrsService.isNearlyCorrect(
      userInput: _userInput,
      correctAnswers: _correctAnswers,
    );

    setState(() {
      _answered = true;
      _wasCorrect = correct;
      _isNearlyCorrect = nearly;
    });

    // SRS aktualisieren
    _updateSrs(correct);

    // Statistiken speichern
    DatabaseService.recordDailyReview(wasCorrect: correct);

    if (correct) {
      _correctCount++;
    } else {
      _wrongCount++;
    }
  }

  Future<void> _updateSrs(bool wasCorrect) async {
    final updated = SrsService.updateAfterReview(
      vocab: _current,
      wasCorrect: wasCorrect,
    );
    await DatabaseService.updateVocabulary(updated);
  }

  void _nextCard() {
    if (_currentIndex < _queue.length - 1) {
      setState(() {
        _currentIndex++;
        _answered = false;
        _wasCorrect = false;
        _isNearlyCorrect = false;
        _userInput = '';
        _inputController.clear();
        _randomizeDirection();
      });
      _focusNode.requestFocus();
    } else {
      // Alle Vokabeln abgefragt → Ergebnis zeigen
      _showResults();
    }
  }

  void _showResults() {
    final total = _correctCount + _wrongCount;
    final percent = total > 0 ? (_correctCount / total * 100).round() : 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '🎉 Lerneinheit abgeschlossen!',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 60,
                fontWeight: FontWeight.bold,
                color: percent >= 70
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFFE74C3C),
              ),
            ),
            Text(
              '$_correctCount von $total richtig',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(
              percent >= 80
                  ? 'Ausgezeichnet! 🌟'
                  : percent >= 60
                      ? 'Gut gemacht! Weiter üben!'
                      : 'Nicht aufgeben, morgen wieder!',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Dialog schließen
              Navigator.pop(context); // Quiz-Screen schließen
            },
            child: const Text(
              'Zurück zur Übersicht',
              style: TextStyle(color: Color(0xFF4ECDC4)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4ECDC4))),
      );
    }

    if (_queue.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            'Keine fälligen Vokabeln! 🎉\nKomm morgen wieder.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${_queue.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Text('✅ $_correctCount', style: const TextStyle(color: Color(0xFF2ECC71))),
                const SizedBox(width: 10),
                Text('❌ $_wrongCount', style: const TextStyle(color: Color(0xFFE74C3C))),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Fortschrittsbalken
              LinearProgressIndicator(
                value: (_currentIndex + 1) / _queue.length,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4ECDC4)),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 30),

              // Richtungsanzeige (DE→EN oder EN→DE)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _directionLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),

              const SizedBox(height: 24),

              // Die Fragevokabel
              Expanded(
                flex: 2,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _question,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      // Beispielsatz anzeigen (nur nach Beantwortung)
                      if (_answered && _current.example != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          '📝 ${_current.example}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Ergebnisanzeige nach Beantwortung
              if (_answered) ...[
                _buildResultCard(),
                const SizedBox(height: 16),
              ],

              // Eingabefeld
              if (!_answered) ...[
                TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  autofocus: true,
                  onChanged: (v) => _userInput = v,
                  onSubmitted: (_) => _checkAnswer(),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: _inputHint,
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF4ECDC4)),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Aktionsbutton
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _answered ? _nextCard : _checkAnswer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _answered
                        ? (_wasCorrect
                            ? const Color(0xFF2ECC71)
                            : const Color(0xFFE74C3C))
                        : const Color(0xFF4ECDC4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _answered ? 'Weiter →' : 'Prüfen ✓',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Überspringen-Button
              if (!_answered)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _userInput = '';
                      _inputController.clear();
                      _answered = true;
                      _wasCorrect = false;
                    });
                    _updateSrs(false);
                    DatabaseService.recordDailyReview(wasCorrect: false);
                    _wrongCount++;
                  },
                  child: const Text(
                    'Überspringen',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _wasCorrect
            ? const Color(0xFF2ECC71).withOpacity(0.15)
            : const Color(0xFFE74C3C).withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _wasCorrect
              ? const Color(0xFF2ECC71).withOpacity(0.4)
              : const Color(0xFFE74C3C).withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _wasCorrect ? '✅ Richtig!' : '❌ Falsch!',
                style: TextStyle(
                  color: _wasCorrect ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isNearlyCorrect && !_wasCorrect)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    '(fast richtig!)',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Korrekte Antwort:',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            _correctAnswers.join(' / '),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!_wasCorrect && _userInput.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Deine Antwort: $_userInput',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

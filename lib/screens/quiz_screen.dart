// lib/screens/quiz_screen.dart
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
  List<Vocabulary> _mainQueue = [];
  List<Vocabulary> _retryQueue = [];
  bool _inRetryMode = false;

  int _currentIndex = 0;
  bool _askGermanToEnglish = true;
  bool _answered = false;
  bool _wasCorrect = false;
  bool _isNearlyCorrect = false;
  String _userInput = '';
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
    final limit = await DatabaseService.getDailyLimit();
    final vocabs = await DatabaseService.getDueVocabularies(limit: limit);
    setState(() {
      _mainQueue = vocabs;
      _inRetryMode = false;
      _isLoading = false;
      if (vocabs.isNotEmpty) _setDirection();
    });
  }

  // 2/3 DE→EN, 1/3 EN→DE
  void _setDirection() {
    _askGermanToEnglish = _random.nextInt(3) < 2; // 0,1 → DE→EN; 2 → EN→DE
  }

  Vocabulary get _current =>
      _inRetryMode ? _retryQueue[_currentIndex] : _mainQueue[_currentIndex];

  List<Vocabulary> get _activeQueue =>
      _inRetryMode ? _retryQueue : _mainQueue;

  String get _question {
    if (_askGermanToEnglish) {
      // Zeige alle deutschen Varianten als Frage
      final parts = _current.wordDe.split('|').map((s) => s.trim()).toList();
      return parts.join('\n');
    } else {
      final parts = _current.wordEn.split('|').map((s) => s.trim()).toList();
      return parts.join('\n');
    }
  }

  List<String> get _correctAnswers =>
      _askGermanToEnglish ? _current.englishVariants : _current.germanTranslations;

  // Alle akzeptierten Antworten als lesbarer String
  String get _allAnswersDisplay {
    if (_askGermanToEnglish) {
      return _current.wordEn.replaceAll('|', '   /   ');
    } else {
      return _current.wordDe.replaceAll('|', '   /   ');
    }
  }

  bool get _hasMultipleAnswers => _correctAnswers.length > 1;

  String get _directionLabel =>
      _askGermanToEnglish ? '🇩🇪 → 🇬🇧' : '🇬🇧 → 🇩🇪';

  String get _inputHint => _askGermanToEnglish
      ? 'Englische Übersetzung eingeben...'
      : 'Deutsche Übersetzung eingeben...';

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

    _updateSrs(correct);
    DatabaseService.recordDailyReview(wasCorrect: correct);

    if (correct) {
      _correctCount++;
      if (_inRetryMode) _retryQueue.removeAt(_currentIndex);
    } else {
      _wrongCount++;
      if (!_inRetryMode) {
        final alreadyIn = _retryQueue.any((v) => v.id == _current.id);
        if (!alreadyIn) _retryQueue.add(_current);
      }
    }
  }

  Future<void> _updateSrs(bool wasCorrect) async {
    final updated = SrsService.updateAfterReview(
        vocab: _current, wasCorrect: wasCorrect);
    await DatabaseService.updateVocabulary(updated);
  }

  void _nextCard() {
    if (!_answered) return;

    if (_inRetryMode) {
      if (_retryQueue.isEmpty) { _showResults(); return; }
      setState(() {
        _currentIndex = _currentIndex % _retryQueue.length;
        _resetCard();
      });
      _focusNode.requestFocus();
      return;
    }

    if (_currentIndex < _mainQueue.length - 1) {
      setState(() { _currentIndex++; _resetCard(); });
      _focusNode.requestFocus();
    } else {
      if (_retryQueue.isNotEmpty) {
        _retryQueue.shuffle();
        setState(() {
          _inRetryMode = true;
          _currentIndex = 0;
          _resetCard();
        });
        _focusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🔄 Wiederholung: ${_retryQueue.length} falsche Vokabeln'),
          backgroundColor: const Color(0xFFE74C3C),
          duration: const Duration(seconds: 3),
        ));
      } else {
        _showResults();
      }
    }
  }

  void _resetCard() {
    _answered = false;
    _wasCorrect = false;
    _isNearlyCorrect = false;
    _userInput = '';
    _inputController.clear();
    _setDirection();
  }

  void _skipCard() {
    setState(() {
      _userInput = '';
      _inputController.clear();
      _answered = true;
      _wasCorrect = false;
    });
    _updateSrs(false);
    DatabaseService.recordDailyReview(wasCorrect: false);
    _wrongCount++;
    if (!_inRetryMode) {
      final alreadyIn = _retryQueue.any((v) => v.id == _current.id);
      if (!alreadyIn) _retryQueue.add(_current);
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
        title: const Text('🎉 Lerneinheit abgeschlossen!',
            style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$percent%',
              style: TextStyle(
                fontSize: 60, fontWeight: FontWeight.bold,
                color: percent >= 70
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFFE74C3C),
              )),
          Text('$_correctCount von $total richtig',
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            percent >= 80 ? 'Ausgezeichnet! 🌟'
                : percent >= 60 ? 'Gut gemacht!'
                : 'Nicht aufgeben!',
            style: const TextStyle(color: Colors.white54)),
        ]),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text('Zurück',
                style: TextStyle(color: Color(0xFF4ECDC4))),
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
    if (_mainQueue.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white)),
        body: const Center(
          child: Text('Keine fälligen Vokabeln! 🎉\nKomm morgen wieder.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _inRetryMode
                ? '🔄 ${_currentIndex + 1}/${_retryQueue.length}'
                : '${_currentIndex + 1} / ${_mainQueue.length}',
            style: const TextStyle(color: Colors.white70, fontSize: 15)),
          if (_retryQueue.isNotEmpty && !_inRetryMode)
            Text('${_retryQueue.length} im Wiederholungstopf',
                style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 11)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Text('✅ $_correctCount',
                  style: const TextStyle(color: Color(0xFF2ECC71))),
              const SizedBox(width: 10),
              Text('❌ $_wrongCount',
                  style: const TextStyle(color: Color(0xFFE74C3C))),
            ]),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            // Fortschrittsbalken
            LinearProgressIndicator(
              value: _inRetryMode
                  ? 1.0
                  : (_currentIndex + 1) / _mainQueue.length,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                _inRetryMode
                    ? const Color(0xFFE74C3C)
                    : const Color(0xFF4ECDC4)),
              borderRadius: BorderRadius.circular(4),
            ),
            if (_inRetryMode)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Wiederholung – ${_retryQueue.length} verbleibend',
                    style: const TextStyle(
                        color: Color(0xFFE74C3C), fontSize: 12)),
              ),
            const SizedBox(height: 20),

            // Richtungsanzeige
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_directionLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
            const SizedBox(height: 20),

            // Fragevokabel
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
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                    textAlign: TextAlign.center,
                  ),
                  // Hinweis wenn mehrere Antworten möglich
                  if (!_answered && _hasMultipleAnswers) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ECDC4).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_correctAnswers.length} mögliche Übersetzungen',
                        style: const TextStyle(
                            color: Color(0xFF4ECDC4), fontSize: 12),
                      ),
                    ),
                  ],
                  if (_answered && _current.example != null) ...[
                    const SizedBox(height: 16),
                    Text('📝 ${_current.example}',
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                            fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center),
                  ],
                ]),
              ),
            ),

            if (_answered) ...[
              _buildResultCard(),
              const SizedBox(height: 14),
            ],

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
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFF4ECDC4))),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 14),
            ],

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _answered ? _nextCard : _checkAnswer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _answered
                      ? (_wasCorrect
                          ? const Color(0xFF2ECC71)
                          : const Color(0xFFE74C3C))
                      : const Color(0xFF4ECDC4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _answered ? 'Weiter →' : 'Prüfen ✓',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ),

            const SizedBox(height: 10),
            if (!_answered)
              TextButton(
                onPressed: _skipCard,
                child: const Text('Überspringen',
                    style: TextStyle(color: Colors.white38)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _wasCorrect
            ? const Color(0xFF2ECC71).withOpacity(0.12)
            : const Color(0xFFE74C3C).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _wasCorrect
              ? const Color(0xFF2ECC71).withOpacity(0.4)
              : const Color(0xFFE74C3C).withOpacity(0.4),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            _wasCorrect ? '✅ Richtig!' : '❌ Falsch!',
            style: TextStyle(
              color: _wasCorrect
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFFE74C3C),
              fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_isNearlyCorrect && !_wasCorrect)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('(fast richtig!)',
                  style: TextStyle(color: Colors.orange, fontSize: 12)),
            ),
          if (!_wasCorrect && _inRetryMode)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('→ nochmal',
                  style: TextStyle(
                      color: Color(0xFFE74C3C), fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 8),
        Text('Alle akzeptierten Antworten:',
            style: TextStyle(
                color: Colors.white.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 4),
        // Alle Alternativen einzeln anzeigen
        ..._correctAnswers.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '• $a',
            style: const TextStyle(
                color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w500),
          ),
        )),
        if (!_wasCorrect && _userInput.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Deine Antwort: $_userInput',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 13)),
        ],
      ]),
    );
  }
}

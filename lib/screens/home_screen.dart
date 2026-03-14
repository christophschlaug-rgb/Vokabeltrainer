// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/vocabulary_loader.dart';
import 'quiz_screen.dart';
import 'stats_screen.dart';
import 'dictionary_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalVocabs = 0;
  int _dueVocabs = 0;
  int _dailyLimit = 50;
  bool _isLoading = false;
  String _loadingStatus = '';
  Map<String, int> _todayStats = {};
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final total = await DatabaseService.getVocabularyCount();
    final limit = await DatabaseService.getDailyLimit();
    final due = await DatabaseService.getDueCount();
    final stats = await DatabaseService.getTodayStats();
    final streak = await DatabaseService.getLearningStreak();

    setState(() {
      _totalVocabs = total;
      _dueVocabs = due;
      _dailyLimit = limit;
      _todayStats = stats;
      _streak = streak;
    });

    if (total == 0) _loadVocabularies();
  }

  Future<void> _loadVocabularies() async {
    setState(() {
      _isLoading = true;
      _loadingStatus = 'Starte...';
    });

    await VocabularyLoader.loadAndSaveVocabularies(
      onStatus: (status) => setState(() => _loadingStatus = status),
    );

    setState(() => _isLoading = false);
    await _loadStats();
  }

  int get _effectiveDue => _dueVocabs < _dailyLimit ? _dueVocabs : _dailyLimit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VokabelTrainer',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold)),
                      Text('Englisch · Basis → C1',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 14)),
                    ],
                  ),
                  Row(
                    children: [
                      if (_streak > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF6B35).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFFFF6B35)
                                    .withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              const Text('🔥',
                                  style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text('$_streak Tage',
                                  style: const TextStyle(
                                      color: Color(0xFFFF6B35),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      // Einstellungen-Button
                      IconButton(
                        icon: const Icon(Icons.settings_outlined,
                            color: Colors.white54),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        ).then((_) => _loadStats()),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Lernkarte ────────────────────────────────────
              _buildDueCard(),

              const SizedBox(height: 16),

              // ── Statistiken ──────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: '📚',
                      label: 'Gesamt',
                      value: '$_totalVocabs',
                      color: const Color(0xFF4ECDC4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      icon: '✅',
                      label: 'Heute richtig',
                      value: '${_todayStats['correct'] ?? 0}',
                      color: const Color(0xFF2ECC71),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      icon: '❌',
                      label: 'Heute falsch',
                      value: '${_todayStats['wrong'] ?? 0}',
                      color: const Color(0xFFE74C3C),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (_isLoading)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            const Color(0xFF4ECDC4).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4ECDC4)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_loadingStatus,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              // ── Aktionsbuttons ───────────────────────────────
              Column(
                children: [
                  // Lernen starten
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _effectiveDue > 0 && !_isLoading
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const QuizScreen()),
                              ).then((_) => _loadStats())
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ECDC4),
                        disabledBackgroundColor:
                            Colors.white.withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _effectiveDue > 0
                            ? '🎓 Lernen starten ($_effectiveDue Vokabeln)'
                            : 'Heute alles gelernt! 🎉',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _effectiveDue > 0
                              ? Colors.black
                              : Colors.white38,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Wörterbuch + Statistiken
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DictionaryScreen()),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('📖 Wörterbuch'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const StatsScreen()),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('📊 Statistiken'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Aktualisieren
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _loadVocabularies,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.1)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('🔄 Vokabeln neu laden'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDueCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16213E), Color(0xFF0F3460)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Heute zu lernen',
                  style: TextStyle(color: Colors.white60, fontSize: 14)),
              Text(
                'Limit: $_dailyLimit',
                style: const TextStyle(
                    color: Color(0xFF4ECDC4), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_effectiveDue Vokabeln',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_dueVocabs > _dailyLimit)
            Text(
              '($_dueVocabs insgesamt fällig, Limit auf $_dailyLimit gesetzt)',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            )
          else if (_effectiveDue > 0)
            const Text(
              'Bereit für die heutige Lerneinheit?',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            )
          else if (_totalVocabs > 0)
            const Text(
              'Alles für heute geschafft! Morgen geht\'s weiter.',
              style: TextStyle(color: Color(0xFF4ECDC4), fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

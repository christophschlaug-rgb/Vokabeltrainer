// lib/screens/home_screen.dart
// Hauptbildschirm der App

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/vocabulary_loader.dart';
import 'quiz_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalVocabs = 0;
  int _dueVocabs = 0;
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
    final due = await DatabaseService.getDueCount();
    final stats = await DatabaseService.getTodayStats();
    final streak = await DatabaseService.getLearningStreak();

    setState(() {
      _totalVocabs = total;
      _dueVocabs = due;
      _todayStats = stats;
      _streak = streak;
    });

    // Beim ersten Start automatisch Vokabeln laden
    if (total == 0) {
      _loadVocabularies();
    }

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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VokabelTrainer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Englisch · C1-Niveau',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  // Streak-Anzeige
                  if (_streak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                          Text(
                            '$_streak Tage',
                            style: const TextStyle(
                              color: Color(0xFFFF6B35),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 30),

              // ── Lernkarte: Fällige Vokabeln ─────────────────
              _buildDueCard(),

              const SizedBox(height: 20),

              // ── Statistiken ─────────────────────────────────
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: '✅',
                      label: 'Heute richtig',
                      value: '${_todayStats['correct'] ?? 0}',
                      color: const Color(0xFF2ECC71),
                    ),
                  ),
                  const SizedBox(width: 12),
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

              const SizedBox(height: 20),

              // ── Ladefortschritt ─────────────────────────────
              if (_isLoading)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF4ECDC4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _loadingStatus,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Quelle: TU Chemnitz Wörterbuch (400.000+ Einträge)\nErster Download dauert ca. 1–2 Minuten.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              // ── Aktionsbuttons ───────────────────────────────
              Column(
                children: [
                  // Hauptbutton: Lernen starten
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _dueVocabs > 0 && !_isLoading
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const QuizScreen(),
                                ),
                              ).then((_) => _loadStats())
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ECDC4),
                        disabledBackgroundColor: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _dueVocabs > 0
                            ? '🎓 Lernen starten ($_dueVocabs fällig)'
                            : 'Heute alles gelernt! 🎉',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _dueVocabs > 0 ? Colors.black : Colors.white38,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sekundärbuttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _loadVocabularies,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('🔄 Aktualisieren'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StatsScreen(),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('📊 Statistiken'),
                        ),
                      ),
                    ],
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
          const Text(
            'Heute zu lernen',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '$_dueVocabs Vokabeln',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_dueVocabs > 0)
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

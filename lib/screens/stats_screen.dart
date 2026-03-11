// lib/screens/stats_screen.dart
// Statistikbildschirm

import 'package:flutter/material.dart';
import '../services/database_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _totalVocabs = 0;
  int _dueVocabs = 0;
  int _streak = 0;
  Map<String, int> _todayStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final total = await DatabaseService.getVocabularyCount();
    final due = await DatabaseService.getDueCount();
    final streak = await DatabaseService.getLearningStreak();
    final today = await DatabaseService.getTodayStats();

    setState(() {
      _totalVocabs = total;
      _dueVocabs = due;
      _streak = streak;
      _todayStats = today;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4ECDC4))),
      );
    }

    final reviewed = _todayStats['reviewed'] ?? 0;
    final correct = _todayStats['correct'] ?? 0;
    final wrong = _todayStats['wrong'] ?? 0;
    final percent = reviewed > 0 ? (correct / reviewed * 100).round() : 0;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Statistiken',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dein Lernfortschritt',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Streak-Card
            _buildBigCard(
              icon: '🔥',
              label: 'Lerntage in Folge',
              value: '$_streak',
              subtitle: _streak == 0
                  ? 'Heute noch nicht gelernt'
                  : _streak == 1
                      ? 'Heute gestartet – weiter so!'
                      : 'Beeindruckend!',
              color: const Color(0xFFFF6B35),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildSmallCard(
                    icon: '📚',
                    label: 'Vokabeln gesamt',
                    value: '$_totalVocabs',
                    color: const Color(0xFF4ECDC4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSmallCard(
                    icon: '⏰',
                    label: 'Heute fällig',
                    value: '$_dueVocabs',
                    color: const Color(0xFFFFD166),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Heute-Statistik
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📅 Heute',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniStat('Abgefragt', '$reviewed', Colors.white70),
                      _buildMiniStat('Richtig', '$correct', const Color(0xFF2ECC71)),
                      _buildMiniStat('Falsch', '$wrong', const Color(0xFFE74C3C)),
                      _buildMiniStat('Quote', '$percent%',
                          percent >= 70 ? const Color(0xFF2ECC71) : const Color(0xFFFFD166)),
                    ],
                  ),
                  if (reviewed > 0) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: reviewed > 0 ? correct / reviewed : 0,
                        backgroundColor: const Color(0xFFE74C3C).withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF2ECC71)),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // SRS-Erklärung
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4ECDC4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.2)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ℹ️ So funktioniert SRS',
                    style: TextStyle(
                      color: Color(0xFF4ECDC4),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Richtig → Vokabel kommt erst in 3, 7, 14 oder 30 Tagen wieder\n'
                    'Falsch → Vokabel kommt morgen wieder',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBigCard({
    required String icon,
    required String label,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallCard({
    required String icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
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

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}

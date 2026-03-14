// lib/screens/settings_screen.dart
// Einstellungen: tägliches Vokabel-Limit

import 'package:flutter/material.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _dailyLimit = 50;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final limit = await DatabaseService.getDailyLimit();
    setState(() => _dailyLimit = limit);
  }

  Future<void> _save(int value) async {
    await DatabaseService.setDailyLimit(value);
    setState(() {
      _dailyLimit = value;
      _saved = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('⚙️ Einstellungen',
            style: TextStyle(color: Colors.white, fontSize: 18)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tägliches Limit ──────────────────────────────
            Container(
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
                    '📚 Vokabeln pro Tag',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Wie viele fällige Vokabeln sollen pro Lernsitzung '
                    'abgefragt werden?',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Großer Zahlenwert
                  Center(
                    child: Text(
                      '$_dailyLimit',
                      style: const TextStyle(
                        color: Color(0xFF4ECDC4),
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Schieberegler
                  Slider(
                    value: _dailyLimit.toDouble(),
                    min: 5,
                    max: 200,
                    divisions: 39, // Schritte: 5,10,15,...,200
                    activeColor: const Color(0xFF4ECDC4),
                    inactiveColor: Colors.white12,
                    label: '$_dailyLimit Vokabeln',
                    onChanged: (v) =>
                        setState(() => _dailyLimit = v.round()),
                    onChangeEnd: (v) => _save(v.round()),
                  ),

                  // Schnellauswahl-Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [10, 25, 50, 100].map((n) {
                      final isActive = _dailyLimit == n;
                      return GestureDetector(
                        onTap: () => _save(n),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF4ECDC4).withOpacity(0.2)
                                : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFF4ECDC4)
                                  : Colors.white.withOpacity(0.15),
                            ),
                          ),
                          child: Text(
                            '$n',
                            style: TextStyle(
                              color: isActive
                                  ? const Color(0xFF4ECDC4)
                                  : Colors.white60,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Empfehlungshinweis
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF4ECDC4).withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF4ECDC4).withOpacity(0.2)),
              ),
              child: const Text(
                '💡 Empfehlung: Beginne mit 10–25 Vokabeln täglich '
                'und steigere dich langsam. Regelmäßiges Lernen '
                'ist wichtiger als viele Vokabeln auf einmal.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),

            const Spacer(),

            // Gespeichert-Bestätigung
            if (_saved)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2ECC71).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '✅ Gespeichert',
                    style: TextStyle(
                        color: Color(0xFF2ECC71),
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

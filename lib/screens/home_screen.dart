import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/vocabulary_loader.dart';
import 'quiz_screen.dart';
import 'stats_screen.dart';
import 'dictionary_screen.dart';
import 'settings_screen.dart';
import 'scan_screen.dart';
import 'units_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalVocabs = 0;
  int _dueVocabs   = 0;
  int _dailyLimit  = 50;
  int _unitCount   = 0;
  bool _isLoading  = false;
  String _loadingStatus  = '';
  bool _loadingHasError  = false;
  Map<String, int> _todayStats = {};
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final total = await DatabaseService.getVocabularyCount();
    if (total < 100) {
      await _loadVocabularies();
    } else {
      await _loadStats();
    }
  }

  Future<void> _loadStats() async {
    final total   = await DatabaseService.getVocabularyCount();
    final limit   = await DatabaseService.getDailyLimit();
    final due     = await DatabaseService.getDueCount();
    final stats   = await DatabaseService.getTodayStats();
    final streak  = await DatabaseService.getLearningStreak();
    final units   = await DatabaseService.getUnitCount();
    setState(() {
      _totalVocabs = total;
      _dueVocabs   = due;
      _dailyLimit  = limit;
      _todayStats  = stats;
      _streak      = streak;
      _unitCount   = units;
    });
  }

  Future<void> _loadVocabularies() async {
    setState(() {
      _isLoading = true;
      _loadingHasError = false;
      _loadingStatus = 'Starte...';
    });
    await VocabularyLoader.loadAndSaveVocabularies(
      onStatus: (s) {
        final hasError = s.startsWith('⚠️');
        setState(() {
          _loadingStatus   = s;
          _loadingHasError = hasError;
          if (s.startsWith('✅') || hasError) _isLoading = false;
        });
      },
    );
    if (_isLoading) setState(() => _isLoading = false);
    await _loadStats();
  }

  int get _effectiveDue =>
      _dueVocabs < _dailyLimit ? _dueVocabs : _dailyLimit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────
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
                          style: TextStyle(
                              color: Colors.white38, fontSize: 14)),
                    ],
                  ),
                  Row(children: [
                    if (_streak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFFF6B35)
                                  .withOpacity(0.5)),
                        ),
                        child: Row(children: [
                          const Text('🔥',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Text('$_streak Tage',
                              style: const TextStyle(
                                  color: Color(0xFFFF6B35),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ]),
                      ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: Colors.white54),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ).then((_) => _loadStats()),
                    ),
                  ]),
                ],
              ),

              const SizedBox(height: 18),

              // ── Heute-Kachel ──────────────────────────────────
              _buildDueCard(),

              const SizedBox(height: 14),

              // ── Stats-Kacheln ─────────────────────────────────
              Row(children: [
                Expanded(
                    child: _statCard('📚', 'Vokabeln',
                        '$_totalVocabs', const Color(0xFF4ECDC4))),
                const SizedBox(width: 10),
                Expanded(
                    child: _statCard('✅', 'Heute richtig',
                        '${_todayStats['correct'] ?? 0}',
                        const Color(0xFF2ECC71))),
                const SizedBox(width: 10),
                Expanded(
                    child: _statCard('❌', 'Heute falsch',
                        '${_todayStats['wrong'] ?? 0}',
                        const Color(0xFFE74C3C))),
              ]),

              const SizedBox(height: 14),

              // ── Units-Kachel ──────────────────────────────────
              _buildUnitsCard(),

              const SizedBox(height: 14),

              // ── Status / Fehler ───────────────────────────────
              if (_isLoading || _loadingStatus.isNotEmpty)
                _buildStatusBox(),

              if (_isLoading || _loadingStatus.isNotEmpty)
                const SizedBox(height: 14),

              // ── Hauptbutton ───────────────────────────────────
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
                        borderRadius: BorderRadius.circular(16)),
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

              // ── Sekundär-Buttons ──────────────────────────────
              Row(children: [
                Expanded(child: _outlineBtn('📖 Wörterbuch', () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DictionaryScreen()));
                })),
                const SizedBox(width: 10),
                Expanded(child: _outlineBtn('📊 Statistiken', () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StatsScreen()));
                })),
              ]),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: _outlineBtn('📷 Buchseite scannen', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ScanScreen()),
                  ).then((_) => _loadStats());
                }),
              ),

              const SizedBox(height: 6),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _loadVocabularies,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _loadingHasError
                        ? const Color(0xFFFF6B35)
                        : Colors.white38,
                    side: BorderSide(
                        color: _loadingHasError
                            ? const Color(0xFFFF6B35).withOpacity(0.5)
                            : Colors.white.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_loadingHasError
                      ? '🔄 Download erneut versuchen'
                      : '🔄 Vokabeln neu laden'),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDueCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16213E), Color(0xFF0F3460)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Heute zu lernen',
              style: TextStyle(color: Colors.white60, fontSize: 14)),
          Text('Limit: $_dailyLimit',
              style: const TextStyle(
                  color: Color(0xFF4ECDC4), fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        Text('$_effectiveDue Vokabeln',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold)),
        if (_dueVocabs > _dailyLimit)
          Text('($_dueVocabs fällig, Limit $_dailyLimit)',
              style: const TextStyle(color: Colors.white38, fontSize: 12))
        else if (_effectiveDue > 0)
          const Text('Bereit für heute?',
              style: TextStyle(color: Colors.white54, fontSize: 13))
        else if (_totalVocabs > 0)
          const Text('Alles für heute geschafft! 🎉',
              style: TextStyle(color: Color(0xFF4ECDC4), fontSize: 13)),
      ]),
    );
  }

  Widget _buildUnitsCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UnitsScreen()),
      ).then((_) => _loadStats()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF4ECDC4).withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF4ECDC4).withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
                child: Text('📚', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Meine Units',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              Text(
                _unitCount == 0
                    ? 'Buchseiten scannen und Wörter sammeln'
                    : '$_unitCount Unit${_unitCount == 1 ? '' : 's'} · Tippe zum Öffnen',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12),
              ),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios,
              color: Colors.white24, size: 16),
        ]),
      ),
    );
  }

  Widget _buildStatusBox() {
    final isError = _loadingHasError;
    final color =
        isError ? const Color(0xFFE74C3C) : const Color(0xFF4ECDC4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 10, top: 2),
            child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color)),
          ),
        Expanded(
          child: Text(_loadingStatus,
              style: TextStyle(
                  color: isError
                      ? const Color(0xFFFF6B6B)
                      : Colors.white70,
                  fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _statCard(String icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _outlineBtn(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }
}

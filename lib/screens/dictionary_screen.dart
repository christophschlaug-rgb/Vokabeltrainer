// lib/screens/dictionary_screen.dart
// Wörterbuch-Ansicht mit Suchfunktion

import 'package:flutter/material.dart';
import '../models/vocabulary.dart';
import '../services/database_service.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  List<Vocabulary> _results = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final all = await DatabaseService.getAllVocabulariesSorted();
    setState(() {
      _results = all;
      _isLoading = false;
    });
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;

    if (q.isEmpty) {
      _loadAll();
      return;
    }

    setState(() => _isSearching = true);
    final found = await DatabaseService.searchVocabularies(q);
    setState(() {
      _results = found;
      _isSearching = false;
    });
  }

  String _statusLabel(Vocabulary v) {
    if (v.totalCorrect == 0 && v.totalWrong == 0) return 'Neu';
    if (v.successStreak >= 6) return '⭐ Gelernt';
    if (v.successStreak >= 3) return '📈 Fortschritt';
    return '🔁 Üben';
  }

  Color _statusColor(Vocabulary v) {
    if (v.totalCorrect == 0 && v.totalWrong == 0) return Colors.white30;
    if (v.successStreak >= 6) return const Color(0xFF2ECC71);
    if (v.successStreak >= 3) return const Color(0xFF4ECDC4);
    return const Color(0xFFFF6B35);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('📖 Wörterbuch',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Englisch oder Deutsch suchen...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF4ECDC4)),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading || _isSearching
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4ECDC4)))
          : _results.isEmpty
              ? const Center(
                  child: Text('Keine Treffer.',
                      style: TextStyle(color: Colors.white54, fontSize: 16)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          Text(
                            '${_results.length} Einträge'
                            '${_lastQuery.isNotEmpty ? ' für „$_lastQuery"' : ''}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final v = _results[i];
                          final enWords = v.wordEn.replaceAll('|', ' / ');
                          final deWords = v.wordDe.replaceAll('|', ' / ');
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.07)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              title: Text(
                                enWords,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                deWords,
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 13),
                              ),
                              trailing: Text(
                                _statusLabel(v),
                                style: TextStyle(
                                    color: _statusColor(v), fontSize: 11),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

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
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _lastQuery = '';
  int _offset = 0;
  static const _pageSize = 100;

  final Set<int> _selected = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMorePages();
    }
  }

  Future<void> _loadPage() async {
    setState(() { _isLoading = true; _offset = 0; _hasMore = true; });
    final page = await DatabaseService.getVocabulariesPaged(
        offset: 0, limit: _pageSize, query: '');
    setState(() {
      _results = page;
      _isLoading = false;
      _hasMore = page.length == _pageSize;
      _offset = page.length;
    });
  }

  Future<void> _loadMorePages() async {
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final page = await DatabaseService.getVocabulariesPaged(
        offset: _offset, limit: _pageSize, query: _lastQuery);
    setState(() {
      _results.addAll(page);
      _offset += page.length;
      _hasMore = page.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;

    if (query.isEmpty) {
      _loadPage();
      return;
    }

    setState(() { _isSearching = true; _results = []; _offset = 0; _hasMore = false; });
    // Suche: alle Treffer auf einmal laden (kein Paginierungs-Limit)
    final found = await DatabaseService.getVocabulariesPaged(
        offset: 0, limit: 0, query: query);
    setState(() {
      _results = found;
      _offset = found.length;
      _hasMore = false; // Bei Suche kein weiteres Nachladen nötig
      _isSearching = false;
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
        _selectionMode = true;
      }
    });
  }

  Future<void> _deleteSingle(Vocabulary v) async {
    FocusScope.of(context).unfocus();
    final confirm = await _confirmDelete(
        '„${v.wordEn}" löschen?', 'Diese Vokabel wird dauerhaft entfernt.');
    if (!confirm) return;
    await DatabaseService.deleteVocabulary(v.id!);
    setState(() => _results.remove(v));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('„${v.wordEn}" gelöscht'),
        backgroundColor: const Color(0xFF2ECC71),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _deleteSelected() async {
    FocusScope.of(context).unfocus();
    final n = _selected.length;
    final confirm = await _confirmDelete(
        '$n Vokabeln löschen?', 'Diese Vokabeln werden dauerhaft entfernt.');
    if (!confirm) return;
    await DatabaseService.deleteVocabularies(_selected.toList());
    setState(() {
      _results.removeWhere((v) => _selected.contains(v.id));
      _selected.clear();
      _selectionMode = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$n Vokabeln gelöscht'),
        backgroundColor: const Color(0xFF2ECC71),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<bool> _confirmDelete(String title, String subtitle) async =>
      await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF16213E),
              title: Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 17)),
              content: Text(subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Abbrechen',
                        style: TextStyle(color: Colors.white54))),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Löschen',
                        style: TextStyle(
                            color: Color(0xFFE74C3C),
                            fontWeight: FontWeight.bold))),
              ],
            ),
          ) ??
      false;

  String _statusLabel(Vocabulary v) {
    if (v.totalCorrect == 0 && v.totalWrong == 0) return 'Neu';
    if (v.successStreak >= 6) return '⭐';
    if (v.successStreak >= 3) return '📈';
    return '🔁';
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
        title: _selectionMode
            ? Text('${_selected.length} ausgewählt',
                style: const TextStyle(color: Colors.white, fontSize: 17))
            : const Text('📖 Wörterbuch',
                style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white70),
              onPressed: () =>
                  setState(() => _selected.addAll(_results.map((v) => v.id!))),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFE74C3C)),
              onPressed: _deleteSelected,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () =>
                  setState(() { _selected.clear(); _selectionMode = false; }),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  _lastQuery.isEmpty
                      ? '${_results.length}+ Einträge'
                      : '${_results.length} Treffer (alle durchsucht)',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Englisch oder Deutsch suchen...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
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
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF4ECDC4))),
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
              ? Center(
                  child: Text(
                    _lastQuery.isEmpty
                        ? 'Keine Vokabeln vorhanden.'
                        : 'Keine Treffer für „$_lastQuery".',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 15),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _results.length + (_isLoadingMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _results.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF4ECDC4), strokeWidth: 2),
                        ),
                      );
                    }
                    final v = _results[i];
                    final isSelected = _selected.contains(v.id);
                    return Dismissible(
                      key: Key('v_${v.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: const Color(0xFFE74C3C),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline,
                                color: Colors.white, size: 26),
                            Text('Löschen',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                      confirmDismiss: (_) async {
                        FocusScope.of(context).unfocus();
                        return _confirmDelete(
                          '„${v.wordEn}" löschen?',
                          'Diese Vokabel wird dauerhaft entfernt.',
                        );
                      },
                      onDismissed: (_) async {
                        await DatabaseService.deleteVocabulary(v.id!);
                        setState(() => _results.removeAt(i));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('„${v.wordEn}" gelöscht'),
                            backgroundColor: const Color(0xFF2ECC71),
                            duration: const Duration(seconds: 2),
                          ));
                        }
                      },
                      child: GestureDetector(
                        onLongPress: () => _toggleSelect(v.id!),
                        onTap: _selectionMode
                            ? () => _toggleSelect(v.id!)
                            : null,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFE74C3C).withOpacity(0.15)
                                : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFE74C3C).withOpacity(0.5)
                                  : Colors.white.withOpacity(0.07),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 2),
                            leading: _selectionMode
                                ? Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: isSelected
                                        ? const Color(0xFFE74C3C)
                                        : Colors.white30,
                                  )
                                : null,
                            title: Text(
                              v.wordEn.replaceAll('|', ' / '),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              v.wordDe.replaceAll('|', ' / '),
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 13),
                            ),
                            trailing: _selectionMode
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_statusLabel(v),
                                          style: TextStyle(
                                              color: _statusColor(v),
                                              fontSize: 13)),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => _deleteSingle(v),
                                        child: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.white24,
                                            size: 20),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

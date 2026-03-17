// lib/screens/units_screen.dart
// Wortlisten aus Buchseiten ("Units")

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'scan_screen.dart';

class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});
  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  List<Map<String, dynamic>> _units = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final units = await DatabaseService.getAllUnits();
    setState(() { _units = units; _isLoading = false; });
  }

  Future<void> _createUnit() async {
    final name = await _askName('Neue Unit', 'z.B. Unit 1, Kapitel 3...');
    if (name == null || name.trim().isEmpty) return;
    final id = await DatabaseService.createUnit(name.trim());
    await _load();
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UnitDetailScreen(unitId: id, unitName: name.trim()),
        ),
      ).then((_) => _load());
    }
  }

  Future<void> _renameUnit(Map<String, dynamic> unit) async {
    final name = await _askName('Umbenennen', unit['name'] as String,
        initial: unit['name'] as String);
    if (name == null || name.trim().isEmpty) return;
    await DatabaseService.renameUnit(unit['id'] as int, name.trim());
    await _load();
  }

  Future<void> _deleteUnit(Map<String, dynamic> unit) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: Text('„${unit['name']}" löschen?',
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
            '${unit['word_count']} Wörter werden gelöscht.',
            style: const TextStyle(color: Colors.white60)),
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
    ) ?? false;
    if (!confirm) return;
    await DatabaseService.deleteUnit(unit['id'] as int);
    await _load();
  }

  Future<String?> _askName(String title, String hint,
      {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen',
                  style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('OK',
                  style: TextStyle(color: Color(0xFF4ECDC4),
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('📚 Meine Units',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF4ECDC4)),
            tooltip: 'Neue Unit',
            onPressed: _createUnit,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4ECDC4)))
          : _units.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('📚',
                          style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      const Text('Noch keine Units vorhanden.',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                          'Erstelle eine Unit und scanne\nBuchseiten hinein.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white30, fontSize: 13)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _createUnit,
                        icon: const Icon(Icons.add),
                        label: const Text('Erste Unit erstellen'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4ECDC4),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _units.length,
                  itemBuilder: (ctx, i) {
                    final u = _units[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UnitDetailScreen(
                              unitId: u['id'] as int,
                              unitName: u['name'] as String,
                            ),
                          ),
                        ).then((_) => _load()),
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF4ECDC4).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text('📖',
                                style: TextStyle(fontSize: 22)),
                          ),
                        ),
                        title: Text(u['name'] as String,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${u['word_count']} Wörter · '
                          '${_formatDate(u['created_at'] as String)}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white38),
                          color: const Color(0xFF16213E),
                          onSelected: (val) {
                            if (val == 'rename') _renameUnit(u);
                            if (val == 'scan') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ScanScreen(
                                      targetUnitId: u['id'] as int,
                                      targetUnitName: u['name'] as String),
                                ),
                              ).then((_) => _load());
                            }
                            if (val == 'delete') _deleteUnit(u);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'scan',
                                child: Row(children: [
                                  Icon(Icons.camera_alt_outlined,
                                      color: Color(0xFF4ECDC4), size: 18),
                                  SizedBox(width: 8),
                                  Text('Seite scannen',
                                      style: TextStyle(
                                          color: Colors.white)),
                                ])),
                            const PopupMenuItem(
                                value: 'rename',
                                child: Row(children: [
                                  Icon(Icons.edit_outlined,
                                      color: Colors.white54, size: 18),
                                  SizedBox(width: 8),
                                  Text('Umbenennen',
                                      style: TextStyle(
                                          color: Colors.white)),
                                ])),
                            const PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_outline,
                                      color: Color(0xFFE74C3C), size: 18),
                                  SizedBox(width: 8),
                                  Text('Löschen',
                                      style: TextStyle(
                                          color: Color(0xFFE74C3C))),
                                ])),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _units.isNotEmpty
          ? FloatingActionButton(
              onPressed: _createUnit,
              backgroundColor: const Color(0xFF4ECDC4),
              foregroundColor: Colors.black,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    } catch (_) {
      return '';
    }
  }
}

// ─── Unit-Detail-Screen ────────────────────────────────────────────────────

class UnitDetailScreen extends StatefulWidget {
  final int unitId;
  final String unitName;
  const UnitDetailScreen(
      {super.key, required this.unitId, required this.unitName});
  @override
  State<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends State<UnitDetailScreen> {
  List<String> _words = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final words = await DatabaseService.getUnitWords(widget.unitId);
    setState(() { _words = words; _isLoading = false; });
  }

  Future<void> _removeWord(String word) async {
    await DatabaseService.removeWordFromUnit(widget.unitId, word);
    setState(() => _words.remove(word));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.unitName,
              style: const TextStyle(color: Colors.white, fontSize: 17)),
          Text('${_words.length} Wörter',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined,
                color: Color(0xFF4ECDC4)),
            tooltip: 'Seite scannen',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ScanScreen(
                    targetUnitId: widget.unitId,
                    targetUnitName: widget.unitName),
              ),
            ).then((_) => _load()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4ECDC4)))
          : _words.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('📷',
                          style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      const Text('Noch keine Wörter.',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 15)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ScanScreen(
                                targetUnitId: widget.unitId,
                                targetUnitName: widget.unitName),
                          ),
                        ).then((_) => _load()),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Buchseite scannen'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4ECDC4),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _words.length,
                  itemBuilder: (ctx, i) {
                    final w = _words[i];
                    return Dismissible(
                      key: Key('uw_$w'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: const Color(0xFFE74C3C),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white),
                      ),
                      onDismissed: (_) => _removeWord(w),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.07)),
                        ),
                        child: Text(w,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15)),
                      ),
                    );
                  },
                ),
    );
  }
}

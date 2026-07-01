import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/db/history_db.dart';
import '../../models/history_item.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryItem> _items = [];
  List<HistoryItem> _filtered = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _applyFilter();
      });
    });
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filtered = List.from(_items);
    } else {
      _filtered = _items
          .where((e) =>
              e.fileName.toLowerCase().contains(_searchQuery) ||
              e.peerName.toLowerCase().contains(_searchQuery))
          .toList();
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final items = await HistoryDB.instance.getAllItems();
    setState(() {
      _items = items;
      _isLoading = false;
      _applyFilter();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteItem(String id) async {
    await HistoryDB.instance.deleteItem(id);
    _loadHistory();
  }

  Future<void> _clearAll() async {
    await HistoryDB.instance.clearHistory();
    _searchController.clear();
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Historique', style: GoogleFonts.plusJakartaSans()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher dans l\'historique...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withAlpha(150),
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.onSurface.withAlpha(8),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary.withAlpha(120),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _items.isEmpty
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Effacer l\'historique'),
                        content: const Text('Êtes-vous sûr de vouloir tout effacer ?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _clearAll();
                            },
                            child: const Text('Effacer', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isNotEmpty ? Icons.search_off : Icons.history,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withAlpha(100),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Aucun résultat pour "$_searchQuery"'
                            : 'Aucun historique',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final item = _filtered[index];
                    final date = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
                    final isReceive = item.type == 'receive';
                    final ext = item.fileName.split('.').last.toLowerCase();
                    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: isImage && item.filePath.isNotEmpty
                                ? Image.file(
                                    File(item.filePath),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(Icons.image, color: colorScheme.primary),
                                  )
                                : Icon(
                                    isReceive ? Icons.download : Icons.upload,
                                    color: colorScheme.primary,
                                  ),
                          ),
                        ),
                        title: Text(
                          item.fileName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${isReceive ? 'Reçu de' : 'Envoyé à'} ${item.peerName}',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withAlpha(150)),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _deleteItem(item.id),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

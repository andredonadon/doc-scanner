import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/document.dart';
import '../services/scan_flow.dart';
import '../widgets/dialogs.dart';
import 'document_screen.dart';

/// Home screen: all scanned documents, searchable by title and page text.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  late Future<List<ScanDocument>> _documents;

  @override
  void initState() {
    super.initState();
    _reload();
    storage.addListener(_reload);
  }

  @override
  void dispose() {
    storage.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _documents = storage.documents(query: _search.text.trim()));
  }

  Future<void> _scan() async {
    final doc = await scanPages(context);
    if (doc != null && mounted) _open(doc);
  }

  void _open(ScanDocument doc) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => DocumentScreen(document: doc)));
  }

  Future<void> _rename(ScanDocument doc) async {
    final title = await promptText(context, title: 'Rename', initial: doc.title);
    if (title != null && title.isNotEmpty) await storage.renameDocument(doc.id, title);
  }

  Future<void> _delete(ScanDocument doc) async {
    if (await confirm(context,
        title: 'Delete document?', message: '"${doc.title}" and all its pages will be removed.')) {
      await storage.deleteDocument(doc.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Search titles and text…', border: InputBorder.none),
                onChanged: (_) => _reload(),
              )
            : const Text('Documents'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                _reload();
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<ScanDocument>>(
        future: _documents,
        builder: (context, snapshot) {
          final docs = snapshot.data;
          if (docs == null) return const Center(child: CircularProgressIndicator());
          if (docs.isEmpty) {
            return _EmptyState(searching: _search.text.isNotEmpty);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
            itemBuilder: (context, i) => _DocumentTile(
              document: docs[i],
              onTap: () => _open(docs[i]),
              onRename: () => _rename(docs[i]),
              onDelete: () => _delete(docs[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ScanDocument document;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = document.coverPath;
    final d = document.updatedAt;
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: onTap,
      leading: SizedBox(
        width: 56,
        height: 72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: cover == null
              ? ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.description_outlined))
              : Image.file(File(cover), fit: BoxFit.cover, cacheWidth: 168),
        ),
      ),
      title: Text(document.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'} · $date'),
      trailing: PopupMenuButton<VoidCallback>(
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          PopupMenuItem(value: onRename, child: const Text('Rename')),
          PopupMenuItem(value: onDelete, child: const Text('Delete')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off : Icons.document_scanner_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(searching ? 'No matching documents' : 'No documents yet',
                style: theme.textTheme.titleMedium),
            if (!searching) ...[
              const SizedBox(height: 8),
              Text('Tap Scan to photograph a document or import images.',
                  textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

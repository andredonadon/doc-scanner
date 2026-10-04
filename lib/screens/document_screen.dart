import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/document.dart';
import '../services/export.dart';
import '../services/scan_flow.dart';
import '../widgets/dialogs.dart';
import 'page_screen.dart';

/// One document: its pages in order, with export and editing actions.
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.document});
  final ScanDocument document;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  ScanDocument get _doc => widget.document;
  List<ScanPage>? _pages;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
    ocr.addListener(_onOcrChanged);
  }

  @override
  void dispose() {
    ocr.removeListener(_onOcrChanged);
    super.dispose();
  }

  void _onOcrChanged() => _load();

  Future<void> _load() async {
    final pages = await storage.pages(_doc.id);
    if (mounted) setState(() => _pages = pages);
  }

  Future<void> _addPages() async {
    await scanPages(context, document: _doc);
    await _load();
  }

  Future<void> _openPage(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PageScreen(document: _doc, initialIndex: index)),
    );
    await _load();
  }

  Future<void> _rename() async {
    final title = await promptText(context, title: 'Rename', initial: _doc.title);
    if (title == null || title.isEmpty) return;
    await storage.renameDocument(_doc.id, title);
    setState(() => _doc.title = title);
  }

  Future<void> _delete() async {
    if (!await confirm(context,
        title: 'Delete document?', message: '"${_doc.title}" and all its pages will be removed.')) {
      return;
    }
    await storage.deleteDocument(_doc.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _export(Future<void> Function() action) async {
    setState(() => _exporting = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    final pages = _pages!;
    setState(() => pages.insert(newIndex, pages.removeAt(oldIndex)));
    storage.reorderPages(_doc.id, pages);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final hasPages = pages != null && pages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onTap: _rename, child: Text(_doc.title)),
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: !hasPages || _exporting
                ? null
                : () => _export(() => Exporter.sharePdf(_doc, pages)),
          ),
          PopupMenuButton<VoidCallback>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(value: _rename, child: const Text('Rename')),
              if (hasPages)
                PopupMenuItem(
                  value: () => _export(() => Exporter.shareImages(_doc, pages)),
                  child: const Text('Share as images'),
                ),
              if (hasPages)
                PopupMenuItem(
                  value: () => _export(() => Exporter.shareText(
                      _doc.title, pages.map((p) => p.ocrText ?? '').join('\n\n'))),
                  child: const Text('Share text'),
                ),
              PopupMenuItem(value: _delete, child: const Text('Delete')),
            ],
          ),
        ],
        bottom: _exporting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
            : null,
      ),
      body: pages == null
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              itemCount: pages.length,
              onReorderItem: _onReorder,
              itemBuilder: (context, i) => _PageTile(
                key: ValueKey(pages[i].id),
                page: pages[i],
                number: i + 1,
                ocrPending: ocr.isPending(pages[i].id),
                onTap: () => _openPage(i),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPages,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add pages'),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.page,
    required this.number,
    required this.ocrPending,
    required this.onTap,
  });

  final ScanPage page;
  final int number;
  final bool ocrPending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = page.ocrText;
    final String status;
    if (ocrPending) {
      status = 'Recognizing text…';
    } else if (text == null) {
      status = 'No text recognized yet';
    } else if (text.isEmpty) {
      status = 'No text found';
    } else {
      status = text.replaceAll(RegExp(r'\s+'), ' ');
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 90,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(File(page.imagePath), fit: BoxFit.cover, cacheWidth: 270),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Page $number', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(status,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 24), // room for the drag handle
          ],
        ),
      ),
    );
  }
}

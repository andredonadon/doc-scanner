import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/document.dart';
import '../services/export.dart';
import '../services/scan_flow.dart';
import '../widgets/dialogs.dart';

/// Full-screen, swipeable view of a document's pages.
class PageScreen extends StatefulWidget {
  const PageScreen({super.key, required this.document, required this.initialIndex});
  final ScanDocument document;
  final int initialIndex;

  @override
  State<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends State<PageScreen> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  List<ScanPage>? _pages;

  @override
  void initState() {
    super.initState();
    _load();
    ocr.addListener(_onOcrChanged);
  }

  @override
  void dispose() {
    ocr.removeListener(_onOcrChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onOcrChanged() => _load();

  Future<void> _load() async {
    final pages = await storage.pages(widget.document.id);
    if (!mounted) return;
    if (pages.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _pages = pages;
      _index = _index.clamp(0, pages.length - 1);
    });
  }

  ScanPage get _page => _pages![_index];

  Future<void> _edit() async {
    if (await editPage(context, _page)) setState(() {});
  }

  Future<void> _delete() async {
    if (!await confirm(context,
        title: 'Delete page?', message: 'Page ${_index + 1} will be removed.')) {
      return;
    }
    await storage.deletePage(_page);
    await _load();
  }

  void _showText() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OcrSheet(pageId: _page.id, title: widget.document.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(pages == null ? '' : 'Page ${_index + 1} of ${pages.length}'),
      ),
      body: pages == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.file(File(pages[i].imagePath),
                      key: ValueKey(pages[i].imagePath), cacheWidth: 2000),
                ),
              ),
            ),
      bottomNavigationBar: pages == null
          ? null
          : BottomAppBar(
              color: Colors.black,
              child: IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Action(icon: Icons.crop_rotate, label: 'Edit', onPressed: _edit),
                    _Action(
                      icon: Icons.text_snippet_outlined,
                      label: ocr.isPending(_page.id) ? 'Reading…' : 'Text',
                      onPressed: _showText,
                    ),
                    _Action(icon: Icons.delete_outline, label: 'Delete', onPressed: _delete),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Shows a page's recognized text, with copy/share and a re-run option.
class _OcrSheet extends StatefulWidget {
  const _OcrSheet({required this.pageId, required this.title});
  final int pageId;
  final String title;

  @override
  State<_OcrSheet> createState() => _OcrSheetState();
}

class _OcrSheetState extends State<_OcrSheet> {
  ScanPage? _page;

  @override
  void initState() {
    super.initState();
    _changed();
    ocr.addListener(_changed);
  }

  @override
  void dispose() {
    ocr.removeListener(_changed);
    super.dispose();
  }

  Future<void> _changed() async {
    final page = await storage.page(widget.pageId);
    if (mounted) setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final text = page?.ocrText;
    final pending = ocr.isPending(widget.pageId);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const SizedBox(width: 8),
                Text('Recognized text', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Run OCR again',
                  icon: const Icon(Icons.refresh),
                  onPressed: pending || page == null ? null : () => ocr.enqueue([page]),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: text == null || text.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied to clipboard')));
                        },
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share),
                  onPressed: text == null || text.isEmpty
                      ? null
                      : () => Exporter.shareText(widget.title, text),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: pending
                  ? const Center(child: CircularProgressIndicator())
                  : text == null || text.isEmpty
                      ? const Center(child: Text('No text found on this page.'))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(text),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

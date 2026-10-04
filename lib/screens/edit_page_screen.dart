import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/scanner.dart';
import '../widgets/corner_editor.dart';

/// Result of editing a page: the processed image is at [imagePath] (a
/// temporary file the caller should move or copy).
class EditResult {
  const EditResult(this.imagePath, this.corners, this.filter);
  final String imagePath;
  final List<(double, double)> corners;
  final ScanFilter filter;
}

/// Two-step editor: adjust the document corners, then choose a filter.
class EditPageScreen extends StatefulWidget {
  const EditPageScreen({
    super.key,
    required this.originalPath,
    this.initialCorners,
    this.initialFilter = ScanFilter.enhanced,
    this.title = 'Adjust',
  });

  final String originalPath;

  /// Corners from a previous edit; when null they are auto-detected.
  final List<(double, double)>? initialCorners;
  final ScanFilter initialFilter;
  final String title;

  @override
  State<EditPageScreen> createState() => _EditPageScreenState();
}

class _EditPageScreenState extends State<EditPageScreen> {
  Size? _imageSize;
  late List<(double, double)> _corners;
  bool _detected = false;
  late ScanFilter _filter = widget.initialFilter;
  bool _cropping = true;
  bool _busy = false;
  final _previews = <ScanFilter, String>{};

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    for (final path in _previews.values) {
      File(path).delete().ignore();
    }
    super.dispose();
  }

  Future<void> _detect() async {
    final DetectionResult result;
    try {
      result = await Scanner.detect(widget.originalPath);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This image format is not supported.')));
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    setState(() {
      _imageSize = Size(result.width.toDouble(), result.height.toDouble());
      _corners = widget.initialCorners ?? result.corners;
      _detected = widget.initialCorners != null || result.found;
    });
  }

  Future<void> _showFilter(ScanFilter filter) async {
    setState(() {
      _filter = filter;
      _busy = true;
    });
    if (!_previews.containsKey(filter)) {
      final dir = await getTemporaryDirectory();
      final out = p.join(dir.path,
          'preview_${filter.name}_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await Scanner.process(widget.originalPath, out, _corners, filter);
      _previews[filter] = out;
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toFilterStep() {
    // Corners may have changed, so earlier previews are stale.
    for (final path in _previews.values) {
      File(path).delete().ignore();
    }
    _previews.clear();
    setState(() => _cropping = false);
    _showFilter(_filter);
  }

  void _save() {
    final path = _previews.remove(_filter)!;
    Navigator.pop(context, EditResult(path, _corners, _filter));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: _cropping
            ? null
            : BackButton(onPressed: () => setState(() => _cropping = true)),
      ),
      body: _imageSize == null
          ? const Center(child: CircularProgressIndicator())
          : _cropping
              ? _buildCropStep()
              : _buildFilterStep(),
    );
  }

  Widget _buildCropStep() {
    return Column(
      children: [
        if (!_detected)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No document edges found — drag the corners to adjust.',
                style: TextStyle(color: Colors.white70)),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: CornerEditor(
              imagePath: widget.originalPath,
              imageSize: _imageSize!,
              corners: _corners,
              onChanged: (c) => setState(() => _corners = c),
            ),
          ),
        ),
        _BottomBar(children: [
          TextButton.icon(
            onPressed: () => setState(
                () => _corners = const [(0, 0), (1, 0), (1, 1), (0, 1)]),
            icon: const Icon(Icons.fullscreen),
            label: const Text('Full page'),
          ),
          FilledButton.icon(
            onPressed: _toFilterStep,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next'),
          ),
        ]),
      ],
    );
  }

  Widget _buildFilterStep() {
    final preview = _previews[_filter];
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: preview == null
                  ? const CircularProgressIndicator()
                  : Stack(alignment: Alignment.center, children: [
                      Image.file(File(preview), cacheWidth: 1600, gaplessPlayback: true),
                      if (_busy) const CircularProgressIndicator(),
                    ]),
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in ScanFilter.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: f == _filter,
                    onSelected: _busy ? null : (_) => _showFilter(f),
                  ),
                ),
            ],
          ),
        ),
        _BottomBar(children: [
          TextButton.icon(
            onPressed: () => setState(() => _cropping = true),
            icon: const Icon(Icons.crop),
            label: const Text('Crop'),
          ),
          FilledButton.icon(
            onPressed: _busy || preview == null ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ]),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: children,
        ),
      ),
    );
  }
}

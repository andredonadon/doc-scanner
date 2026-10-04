import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/document.dart';
import '../screens/capture_screen.dart';
import '../screens/edit_page_screen.dart';
import 'scanner.dart';

/// Captures photos, lets the user adjust each one, and saves the results as
/// pages of [document] (or of a new document when null). Returns the document
/// the pages were added to, or null if nothing was saved.
Future<ScanDocument?> scanPages(BuildContext context, {ScanDocument? document}) async {
  final shots = await Navigator.push<List<String>>(
      context, MaterialPageRoute(builder: (_) => const CaptureScreen()));
  if (shots == null || shots.isEmpty || !context.mounted) return null;

  final createdHere = document == null;
  final doc = document ?? await storage.createDocument(_defaultTitle());
  var filter = ScanFilter.enhanced;
  final added = <ScanPage>[];

  for (var i = 0; i < shots.length; i++) {
    final original = await storage.newImagePath(doc.id, 'orig');
    await File(shots[i]).copy(original);
    if (!context.mounted) break;
    final result = await Navigator.push<EditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => EditPageScreen(
          originalPath: original,
          initialFilter: filter,
          title: shots.length > 1 ? 'Page ${i + 1} of ${shots.length}' : 'Adjust',
        ),
      ),
    );
    if (result == null) {
      await File(original).delete();
      continue;
    }
    filter = result.filter; // Reuse the last choice for the next page.
    final processed = await storage.newImagePath(doc.id, 'page');
    await _move(result.imagePath, processed);
    added.add(await storage.addPage(
      documentId: doc.id,
      imagePath: processed,
      originalPath: original,
      corners: result.corners,
      filter: result.filter,
    ));
  }

  if (added.isEmpty) {
    if (createdHere) await storage.deleteDocument(doc.id);
    return null;
  }
  ocr.enqueue(added);
  return doc;
}

/// Re-opens the editor for an existing page and saves the new crop/filter.
Future<bool> editPage(BuildContext context, ScanPage page) async {
  final result = await Navigator.push<EditResult>(
    context,
    MaterialPageRoute(
      builder: (_) => EditPageScreen(
        originalPath: page.originalPath,
        initialCorners: page.corners,
        initialFilter: page.filter,
      ),
    ),
  );
  if (result == null) return false;
  final processed = await storage.newImagePath(page.documentId, 'page');
  await _move(result.imagePath, processed);
  await storage.updatePageImage(page, processed, result.corners, result.filter);
  ocr.enqueue([page]);
  return true;
}

Future<void> _move(String from, String to) async {
  await File(from).copy(to);
  await File(from).delete();
}

String _defaultTitle() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Scan ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}.${two(now.minute)}';
}

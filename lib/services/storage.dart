import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/document.dart';
import 'scanner.dart';

/// Persists documents and pages. Metadata lives in SQLite; images live under
/// `<app documents>/scans/<documentId>/`. Paths are stored relative to the app
/// documents directory so they survive app-container moves.
class Storage extends ChangeNotifier {
  Storage._(this._db, this._root);

  final Database _db;
  final String _root;

  static Future<Storage> open() async {
    final root = (await getApplicationDocumentsDirectory()).path;
    final db = await openDatabase(
      p.join(root, 'scans.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE pages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            original_path TEXT NOT NULL,
            corners TEXT NOT NULL,
            filter TEXT NOT NULL,
            ocr_text TEXT
          )''');
        await db.execute('CREATE INDEX pages_doc ON pages(document_id, position)');
      },
    );
    return Storage._(db, root);
  }

  String _abs(String rel) => p.join(_root, rel);
  String _rel(String abs) => p.relative(abs, from: _root);

  /// Directory where a document's images are stored.
  Future<Directory> documentDir(int documentId) =>
      Directory(p.join(_root, 'scans', '$documentId')).create(recursive: true);

  /// A fresh, unique file path inside a document's directory.
  Future<String> newImagePath(int documentId, String prefix) async {
    final dir = await documentDir(documentId);
    return p.join(dir.path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}.jpg');
  }

  /// Lists documents, newest first. A non-empty [query] matches the title or
  /// any page's recognized text.
  Future<List<ScanDocument>> documents({String query = ''}) async {
    final where = query.isEmpty
        ? ''
        : '''WHERE d.title LIKE ?1 OR EXISTS (
               SELECT 1 FROM pages s WHERE s.document_id = d.id AND s.ocr_text LIKE ?1)''';
    final rows = await _db.rawQuery('''
      SELECT d.*,
        (SELECT COUNT(*) FROM pages c WHERE c.document_id = d.id) AS page_count,
        (SELECT image_path FROM pages f WHERE f.document_id = d.id
           ORDER BY position LIMIT 1) AS cover
      FROM documents d $where
      ORDER BY d.updated_at DESC''', query.isEmpty ? [] : ['%$query%']);
    return [
      for (final r in rows)
        ScanDocument(
          id: r['id'] as int,
          title: r['title'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
          pageCount: r['page_count'] as int,
          coverPath: r['cover'] == null ? null : _abs(r['cover'] as String),
        ),
    ];
  }

  Future<ScanDocument> createDocument(String title) async {
    final now = DateTime.now();
    final id = await _db.insert('documents', {
      'title': title,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    notifyListeners();
    return ScanDocument(id: id, title: title, createdAt: now, updatedAt: now);
  }

  Future<void> renameDocument(int id, String title) async {
    await _db.update('documents', {'title': title}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> deleteDocument(int id) async {
    await _db.delete('documents', where: 'id = ?', whereArgs: [id]);
    final dir = Directory(p.join(_root, 'scans', '$id'));
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  Future<List<ScanPage>> pages(int documentId) async {
    final rows = await _db.query('pages',
        where: 'document_id = ?', whereArgs: [documentId], orderBy: 'position');
    return [for (final r in rows) _pageFromRow(r)];
  }

  /// Pages whose OCR never completed (e.g. the app was closed mid-queue).
  Future<List<ScanPage>> pagesWithoutText() async {
    final rows = await _db.query('pages', where: 'ocr_text IS NULL', orderBy: 'id');
    return [for (final r in rows) _pageFromRow(r)];
  }

  Future<ScanPage?> page(int id) async {
    final rows = await _db.query('pages', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _pageFromRow(rows.first);
  }

  ScanPage _pageFromRow(Map<String, Object?> r) => ScanPage(
        id: r['id'] as int,
        documentId: r['document_id'] as int,
        position: r['position'] as int,
        imagePath: _abs(r['image_path'] as String),
        originalPath: _abs(r['original_path'] as String),
        corners: ScanPage.decodeCorners(r['corners'] as String),
        filter: ScanFilter.values.byName(r['filter'] as String),
        ocrText: r['ocr_text'] as String?,
      );

  Future<ScanPage> addPage({
    required int documentId,
    required String imagePath,
    required String originalPath,
    required List<(double, double)> corners,
    required ScanFilter filter,
  }) async {
    final position = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COALESCE(MAX(position) + 1, 0) FROM pages WHERE document_id = ?',
            [documentId])) ??
        0;
    final id = await _db.insert('pages', {
      'document_id': documentId,
      'position': position,
      'image_path': _rel(imagePath),
      'original_path': _rel(originalPath),
      'corners': ScanPage.encodeCorners(corners),
      'filter': filter.name,
    });
    await _touch(documentId);
    return ScanPage(
      id: id,
      documentId: documentId,
      position: position,
      imagePath: imagePath,
      originalPath: originalPath,
      corners: corners,
      filter: filter,
    );
  }

  /// Replaces a page's processed image after re-cropping or a filter change.
  /// The old image is deleted and the OCR text is reset.
  Future<void> updatePageImage(ScanPage page, String newImagePath,
      List<(double, double)> corners, ScanFilter filter) async {
    final old = page.imagePath;
    await _db.update(
        'pages',
        {
          'image_path': _rel(newImagePath),
          'corners': ScanPage.encodeCorners(corners),
          'filter': filter.name,
          'ocr_text': null,
        },
        where: 'id = ?',
        whereArgs: [page.id]);
    if (old != newImagePath) await _deleteFile(old);
    page
      ..imagePath = newImagePath
      ..corners = corners
      ..filter = filter
      ..ocrText = null;
    await _touch(page.documentId);
  }

  Future<void> setOcrText(int pageId, String text) async {
    await _db.update('pages', {'ocr_text': text}, where: 'id = ?', whereArgs: [pageId]);
    notifyListeners();
  }

  Future<void> deletePage(ScanPage page) async {
    await _db.delete('pages', where: 'id = ?', whereArgs: [page.id]);
    await _deleteFile(page.imagePath);
    await _deleteFile(page.originalPath);
    await _touch(page.documentId);
  }

  /// Saves the page order given by [ordered].
  Future<void> reorderPages(int documentId, List<ScanPage> ordered) async {
    await _db.transaction((txn) async {
      for (var i = 0; i < ordered.length; i++) {
        ordered[i].position = i;
        await txn.update('pages', {'position': i},
            where: 'id = ?', whereArgs: [ordered[i].id]);
      }
    });
    await _touch(documentId);
  }

  Future<void> _touch(int documentId) async {
    await _db.update('documents', {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [documentId]);
    notifyListeners();
  }

  Future<void> _deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

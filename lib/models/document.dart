import 'dart:convert';

import '../services/scanner.dart';

class ScanDocument {
  ScanDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.pageCount = 0,
    this.coverPath,
  });

  final int id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final int pageCount;

  /// Absolute path of the first page's image, if any.
  final String? coverPath;
}

class ScanPage {
  ScanPage({
    required this.id,
    required this.documentId,
    required this.position,
    required this.imagePath,
    required this.originalPath,
    required this.corners,
    required this.filter,
    this.ocrText,
    this.ocrLayout,
  });

  final int id;
  final int documentId;
  int position;

  /// Absolute path of the processed (cropped + filtered) image.
  String imagePath;

  /// Absolute path of the untouched photo, kept so the crop can be redone.
  final String originalPath;
  List<(double, double)> corners;
  ScanFilter filter;

  /// Recognized text; null until OCR has run.
  String? ocrText;

  /// Position of every recognized word; null until OCR has run (or for pages
  /// recognized before word positions were stored).
  OcrLayout? ocrLayout;

  static String encodeCorners(List<(double, double)> c) =>
      jsonEncode([for (final (x, y) in c) [x, y]]);

  static List<(double, double)> decodeCorners(String s) => [
        for (final p in jsonDecode(s) as List)
          ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];
}

/// A word found by OCR, with its bounding box in image pixels.
class OcrWord {
  const OcrWord(this.text, this.left, this.top, this.width, this.height);
  final String text;
  final int left, top, width, height;
}

/// Where OCR found each word on a page image of [width] x [height] pixels.
/// Used to put an invisible, searchable text layer in exported PDFs.
class OcrLayout {
  const OcrLayout(this.width, this.height, this.words);
  final int width, height;
  final List<OcrWord> words;

  /// Parses the result of the native OCR call.
  factory OcrLayout.fromNative(Map<Object?, Object?> m) => OcrLayout(
        m['width'] as int,
        m['height'] as int,
        [
          for (final w in m['words'] as List)
            OcrWord((w as List)[0] as String, w[1] as int, w[2] as int, w[3] as int, w[4] as int),
        ],
      );

  String encode() => jsonEncode({
        'w': width,
        'h': height,
        'words': [for (final w in words) [w.text, w.left, w.top, w.width, w.height]],
      });

  factory OcrLayout.decode(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return OcrLayout(m['w'] as int, m['h'] as int, [
      for (final w in m['words'] as List)
        OcrWord(w[0] as String, w[1] as int, w[2] as int, w[3] as int, w[4] as int),
    ]);
  }
}

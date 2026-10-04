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

  static String encodeCorners(List<(double, double)> c) =>
      jsonEncode([for (final (x, y) in c) [x, y]]);

  static List<(double, double)> decodeCorners(String s) => [
        for (final p in jsonDecode(s) as List)
          ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];
}

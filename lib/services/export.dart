import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/document.dart';

class Exporter {
  /// Builds a PDF with one page per scan. Each PDF page is A4 wide and as
  /// tall as the scan's aspect ratio requires, so nothing is cropped.
  static Future<File> buildPdf(ScanDocument doc, List<ScanPage> pages) async {
    final pdf = pw.Document(title: doc.title, creator: 'DocScanner');
    for (final page in pages) {
      final bytes = await File(page.imagePath).readAsBytes();
      final size = await _imageSize(bytes);
      final width = PdfPageFormat.a4.width;
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(width, width * size.height / size.width),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
      ));
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${_safeName(doc.title)}.pdf'));
    return file.writeAsBytes(await pdf.save());
  }

  static Future<void> sharePdf(ScanDocument doc, List<ScanPage> pages) async {
    final file = await buildPdf(doc, pages);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      title: doc.title,
    ));
  }

  static Future<void> shareImages(ScanDocument doc, List<ScanPage> pages) =>
      SharePlus.instance.share(ShareParams(
        files: [for (final page in pages) XFile(page.imagePath, mimeType: 'image/jpeg')],
        title: doc.title,
      ));

  static Future<void> shareText(String title, String text) =>
      SharePlus.instance.share(ShareParams(text: text, subject: title));

  static Future<ui.Size> _imageSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    descriptor.dispose();
    buffer.dispose();
    return size;
  }

  static String _safeName(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^\w\- ]'), '_').trim();
    return cleaned.isEmpty ? 'document' : cleaned;
  }
}

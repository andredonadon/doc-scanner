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
  /// Builds a PDF with one page per scan, with recognized text as an
  /// invisible layer so the PDF is searchable and its text can be selected.
  static Future<File> buildPdf(ScanDocument doc, List<ScanPage> pages) async {
    final inputs = <PdfPageInput>[];
    for (final page in pages) {
      final bytes = await File(page.imagePath).readAsBytes();
      final layout = page.ocrLayout;
      final size = layout != null
          ? ui.Size(layout.width.toDouble(), layout.height.toDouble())
          : await _imageSize(bytes);
      inputs.add(PdfPageInput(bytes, size.width, size.height, layout));
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${_safeName(doc.title)}.pdf'));
    return file.writeAsBytes(await renderPdf(doc.title, inputs));
  }

  /// Renders page images into a PDF. Each PDF page is A4 wide and as tall as
  /// the image's aspect ratio requires, so nothing is cropped.
  static Future<Uint8List> renderPdf(String title, List<PdfPageInput> pages) {
    final pdf = pw.Document(title: title, creator: 'DocScanner');
    final font = PdfFont.helvetica(pdf.document);
    for (final page in pages) {
      final width = PdfPageFormat.a4.width;
      final height = width * page.height / page.width;
      final layout = page.layout;
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(width, height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [
          pw.Positioned.fill(child: pw.Image(pw.MemoryImage(page.jpeg), fit: pw.BoxFit.fill)),
          if (layout != null)
            pw.Positioned.fill(
              child: pw.CustomPaint(
                size: PdfPoint(width, height),
                painter: (canvas, size) => _drawTextLayer(canvas, size, layout, font),
              ),
            ),
        ]),
      ));
    }
    return pdf.save();
  }

  /// Writes each OCR word as invisible text over its position in the image,
  /// stretched to the word's width, so search hits and text selection line up
  /// with the visible scan.
  static void _drawTextLayer(PdfGraphics canvas, PdfPoint size, OcrLayout layout, PdfFont font) {
    final sx = size.x / layout.width, sy = size.y / layout.height;
    for (final word in layout.words) {
      final text = _pdfSafe(word.text);
      if (text.trim().isEmpty) continue;
      final fontSize = word.height * sy;
      final naturalWidth = font.stringMetrics(text).width * fontSize;
      if (fontSize <= 0 || naturalWidth <= 0) continue;
      // PDF y grows upwards; put the baseline a little above the box bottom
      // to leave room for descenders.
      final baseline = size.y - (word.top + word.height) * sy + fontSize * 0.2;
      canvas.drawString(font, fontSize, text, word.left * sx, baseline,
          mode: PdfTextRenderingMode.invisible, scale: word.width * sx / naturalWidth);
    }
  }

  /// The built-in PDF font covers Latin-1 (most Western European languages).
  /// Common typographic characters are mapped to equivalents; anything else
  /// becomes '?' rather than failing the export.
  static String _pdfSafe(String s) {
    const replacements = {
      'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬀ': 'ff', '‘': "'", '’': "'", '‚': ',', '“': '"',
      '”': '"', '„': '"', '–': '-', '—': '-', '…': '...', '•': '·', '€': 'EUR',
    };
    final out = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      out.write(rune <= 0xff ? ch : replacements[ch] ?? '?');
    }
    return out.toString();
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

/// One page to render: a JPEG of [width] x [height] pixels and, if OCR has
/// run, where its words are.
class PdfPageInput {
  const PdfPageInput(this.jpeg, this.width, this.height, this.layout);
  final Uint8List jpeg;
  final double width, height;
  final OcrLayout? layout;
}

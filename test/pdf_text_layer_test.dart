import 'dart:io';

import 'package:doc_scanner/models/document.dart';
import 'package:doc_scanner/services/export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';

void main() {
  final hasPdftotext = Process.runSync('which', ['pdftotext']).exitCode == 0;

  test('exported PDF has a searchable text layer at the word positions', () async {
    // A 1000 x 1400 px page with three words at known pixel boxes.
    const layout = OcrLayout(1000, 1400, [
      OcrWord('Prescription', 100, 200, 400, 50),
      OcrWord('physiothérapie', 520, 200, 380, 50),
      OcrWord('2026', 100, 1200, 120, 40),
    ]);
    final jpeg = img.encodeJpg(img.Image(width: 1000, height: 1400)..clear(img.ColorRgb8(255, 255, 255)));
    final bytes = await Exporter.renderPdf('Test', [PdfPageInput(jpeg, 1000, 1400, layout)]);

    final dir = await Directory.systemTemp.createTemp('pdf_test');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File(p.join(dir.path, 'test.pdf'))..writeAsBytesSync(bytes);

    // Plain text extraction finds every word, accents included.
    final text = Process.runSync('pdftotext', ['-enc', 'UTF-8', pdf.path, '-']).stdout as String;
    expect(text, contains('Prescription'));
    expect(text, contains('physiothérapie'));
    expect(text, contains('2026'));

    // Each word sits where it is in the image (page is A4 wide: 595.28 pt).
    final html = Process.runSync('pdftotext', ['-bbox', '-enc', 'UTF-8', pdf.path, '-']).stdout as String;
    final scale = PdfPageFormat.a4.width / 1000;
    for (final word in layout.words) {
      final m = RegExp('<word xMin="([\\d.]+)" yMin="([\\d.]+)" xMax="([\\d.]+)" yMax="([\\d.]+)">'
              '${RegExp.escape(word.text)}</word>')
          .firstMatch(html);
      expect(m, isNotNull, reason: '${word.text} not found in:\n$html');
      final xMin = double.parse(m!.group(1)!), xMax = double.parse(m.group(3)!);
      final yMin = double.parse(m.group(2)!), yMax = double.parse(m.group(4)!);
      expect(xMin, closeTo(word.left * scale, 2), reason: '${word.text} left');
      expect(xMax, closeTo((word.left + word.width) * scale, 2), reason: '${word.text} right');
      // Vertical extent overlaps the word's box (font metrics vary a bit).
      final top = word.top * scale, bottom = (word.top + word.height) * scale;
      expect(yMax, greaterThan(top), reason: '${word.text} vertical');
      expect(yMin, lessThan(bottom), reason: '${word.text} vertical');
    }
  }, skip: hasPdftotext ? false : 'pdftotext not installed');

  test('characters outside the PDF font do not break the export', () async {
    const layout = OcrLayout(100, 100, [OcrWord('ﬁnal “quote” 中文 €5', 0, 0, 100, 20)]);
    final jpeg = img.encodeJpg(img.Image(width: 100, height: 100));
    expect(await Exporter.renderPdf('T', [PdfPageInput(jpeg, 100, 100, layout)]), isNotEmpty);
  });
}

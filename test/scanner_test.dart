import 'dart:io';
import 'dart:math' as math;

import 'package:doc_scanner/services/scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const w = 1200, h = 900;

// A tilted page, as normalized TL, TR, BR, BL.
const tilted = [(0.18, 0.12), (0.82, 0.18), (0.78, 0.9), (0.14, 0.84)];

/// Draws a synthetic photo of a page on a background, with optional camera-like
/// imperfections, and returns it.
img.Image scene({
  List<(double, double)> page = tilted,
  img.Color? background,
  img.Color? paper,
  bool clutter = false,
  bool finger = false,
  bool shadow = false,
  bool noise = true,
}) {
  final rnd = math.Random(42);
  final image = img.Image(width: w, height: h);
  img.fill(image, color: background ?? img.ColorRgb8(70, 55, 40));
  if (clutter) {
    // Wood-grain-like lines and some objects on the table.
    for (var i = 0; i < 60; i++) {
      final y = rnd.nextInt(h);
      img.drawLine(image,
          x1: 0, y1: y, x2: w, y2: y + rnd.nextInt(40) - 20,
          color: img.ColorRgb8(90 + rnd.nextInt(30), 70, 50), thickness: 2);
    }
    img.fillRect(image, x1: 1000, y1: 650, x2: 1180, y2: 880, color: img.ColorRgb8(30, 60, 140));
    img.fillCircle(image, x: 90, y: 120, radius: 70, color: img.ColorRgb8(200, 190, 60));
  }
  final vertices = [for (final (x, y) in page) img.Point(x * w, y * h)];
  img.fillPolygon(image, vertices: vertices, color: paper ?? img.ColorRgb8(235, 232, 225));
  // Dense "text" on the page.
  final cx = vertices.map((v) => v.x).reduce((a, b) => a + b) / 4;
  final cy = vertices.map((v) => v.y).reduce((a, b) => a + b) / 4;
  for (var row = -6; row <= 6; row++) {
    for (var word = -5; word <= 4; word++) {
      final x = (cx + word * 50).round(), y = (cy + row * 32).round();
      img.fillRect(image,
          x1: x, y1: y, x2: x + 25 + rnd.nextInt(20), y2: y + 10,
          color: img.ColorRgb8(35, 35, 40));
    }
  }
  if (finger) {
    // A thumb over the left edge of the page.
    img.fillCircle(image,
        x: (vertices[0].x + vertices[3].x) ~/ 2, y: (vertices[0].y + vertices[3].y) ~/ 2,
        radius: 55, color: img.ColorRgb8(205, 150, 120));
  }
  if (shadow) {
    // The phone's shadow darkening the lower right of the photo.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final f = 1 - 0.45 * ((x / w + y / h) / 2).clamp(0.0, 1.0);
        final px = image.getPixel(x, y);
        px
          ..r = px.r * f
          ..g = px.g * f
          ..b = px.b * f;
      }
    }
  }
  if (noise) {
    for (final px in image) {
      final n = rnd.nextInt(17) - 8;
      px
        ..r = (px.r + n).clamp(0, 255)
        ..g = (px.g + n).clamp(0, 255)
        ..b = (px.b + n).clamp(0, 255);
    }
  }
  return img.gaussianBlur(image, radius: 1);
}

void main() {
  late Directory tmp;

  setUpAll(() async => tmp = await Directory.systemTemp.createTemp('scanner_test'));
  tearDownAll(() => tmp.delete(recursive: true));

  Future<String> save(String name, img.Image image) async {
    final path = p.join(tmp.path, '$name.jpg');
    await File(path).writeAsBytes(img.encodeJpg(image, quality: 90));
    return path;
  }

  void expectCorners(DetectionResult r, List<(double, double)> expected, {double tol = 0.025}) {
    expect(r.found, isTrue, reason: 'no page found');
    for (var i = 0; i < 4; i++) {
      expect(r.corners[i].$1, closeTo(expected[i].$1, tol), reason: 'corner $i x: ${r.corners}');
      expect(r.corners[i].$2, closeTo(expected[i].$2, tol), reason: 'corner $i y: ${r.corners}');
    }
  }

  group('detect', () {
    final cases = <String, img.Image Function()>{
      'clean': () => scene(noise: false),
      'camera noise': () => scene(),
      'cluttered table': () => scene(clutter: true),
      'low contrast (white on light grey)': () =>
          scene(background: img.ColorRgb8(200, 198, 192)),
      'white page on white-ish table': () => scene(
          background: img.ColorRgb8(215, 212, 205), paper: img.ColorRgb8(240, 238, 234)),
      'finger over the edge': () => scene(finger: true),
      'shadow across the page': () => scene(shadow: true),
      'everything at once': () => scene(clutter: true, finger: true, shadow: true),
    };
    for (final MapEntry(key: name, value: build) in cases.entries) {
      test(name, () async {
        final path = await save(name.replaceAll(RegExp(r'\W'), '_'), build());
        final r = await Scanner.detect(path);
        expect((r.width, r.height), (w, h));
        expectCorners(r, tilted);
      });
    }

    test('page cut off by the photo border', () async {
      const page = [(0.25, 0.08), (1.15, 0.12), (1.1, 0.95), (0.2, 0.9)];
      final r = await Scanner.detect(await save('border', scene(page: page)));
      expect(r.found, isTrue);
      // Left corners are visible and must match; right ones sit on the border.
      expect(r.corners[0].$1, closeTo(0.25, 0.025));
      expect(r.corners[3].$1, closeTo(0.2, 0.025));
      expect(r.corners[1].$1, greaterThan(0.97));
      expect(r.corners[2].$1, greaterThan(0.97));
    });

    test('falls back to the full image when there is no page', () async {
      final blank = img.fill(img.Image(width: 400, height: 300), color: img.ColorRgb8(90, 90, 90));
      final r = await Scanner.detect(await save('blank', blank));
      expect(r.found, isFalse);
      expect(r.corners, [(0, 0), (1, 0), (1, 1), (0, 1)]);
    });
  });

  for (final filter in ScanFilter.values) {
    test('crops and applies the ${filter.label} filter', () async {
      final photo = await save('photo', scene(noise: false));
      final out = p.join(tmp.path, 'out_${filter.name}.jpg');
      await Scanner.process(photo, out, tilted, filter);
      final result = img.decodeJpg(await File(out).readAsBytes())!;
      // Page is ~770 x ~650 px in the photo.
      expect(result.width, inInclusiveRange(740, 800));
      expect(result.height, inInclusiveRange(620, 680));
      // The cropped page should be mostly light paper, not dark background.
      expect(result.getPixel(20, 20).luminance, greaterThan(150));
    });
  }
}

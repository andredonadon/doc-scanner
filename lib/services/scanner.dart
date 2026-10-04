import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Post-processing applied after the perspective correction.
enum ScanFilter {
  original('Original'),
  enhanced('Enhanced'),
  grayscale('Grayscale'),
  blackWhite('B&W');

  const ScanFilter(this.label);
  final String label;
}

/// Result of edge detection. [corners] are normalized (0..1) coordinates in
/// the order top-left, top-right, bottom-right, bottom-left.
class DetectionResult {
  const DetectionResult(this.width, this.height, this.corners, this.found);
  final int width;
  final int height;
  final List<(double, double)> corners;

  /// False when no document was found and [corners] is the full image.
  final bool found;
}

/// Document edge detection, perspective correction and filters, built on
/// OpenCV. All heavy work runs in a background isolate.
class Scanner {
  static Future<DetectionResult> detect(String imagePath) =>
      Isolate.run(() => _detect(imagePath));

  /// Like [detect], but also writes the intermediate edge maps next to
  /// [debugPrefix] (e.g. `out/photo1`) for inspecting failures.
  @visibleForTesting
  static Future<DetectionResult> detectWithDebug(String imagePath, String debugPrefix) =>
      Isolate.run(() => _detect(imagePath, debugPrefix: debugPrefix));

  /// Crops [srcPath] to the quadrilateral [corners] (normalized, TL/TR/BR/BL),
  /// applies [filter] and writes a JPEG to [dstPath].
  static Future<void> process(
    String srcPath,
    String dstPath,
    List<(double, double)> corners,
    ScanFilter filter,
  ) =>
      Isolate.run(() => _process(srcPath, dstPath, corners, filter));

  static const _detectSize = 600.0;
  static const _maxOutputSize = 2480; // ~A4 at 300 dpi

  static DetectionResult _detect(String path, {String? debugPrefix}) {
    final img = cv.imread(path);
    if (img.isEmpty) throw StateError('Cannot read image $path');
    final w = img.cols, h = img.rows;
    final scale = _detectSize / math.max(w, h);
    final small = cv.resize(img, ((w * scale).round(), (h * scale).round()),
        interpolation: cv.INTER_AREA);
    final sw = small.cols, sh = small.rows;

    // Closing with a large kernel erases text and fine texture, leaving the
    // page as a flat bright area whose outline is the only strong edge.
    final textKernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
    final flat = cv.gaussianBlur(
        cv.morphologyEx(small, cv.MORPH_CLOSE, textKernel,
            iterations: 3, borderType: cv.BORDER_REPLICATE),
        (5, 5),
        0);
    final gray = cv.cvtColor(flat, cv.COLOR_BGR2GRAY);
    final dilateKernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));

    // Several independent views of the page outline; each one handles a
    // different kind of photo, and the best quadrilateral among all wins.
    final maps = <(cv.Mat, int)>[
      // 1. Standard edges: good contrast between page and background.
      (cv.dilate(cv.canny(gray, 50, 150), dilateKernel), cv.RETR_LIST),
      // 2. Sensitive edges on every color channel: white page on a light or
      //    colored surface, where the brightness difference is small.
      (cv.dilate(_maxChannelEdges(flat, 15, 45), dilateKernel, iterations: 2), cv.RETR_LIST),
      // 3. The page as a bright region (Otsu threshold). Works even when the
      //    page touches the image border, where edge outlines stay open.
      (cv.threshold(gray, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU).$2, cv.RETR_EXTERNAL),
    ];

    // Real page sides lie on edges in the photo; spurious shapes made by
    // merging the page with background clutter do not.
    final support = _EdgeSupport(
        cv.dilate(cv.max(maps[0].$1, maps[1].$1), dilateKernel, iterations: 2));

    if (debugPrefix != null) {
      cv.imwrite('${debugPrefix}_0flat.jpg', flat);
      for (var i = 0; i < maps.length; i++) {
        cv.imwrite('${debugPrefix}_${i + 1}map.png', maps[i].$1);
      }
    }

    final imageArea = (sw * sh).toDouble();
    List<(double, double)>? best;
    var bestScore = 0.0;
    for (final (map, mode) in maps) {
      final (contours, _) = cv.findContours(map, mode, cv.CHAIN_APPROX_SIMPLE);
      for (final contour in contours) {
        final quad = _quadFromContour(contour, imageArea);
        if (quad == null) continue;
        final fit = support.of(orderCorners(quad));
        if (fit < 0.6) continue;
        final score = _polygonArea(quad) * fit * fit;
        if (score > bestScore) {
          bestScore = score;
          best = quad;
        }
      }
    }

    if (best == null) {
      return DetectionResult(w, h, const [(0, 0), (1, 0), (1, 1), (0, 1)], false);
    }
    return DetectionResult(
      w,
      h,
      orderCorners([
        for (final (x, y) in best) ((x / sw).clamp(0.0, 1.0), (y / sh).clamp(0.0, 1.0)),
      ]),
      true,
    );
  }

  /// Canny edges of each color channel, combined.
  static cv.Mat _maxChannelEdges(cv.Mat bgr, double low, double high) {
    cv.Mat? edges;
    for (final channel in cv.split(bgr)) {
      final e = cv.canny(channel, low, high);
      edges = edges == null ? e : cv.max(edges, e);
    }
    return edges!;
  }

  /// Reduces a contour to a plausible page quadrilateral, or null.
  static List<(double, double)>? _quadFromContour(cv.VecPoint contour, double imageArea) {
    // The convex hull ignores dents such as fingers holding the page.
    final hull = cv.VecPoint.fromMat(cv.convexHull(contour));
    final hullArea = cv.contourArea(hull);
    if (hullArea < imageArea * 0.15 || hullArea > imageArea * 0.98) return null;

    List<(double, double)>? quad;
    final peri = cv.arcLength(hull, true);
    for (final eps in const [0.02, 0.03, 0.04, 0.05, 0.065, 0.08]) {
      final approx = cv.approxPolyDP(hull, eps * peri, true);
      if (approx.length == 4) {
        quad = [for (final p in approx) (p.x.toDouble(), p.y.toDouble())];
        break;
      }
      if (approx.length < 4) break;
    }
    if (quad == null) {
      // Rounded or occluded corners: use the best-fitting rotated rectangle
      // if the shape is rectangular enough.
      final rect = cv.minAreaRect(hull);
      final box = [for (final p in cv.boxPoints(rect)) (p.x.toDouble(), p.y.toDouble())];
      if (hullArea / _polygonArea(box) < 0.9) return null;
      quad = box;
    }
    return _isPlausiblePage(orderCorners(quad)) ? quad : null;
  }

  /// Rejects shapes no photographed page could have: very sharp or very
  /// obtuse corners, or a side much shorter than its opposite.
  static bool _isPlausiblePage(List<(double, double)> q) {
    for (var i = 0; i < 4; i++) {
      final prev = q[(i + 3) % 4], cur = q[i], next = q[(i + 1) % 4];
      final ax = prev.$1 - cur.$1, ay = prev.$2 - cur.$2;
      final bx = next.$1 - cur.$1, by = next.$2 - cur.$2;
      final cos = (ax * bx + ay * by) /
          (math.sqrt(ax * ax + ay * ay) * math.sqrt(bx * bx + by * by) + 1e-9);
      final angle = math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
      if (angle < 45 || angle > 135) return false;
    }
    double len((double, double) a, (double, double) b) =>
        math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
    final top = len(q[0], q[1]), bottom = len(q[3], q[2]);
    final left = len(q[0], q[3]), right = len(q[1], q[2]);
    return math.min(top, bottom) / math.max(top, bottom) > 0.5 &&
        math.min(left, right) / math.max(left, right) > 0.5;
  }

  static double _polygonArea(List<(double, double)> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      sum += a.$1 * b.$2 - b.$1 * a.$2;
    }
    return sum.abs() / 2;
  }

  static void _process(
    String srcPath,
    String dstPath,
    List<(double, double)> corners,
    ScanFilter filter,
  ) {
    final img = cv.imread(srcPath);
    if (img.isEmpty) throw StateError('Cannot read image $srcPath');
    final pts = [
      for (final (x, y) in corners) (x * img.cols, y * img.rows),
    ];
    double dist((double, double) a, (double, double) b) =>
        math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
    var outW = math.max(dist(pts[0], pts[1]), dist(pts[3], pts[2]));
    var outH = math.max(dist(pts[0], pts[3]), dist(pts[1], pts[2]));
    final shrink = math.min(1.0, _maxOutputSize / math.max(outW, outH));
    outW = (outW * shrink).roundToDouble();
    outH = (outH * shrink).roundToDouble();

    final src = cv.VecPoint2f.fromList(
        [for (final (x, y) in pts) cv.Point2f(x, y)]);
    final dst = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(outW - 1, 0),
      cv.Point2f(outW - 1, outH - 1),
      cv.Point2f(0, outH - 1),
    ]);
    final m = cv.getPerspectiveTransform2f(src, dst);
    final warped = cv.warpPerspective(img, m, (outW.toInt(), outH.toInt()));

    final out = switch (filter) {
      ScanFilter.original => warped,
      ScanFilter.enhanced => _enhance(warped),
      ScanFilter.grayscale => cv.cvtColor(warped, cv.COLOR_BGR2GRAY),
      ScanFilter.blackWhite => _blackWhite(warped),
    };
    if (!cv.imwrite(dstPath, out, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]))) {
      throw StateError('Cannot write $dstPath');
    }
  }

  /// Flattens uneven lighting by dividing by an estimate of the paper
  /// background, which whitens the page and keeps ink colors.
  static cv.Mat _enhance(cv.Mat img) {
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
    final background = cv.medianBlur(cv.dilate(img, kernel), 21);
    return cv.divide(img, background, scale: 255);
  }

  static cv.Mat _blackWhite(cv.Mat img) {
    final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
    final blurred = cv.gaussianBlur(gray, (3, 3), 0);
    return cv.adaptiveThreshold(blurred, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY, 31, 15);
  }

  /// Orders four points as top-left, top-right, bottom-right, bottom-left.
  static List<(double, double)> orderCorners(List<(double, double)> pts) {
    final bySum = [...pts]..sort((a, b) => (a.$1 + a.$2).compareTo(b.$1 + b.$2));
    final byDiff = [...pts]..sort((a, b) => (a.$2 - a.$1).compareTo(b.$2 - b.$1));
    return [bySum.first, byDiff.first, bySum.last, byDiff.last];
  }
}

/// Measures how much of a quadrilateral's outline runs along edge pixels.
class _EdgeSupport {
  _EdgeSupport(cv.Mat edges)
      : _w = edges.cols,
        _h = edges.rows,
        _data = Uint8List.fromList(edges.data);

  final int _w, _h;
  final Uint8List _data;

  /// Fraction (0..1) of sample points along the sides that hit an edge.
  /// Points on the image border count as supported, since a page that runs
  /// off the photo has no visible edge there.
  double of(List<(double, double)> quad) {
    const samplesPerSide = 60;
    var hits = 0;
    for (var i = 0; i < 4; i++) {
      final a = quad[i], b = quad[(i + 1) % 4];
      for (var s = 0; s < samplesPerSide; s++) {
        final t = (s + 0.5) / samplesPerSide;
        final x = (a.$1 + (b.$1 - a.$1) * t).round();
        final y = (a.$2 + (b.$2 - a.$2) * t).round();
        if (x <= 3 || y <= 3 || x >= _w - 4 || y >= _h - 4 || _data[y * _w + x] != 0) {
          hits++;
        }
      }
    }
    return hits / (4 * samplesPerSide);
  }
}

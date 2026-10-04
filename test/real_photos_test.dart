// Runs edge detection on real photos in test/photos/ and writes, for each one,
// an overlay of the detected page plus the intermediate edge maps to
// test/photos/out/. Skipped when the folder has no photos.
import 'dart:io';

import 'package:doc_scanner/services/scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  final dir = Directory('test/photos');
  final photos = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) =>
              RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(f.path)).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  final out = Directory('test/photos/out');

  for (final photo in photos) {
    test(p.basename(photo.path), () async {
      out.createSync(recursive: true);
      final name = p.basenameWithoutExtension(photo.path);
      final r = await Scanner.detectWithDebug(photo.path, p.join(out.path, name));
      // ignore: avoid_print
      print('$name: ${r.width}x${r.height} found=${r.found} corners=${r.corners}');

      // Draw the result on a downscaled, EXIF-rotated copy of the photo.
      var image = img.bakeOrientation(img.decodeImage(photo.readAsBytesSync())!);
      image = img.copyResize(image, width: 800);
      final pts = [for (final (x, y) in r.corners) img.Point(x * image.width, y * image.height)];
      final color = r.found ? img.ColorRgb8(0, 220, 0) : img.ColorRgb8(255, 0, 0);
      for (var i = 0; i < 4; i++) {
        img.drawLine(image,
            x1: pts[i].x.round(), y1: pts[i].y.round(),
            x2: pts[(i + 1) % 4].x.round(), y2: pts[(i + 1) % 4].y.round(),
            color: color, thickness: 4);
        img.fillCircle(image, x: pts[i].x.round(), y: pts[i].y.round(), radius: 8, color: color);
      }
      File(p.join(out.path, '${name}_result.jpg')).writeAsBytesSync(img.encodeJpg(image));
    });
  }
}

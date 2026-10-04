import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document.dart';
import 'storage.dart';

/// Runs Tesseract OCR on pages one at a time in the background and stores the
/// recognized text, which makes documents searchable.
class OcrQueue extends ChangeNotifier {
  OcrQueue(this._storage);

  final Storage _storage;
  final _queue = Queue<int>();
  final _pending = <int>{};
  bool _running = false;
  String? _dataPath;

  static const _channel = MethodChannel('doc_scanner/ocr');

  /// Tesseract language codes joined by '+' (e.g. 'eng+ita'); each needs `assets/tessdata/<code>.traineddata`.
  static const language = 'eng';

  bool isPending(int pageId) => _pending.contains(pageId);

  void enqueue(Iterable<ScanPage> pages) {
    for (final page in pages) {
      if (_pending.add(page.id)) _queue.add(page.id);
    }
    notifyListeners();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    while (_queue.isNotEmpty) {
      final id = _queue.removeFirst();
      final page = await _storage.page(id);
      if (page == null) {
        _pending.remove(id); // Deleted while waiting.
        continue;
      }
      Map<Object?, Object?>? result;
      try {
        result = await _channel.invokeMethod<Map<Object?, Object?>>('recognize', {
          'imagePath': page.imagePath,
          'dataPath': _dataPath ??= await _installTessdata(),
          'language': language,
        });
      } catch (e) {
        debugPrint('OCR failed for page $id: $e');
      }
      final current = await _storage.page(id);
      if (current != null && current.imagePath != page.imagePath) {
        _queue.add(id); // Re-edited meanwhile; recognize the new image.
        continue;
      }
      if (current != null && result != null) {
        await _storage.setOcrResult(
            id, (result['text'] as String).trim(), OcrLayout.fromNative(result));
      }
      _pending.remove(id);
      notifyListeners();
    }
    _running = false;
  }

  /// Tesseract reads models from disk, so copy the bundled ones out of the
  /// app assets once. Returns the folder that contains `tessdata/`.
  static Future<String> _installTessdata() async {
    final root = (await getApplicationSupportDirectory()).path;
    final dir = await Directory(p.join(root, 'tessdata')).create(recursive: true);
    for (final lang in language.split('+')) {
      final file = File(p.join(dir.path, '$lang.traineddata'));
      if (await file.exists()) continue;
      final data = await rootBundle.load('assets/tessdata/$lang.traineddata');
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return root;
  }
}

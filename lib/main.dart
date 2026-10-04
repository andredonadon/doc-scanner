import 'package:flutter/material.dart';

import 'app.dart';
import 'services/ocr.dart';
import 'services/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  storage = await Storage.open();
  ocr = OcrQueue(storage);
  runApp(const DocScannerApp());
  ocr.enqueue(await storage.pagesWithoutText());
}

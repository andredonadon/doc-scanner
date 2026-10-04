import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'services/ocr.dart';
import 'services/storage.dart';

/// App-wide services, initialized once in `main()`.
late final Storage storage;
late final OcrQueue ocr;

class DocScannerApp extends StatelessWidget {
  const DocScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1B8A6B);
    return MaterialApp(
      title: 'DocScanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const LibraryScreen(),
    );
  }
}

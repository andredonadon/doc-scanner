# DocScanner

A free and open-source document scanner for Android, built with Flutter.
It has no ads, no account and no tracking, and every step runs on the device.

## Features

- **Scan:** photograph one or more pages in a row, or import photos from the gallery.
- **Automatic edge detection:** finds the page borders. You can drag the corners to adjust (a magnifier helps), then the page is straightened (perspective correction).
- **Filters:** Original, Enhanced (removes shadows and whitens the paper), Grayscale and Black & White.
- **OCR:** recognizes text in the background so you can copy, share or search it.
- **Library:** documents are stored locally. You can rename them, delete them, reorder and re-edit pages, and search by title or page text.
- **Export:** share a document as a **searchable PDF** (the recognized text is an invisible layer, so you can search and select it), as images or as plain text.

## Open-source stack

| Purpose            | Library                                                    | License    |
|--------------------|------------------------------------------------------------|------------|
| Edge detection, filters | [OpenCV](https://opencv.org) via [opencv_dart](https://pub.dev/packages/opencv_dart) | Apache-2.0 |
| OCR                | [Tesseract](https://github.com/tesseract-ocr/tesseract) via [Tesseract4Android](https://github.com/adaptech-cz/Tesseract4Android) | Apache-2.0 |
| Camera             | [camera](https://pub.dev/packages/camera)                  | BSD-3      |
| PDF                | [pdf](https://pub.dev/packages/pdf)                        | Apache-2.0 |
| Database           | [sqflite](https://pub.dev/packages/sqflite)                | BSD-2      |

There are no Google Play Services or proprietary SDKs, so the app can be published on F-Droid.

## Building

Requirements: Flutter (stable), JDK 17, and the Android SDK with **CMake** and **NDK** installed.
OpenCV is compiled from source during the build, so the first build takes several minutes.

```sh
flutter pub get
flutter run                 # on a connected phone or an emulator
flutter build apk --release --split-per-abi
flutter test                # unit tests; also builds OpenCV for the host (needs cmake on PATH)
```

## Project layout

```
lib/
  main.dart, app.dart        app setup and theme
  models/document.dart       ScanDocument, ScanPage
  services/
    scanner.dart             OpenCV: edge detection, perspective warp, filters
    ocr.dart                 background OCR queue (talks to MainActivity.kt)
    storage.dart             SQLite metadata + image files
    export.dart              PDF / image / text sharing
    scan_flow.dart           capture → adjust → save workflow
  screens/                   library, document, page viewer, camera, editor
  widgets/                   corner editor, dialogs
tool/edge_prototype.py       experimental line-based edge detector (Python)
android/app/src/main/kotlin/.../MainActivity.kt   Tesseract bridge
assets/tessdata/             OCR language models (tessdata_fast)
```

## Status

Early but usable. It has been tested on a real phone (arm64): capture, cropping, filters, OCR, library and PDF export all work.

### Known issues

- **Edge detection is the weak spot.** It works on a page with clear contrast against the background. It often fails on low-contrast scenes such as white paper on a white or wrinkled bedsheet. Then it falls back to the full photo, and you drag the corners by hand.
- Only English OCR is bundled (see below).
- The app is Android only. The code is mostly cross-platform, but OCR uses an Android-only bridge (`MainActivity.kt`).

### Roadmap

See [TODO.md](TODO.md) for planned features and open tasks.

## Development notes

- **Toolchain:** Flutter stable, JDK 17, Android SDK with NDK and CMake. `dartcv4` builds OpenCV from source through a native-assets hook. It needs `cmake` on `PATH` (the Android SDK's copy works: `$ANDROID_HOME/cmake/<version>/bin`), including for `flutter test`. The first build per CPU architecture takes several minutes; after that it's cached.
- **Fast device build:** `flutter build apk --release --split-per-abi --target-platform android-arm64`
- **Testing edge detection on real photos:** put photos in `test/photos/` (git-ignored, since photos are often private) and run `flutter test test/real_photos_test.dart`. For each photo it writes an overlay of the detected page plus the intermediate edge maps to `test/photos/out/`.
- **Synthetic tests:** `test/scanner_test.dart` generates hard scenes (noise, clutter, low contrast, finger, shadow, page cut off by the border) and checks the detected corners.
- **OCR:** this uses [Tesseract4Android](https://github.com/adaptech-cz/Tesseract4Android) directly (from JitPack) through a small `MethodChannel` in `MainActivity.kt`. The `flutter_tesseract_ocr` plugin no longer builds with current Gradle.

## OCR languages

Only English is bundled. To add a language, e.g. Italian:

1. Download `ita.traineddata` from [tessdata_fast](https://github.com/tesseract-ocr/tessdata_fast) into `assets/tessdata/`.
2. Set `OcrQueue.language = 'eng+ita'` in `lib/services/ocr.dart`.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

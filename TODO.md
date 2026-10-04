# TODO

Ideas and planned work, roughly in priority order. Effort estimates are rough.

## Next up

- [ ] **Better edge detection.** It fails on low-contrast scenes (white paper on a white bedsheet).
  - [ ] Collect real original photos where it fails into `test/photos/` (git-ignored) and check them with `test/real_photos_test.dart`.
  - [ ] Tune the line-based prototype `tool/edge_prototype.py` on those photos.
  - [ ] Port it to `lib/services/scanner.dart` alongside the contour-based detector, and keep the best-scoring result.
- [ ] **Searchable PDF:** embed the OCR text as an invisible layer, so the text in exported PDFs can be selected and searched. *~1 day*
- [ ] **Rotate page** (90° steps) in the page viewer and editor. *few hours*
- [ ] **Apply filter to all pages** of a document. *few hours*
- [ ] **PDF size options** (small / medium / original) for upload limits on web forms. *few hours*
- [ ] **Share into the app:** accept images from other apps (Android share intent). *few hours*

## Scanning experience

- [ ] **Live edge detection in the camera preview,** with the page outline drawn on top. Depends on the better detector. *few days*
- [ ] **Auto-capture** when the page is detected and the phone is steady.
- [ ] **ID card mode:** front and back of a card on one A4 page. *~1 day*
- [ ] Remove hand shadows and finger marks near page edges. *research*

## OCR

- [ ] **Language picker in the app;** download `traineddata` files on demand instead of bundling them. *~1 day*
- [ ] Bundle or offer more languages (fra, ita, deu, …).

## Documents

- [ ] **Signatures:** draw once, then place on any page. *few days*
- [ ] Import existing PDFs as documents.
- [ ] **Encrypted backup / export** of the whole library. *few days*

## Release

- [ ] Change the application ID from the placeholder `io.github.docscanner.doc_scanner` to the final one (e.g. `io.github.andredonadon.docscanner`). Do this before any public release, because it counts as a new app.
- [ ] App icon and name.
- [ ] Release signing config (keystore outside the repo).
- [ ] F-Droid metadata (fastlane structure, screenshots, description).
- [ ] GitHub release with APKs per ABI.

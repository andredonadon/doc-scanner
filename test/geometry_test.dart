import 'package:doc_scanner/models/document.dart';
import 'package:doc_scanner/services/scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orderCorners returns TL, TR, BR, BL for any input order', () {
    const tl = (0.1, 0.12), tr = (0.9, 0.08), br = (0.95, 0.9), bl = (0.05, 0.88);
    expect(Scanner.orderCorners([br, tl, bl, tr]), [tl, tr, br, bl]);
    expect(Scanner.orderCorners([bl, br, tr, tl]), [tl, tr, br, bl]);
  });

  test('corners survive a JSON round trip', () {
    const corners = [(0.0, 0.0), (1.0, 0.0), (0.75, 0.5), (0.25, 1.0)];
    expect(ScanPage.decodeCorners(ScanPage.encodeCorners(corners)), corners);
  });
}

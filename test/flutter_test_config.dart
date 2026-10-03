import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Golden comparator that tolerates tiny cross-platform rasterization
/// differences. Dev machines (macOS CoreGraphics) and Linux CI (FreeType)
/// render the bundled fonts with sub-pixel differences; 0.4–1.6% pixel
/// diffs were observed on byte-identical screens. Real regressions
/// (layout, color, copy) move far more pixels. The Flutter version is
/// pinned in CI (see .github/workflows/ci.yml) so the message format and
/// rendering stay stable; revisit the threshold after any toolchain bump.
class TolerantGoldenComparator extends GoldenFileComparator {
  TolerantGoldenComparator(this._inner);

  final LocalFileComparator _inner;

  /// Maximum accepted pixel-diff percentage.
  static const double maxDiffPercent = 2.5;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    try {
      return await _inner.compare(imageBytes, golden);
    } catch (e) {
      final String msg = e is TestFailure ? '${e.message}' : '$e';
      final Match? m = RegExp(r'([\d.]+)%').firstMatch(msg);
      if (m != null && double.parse(m.group(1)!) <= maxDiffPercent) {
        return true;
      }
      rethrow;
    }
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      _inner.update(golden, imageBytes);
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final GoldenFileComparator current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(current);
  }
  await testMain();
}

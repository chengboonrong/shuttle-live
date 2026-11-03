import 'dart:ui';

/// Doubles court in metres: x across (0–6.1), y from the far baseline (0–13.4).
const courtWidth = 6.1;
const courtLength = 13.4;
const netY = courtLength / 2;

/// Court corners in the order the user taps them:
/// far-left, far-right, near-right, near-left.
const courtCorners = [
  Offset(0, 0),
  Offset(courtWidth, 0),
  Offset(courtWidth, courtLength),
  Offset(0, courtLength),
];

/// Perspective map between two planes, fitted to four point pairs.
class Homography {
  Homography._(this._h);

  /// 3x3 row-major, last entry fixed at 1.
  final List<double> _h;

  factory Homography.fit(List<Offset> from, List<Offset> to) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = from[i].dx, y = from[i].dy, u = to[i].dx, v = to[i].dy;
      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    // Gauss-Jordan elimination with partial pivoting.
    for (var c = 0; c < 8; c++) {
      var p = c;
      for (var r = c + 1; r < 8; r++) {
        if (a[r][c].abs() > a[p][c].abs()) p = r;
      }
      final row = a[c];
      a[c] = a[p];
      a[p] = row;
      if (a[c][c].abs() < 1e-12) {
        throw ArgumentError('three of the corners are in a line');
      }
      for (var r = 0; r < 8; r++) {
        if (r == c) continue;
        final f = a[r][c] / a[c][c];
        for (var k = c; k < 9; k++) {
          a[r][k] -= f * a[c][k];
        }
      }
    }
    return Homography._([for (var r = 0; r < 8; r++) a[r][8] / a[r][r], 1]);
  }

  Offset map(Offset p) {
    final h = _h;
    final w = h[6] * p.dx + h[7] * p.dy + h[8];
    return Offset(
      (h[0] * p.dx + h[1] * p.dy + h[2]) / w,
      (h[3] * p.dx + h[4] * p.dy + h[5]) / w,
    );
  }
}

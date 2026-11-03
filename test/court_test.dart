import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_live/court.dart';

void main() {
  // A court seen from behind and above the near baseline: far end narrower.
  const taps = [
    Offset(0.35, 0.30),
    Offset(0.65, 0.30),
    Offset(0.90, 0.85),
    Offset(0.10, 0.85),
  ];

  test('tapped corners land on the court corners', () {
    final toCourt = Homography.fit(taps, courtCorners);
    for (var i = 0; i < 4; i++) {
      expect((toCourt.map(taps[i]) - courtCorners[i]).distance, lessThan(1e-9));
    }
  });

  test('net sits above the halfway point on screen and maps back to itself', () {
    final toCourt = Homography.fit(taps, courtCorners);
    final toImage = Homography.fit(courtCorners, taps);
    const centre = Offset(courtWidth / 2, netY);
    final onScreen = toImage.map(centre);
    expect(onScreen.dy, lessThan((0.30 + 0.85) / 2)); // perspective, not a plain stretch
    expect((toCourt.map(onScreen) - centre).distance, lessThan(1e-9));
  });
}

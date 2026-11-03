import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_live/analysis.dart';
import 'package:shuttle_live/court.dart';

void main() {
  test('launch speed undoes drag', () {
    // 8 m in 0.6 s averages 13 m/s, but left the racket near 36 m/s.
    expect(launchSpeed(8, 0.6), closeTo(36, 0.5));
  });

  test('one fast overhead whip is one overhead hit', () {
    // Shoulders at y=100, hips at y=150: torso 50 px. Right wrist whips up.
    List<Offset> pose(Offset wrist) => [
      for (var i = 0; i < 17; i++)
        switch (i) {
          5 => const Offset(90, 100),
          6 => const Offset(110, 100),
          9 => const Offset(90, 140),
          10 => wrist,
          11 => const Offset(92, 150),
          12 => const Offset(108, 150),
          _ => const Offset(100, 80),
        },
    ];
    final path = [
      for (var i = 0; i < 5; i++) const Offset(110, 100),
      const Offset(110, 60),
      const Offset(115, 20),
      const Offset(120, 40),
      for (var i = 0; i < 5; i++) const Offset(120, 40),
    ];
    final s = SwingDetector();
    final t0 = DateTime(2026);
    final swings = [
      for (var i = 0; i < path.length; i++)
        s.update(pose(path[i]), List.filled(17, 0.9), t0.add(Duration(milliseconds: 33 * i)), 8),
    ].nonNulls.toList();
    expect(swings, hasLength(1));
    expect(swings.single.contact, Contact.overhead);
    expect(swings.single.time, t0.add(const Duration(milliseconds: 33 * 6)));
  });

  test('a rally names each shot from its reply', () {
    final m = Match();
    final t0 = DateTime(2026);
    DateTime at(double s) => t0.add(Duration(milliseconds: (s * 1000).round()));
    m.addHit(Side.far, at(0), const Offset(3, 1), Contact.low, 9); // serve
    m.addHit(Side.near, at(1.2), const Offset(3, 12), Contact.overhead, 20);
    expect(m.addHit(Side.near, at(1.5), const Offset(3, 12), Contact.overhead, 9), isNull);
    m.addHit(Side.far, at(1.7), const Offset(3, 3), Contact.low, 9); // smash came back after 0.5 s
    m.addHit(Side.near, at(2.6), const Offset(3, 8), Contact.overhead, 9); // ...as a short block
    m.addHit(Side.far, at(3.8), const Offset(3, 5.5), Contact.low, 9); // drop picked up near the net
    m.tick(at(10));

    expect(m.hits.map((h) => h.type), [
      ShotType.serve,
      ShotType.smash,
      ShotType.block,
      ShotType.drop,
      ShotType.net,
    ]);
    expect(m.hits[1].speedKmh, closeTo(201, 2)); // 9 m in 0.5 s
    expect(m.rallies, 1);
    expect(m.longestRally, 5);
    expect(netY, 6.7);
  });

  test('a reply logged just after the rally timer still counts as the reply', () {
    final m = Match();
    final t0 = DateTime(2026);
    m.addHit(Side.far, t0, const Offset(3, 1), Contact.low, 9);
    m.tick(t0.add(const Duration(milliseconds: 3050)));
    m.addHit(Side.near, t0.add(const Duration(milliseconds: 2950)), const Offset(3, 12), Contact.mid, 9);
    expect(m.hits.first.to, const Offset(3, 12));
    expect(m.rallies, 1);
  });
}

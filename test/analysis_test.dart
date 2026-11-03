import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_live/analysis.dart';
import 'package:shuttle_live/court.dart';

/// Shoulders at y=100, hips at y=150: torso 50 px. The right wrist is the racket hand.
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

void main() {
  test('launch speed undoes drag', () {
    // 8 m in 0.6 s averages 13 m/s, but left the racket near 36 m/s.
    expect(launchSpeed(8, 0.6), closeTo(36, 0.5));
  });

  test('one fast overhead whip is one overhead hit', () {
    // Right wrist whips up.
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

  test('peakNear takes the fastest frame within 0.3 s of a sound', () {
    // 50 ms frames. The wrist drops 20 px at 400 ms (8 torso/s, low), rises 10 px at 600 ms
    // (4, low) and 40 px at 800 ms (16, mid).
    final s = SwingDetector();
    final t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
    for (var i = 0; i <= 20; i++) {
      final y = i < 8 ? 150.0 : i < 12 ? 170.0 : i < 16 ? 160.0 : 120.0;
      s.update(pose(Offset(110, y)), List.filled(17, 0.9), at(50 * i), 8);
    }
    final peak = s.peakNear(at(400)); // the 16 at 800 ms is 400 ms away
    expect(peak.swing, closeTo(8, 0.01));
    expect(peak.contact, Contact.low);
    expect(s.peakNear(at(5000)), (swing: 0.0, contact: Contact.mid));
    s.reset();
    expect(s.peakNear(at(400)).swing, 0);
  });

  group('racket sounds', () {
    // Flat −60 dB, with spikes at {index: dB}.
    List<double> flat(Map<int, double> spikes) => [for (var i = 0; i < 600; i++) spikes[i] ?? -60];

    test('each lone spike is a sound at its own 5 ms step', () {
      expect(racketSounds(flat({100: -30, 300: -35})), [soundStep * 100, soundStep * 300]);
    });

    test('two spikes 0.2 s apart are one sound, the louder', () {
      expect(racketSounds(flat({100: -40, 140: -30})), [soundStep * 140]);
      expect(racketSounds(flat({100: -30, 140: -40})), [soundStep * 100]);
    });

    test('a new sound needs more than 60 steps (0.3 s) after the last', () {
      expect(racketSounds(flat({100: -30, 160: -40})), [soundStep * 100]);
      expect(racketSounds(flat({100: -30, 161: -40})), [soundStep * 100, soundStep * 161]);
    });

    test('a spike under 10 dB of rise, or a slow ramp, is no sound', () {
      expect(racketSounds(flat({100: -51})), isEmpty);
      expect(racketSounds([for (var i = 0; i < 400; i++) -60 + i * 0.1]), isEmpty);
    });
  });

  test('who hit at a sound', () {
    expect(soundHitter(5, 7, null, 8), isNull); // neither swung
    expect(soundHitter(5, 7, Side.far, 8), isNull);
    expect(soundHitter(9, 12, null, 8), Side.near); // a rally's first: the faster side
    expect(soundHitter(12, 9, null, 8), Side.far);
    expect(soundHitter(12, 7, Side.far, 8), Side.near); // the turn order, though far was faster
    expect(soundHitter(7, 12, Side.near, 8), Side.far);
    expect(soundHitter(12, 6, Side.far, 8), Side.far); // far swung twice as fast: the order re-syncs
    expect(soundHitter(12, 3, Side.far, 8), Side.far);
    expect(soundHitter(3, 12, Side.near, 8), Side.near);
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

// Replays recorded pose frames and the same clip's sound through the app's own Player,
// SwingDetector, SoundHits and Match, with onResult's person selection, and prints the hits.
// Skipped unless REPLAY (pose frames json) and SOUND (dB per 5 ms, a json list) are both set.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_live/analysis.dart';
import 'package:shuttle_live/court.dart';
import 'package:shuttle_live/main.dart';

void main() {
  final env = Platform.environment;
  test('a clip replayed through its racket sounds', skip: env['REPLAY'] == null || env['SOUND'] == null, () {
    final frames = jsonDecode(File(env['REPLAY']!).readAsStringSync()) as List;
    final db = [
      for (final x in jsonDecode(File(env['SOUND']!).readAsStringSync()) as List) (x as num).toDouble(),
    ];
    final taps = [
      const Offset(370 / 1280, 342 / 720),
      const Offset(908 / 1280, 342 / 720),
      const Offset(1085 / 1280, 715 / 720),
      const Offset(200 / 1280, 715 / 720),
    ];
    final h = Homography.fit(taps, courtCorners);
    final far = Player(Side.far, farColour), near = Player(Side.near, nearColour);
    final match = Match();
    const threshold = 8.0;
    final base = DateTime(2000);
    final sounds = SoundHits(racketSounds(db), base);
    var now = base;
    for (final f in frames) {
      now = base.add(Duration(microseconds: f['t'] as int));
      List? bestFar, bestNear;
      Offset? farPos, nearPos;
      for (final p in f['p'] as List) {
        final foot = Offset((p[0] + p[2]) / 2, p[3]);
        final c = h.map(foot);
        if (c.dx < -1 || c.dx > courtWidth + 1 || c.dy < -2 || c.dy > courtLength + 2) continue;
        if (c.dy < netY) {
          if (bestFar == null || p[4] > bestFar[4]) (bestFar, farPos) = (p, c);
        } else if (bestNear == null || p[4] > bestNear[4]) {
          (bestNear, nearPos) = (p, c);
        }
      }
      for (final (pl, r, c) in [(far, bestFar, farPos), (near, bestNear, nearPos)]) {
        if (c != null) {
          pl.update(c, now);
          pl.swing.update(
            [for (var k = 0; k < 17; k++) Offset(r![5 + k * 3] * 1.0, r[6 + k * 3] * 1.0)],
            [for (var k = 0; k < 17; k++) r![7 + k * 3] * 1.0],
            now,
            threshold,
          );
        } else {
          pl.unseen++;
          pl.swing.update(const [], const [], now, threshold);
        }
      }
      sounds.hear(now, far, near, match, threshold);
      match.strongSwing = threshold * 2;
      match.tick(now);
    }
    match.tick(now.add(Match.rallyGap * 2)); // the clip's end names its last shot
    for (final x in match.hits) {
      final t = x.time.difference(base).inMicroseconds / 1e6;
      print('${t.toStringAsFixed(2)} ${x.side.name.padRight(4)} ${x.type?.label ?? '-'} '
          '${x.speedKmh == null ? '' : '~${x.speedKmh!.round()} km/h'}');
    }
    print('rallies ${match.rallies}, hits ${match.hits.length}');

    expect(match.hits.length, inInclusiveRange(15, 22));
    expect(match.hits.map((x) => x.speedKmh).nonNulls, everyElement(lessThan(300)));
  });
}

import 'dart:math' as math;
import 'dart:ui';

import 'court.dart';

enum Side { far, near }

enum Contact { overhead, mid, low }

enum ShotType {
  serve('Serve'),
  smash('Smash'),
  clear('Clear'),
  drop('Drop'),
  lift('Lift'),
  net('Net'),
  drive('Drive'),
  block('Block'),
  push('Push'),
  overhead('Overhead');

  const ShotType(this.label);
  final String label;
}

/// Shuttle drag length: terminal speed² / g, about 6.7² / 9.8 m.
// ponytail: one value for every shuttle and a straight-line flight; arcing shots (clears, lifts) read low.
const dragLength = 4.6;

/// Speed off the racket (m/s) for a shuttle that covered [d] metres in [t]
/// seconds while slowed by air drag: d = L·ln(1 + v0·t / L).
double launchSpeed(double d, double t) =>
    dragLength * (math.exp(d / dragLength) - 1) / t;

const forecourt = 2.5; // metres from the net
const deepReply = 4.0; // a reply from further back than this was a deep shot
const fastFlight = 0.9; // seconds between hits

/// Names a shot from how it was hit and where and when it came back.
/// [strongSwing] marks an unreturned overhead as a smash.
ShotType classify(Hit h, Hit? reply, double strongSwing) {
  if (h.serve) return ShotType.serve;
  final t = reply == null ? null : _seconds(reply.time.difference(h.time));
  final depth = reply == null ? null : (reply.pos.dy - netY).abs();
  return switch (h.contact) {
    Contact.overhead when t == null =>
      h.swing >= strongSwing ? ShotType.smash : ShotType.overhead,
    Contact.overhead when t! < fastFlight => ShotType.smash,
    Contact.overhead => depth! < 3 ? ShotType.drop : ShotType.clear,
    Contact.low when depth != null && depth > deepReply => ShotType.lift,
    Contact.low =>
      (h.pos.dy - netY).abs() < forecourt ? ShotType.net : ShotType.block,
    Contact.mid when t != null && t < fastFlight => ShotType.drive,
    Contact.mid => ShotType.push,
  };
}

double _seconds(Duration d) => d.inMicroseconds / 1e6;

class Hit {
  Hit(this.side, this.time, this.pos, this.contact, this.swing, {required this.serve});

  final Side side;
  final DateTime time;
  final Offset pos; // hitter's feet on the court, metres
  final Contact contact;
  final double swing; // peak wrist speed, torso lengths per second
  final bool serve;

  ShotType? type; // set once the reply is seen or the rally ends
  double? speedKmh; // estimated speed off the racket; needs a reply
  Offset? to; // where the reply was hit from
}

/// The rally log: every hit, each named once its reply comes or the rally ends.
class Match {
  static const rallyGap = Duration(seconds: 3);
  static const sameSwing = Duration(milliseconds: 800);

  final hits = <Hit>[];
  int rallies = 0, rallyShots = 0, longestRally = 0;
  double strongSwing = 16;

  /// Returns the new hit, or null if it was taken as part of the last swing.
  Hit? addHit(Side side, DateTime time, Offset pos, Contact contact, double swing) {
    final prev = hits.lastOrNull;
    final sameRally = prev != null && time.difference(prev.time) <= rallyGap;
    if (sameRally && prev.side == side && time.difference(prev.time) < sameSwing) {
      return null;
    }
    final hit = Hit(side, time, pos, contact, swing, serve: !sameRally);
    // A reply can land just after tick() named the shot; name it again with the reply.
    if (prev != null && (prev.type == null || sameRally)) {
      _finish(prev, sameRally && prev.side != side ? hit : null);
    }
    if (!sameRally) {
      rallies++;
      rallyShots = 0;
    }
    rallyShots++;
    longestRally = math.max(longestRally, rallyShots);
    hits.add(hit);
    return hit;
  }

  /// Call every frame: names the last shot once nobody has hit for a while.
  void tick(DateTime now) {
    final last = hits.lastOrNull;
    if (last != null && last.type == null && now.difference(last.time) > rallyGap) {
      _finish(last, null);
    }
  }

  void _finish(Hit h, Hit? reply) {
    h.type = classify(h, reply, strongSwing);
    if (reply == null) return;
    h.to = reply.pos;
    final t = _seconds(reply.time.difference(h.time));
    final d = (reply.pos - h.pos).distance;
    if (t > 0.15 && d > 1) {
      final v = launchSpeed(d, t);
      if (v < 120) h.speedKmh = v * 3.6; // faster than any smash: a timing slip
    }
  }

  void reset() {
    hits.clear();
    rallies = rallyShots = longestRally = 0;
  }
}

// COCO-17 keypoint indexes.
const _lShoulder = 5, _rShoulder = 6, _lWrist = 9, _rWrist = 10, _lHip = 11, _rHip = 12;

/// Finds racket swings from one player's wrists, measured against their own
/// hips and torso length so running about does not count.
class SwingDetector {
  final _prev = <int, Offset>{};
  DateTime? _prevTime, _peakTime, _lastHit;
  double _peak = 0;
  Contact _peakContact = Contact.mid;
  double speed = 0; // latest wrist speed, torso lengths per second

  /// Feeds one frame of keypoints (any units) and returns a swing once it ends.
  ({DateTime time, Contact contact, double swing})? update(
    List<Offset> kp,
    List<double> conf,
    DateTime now,
    double threshold,
  ) {
    final prevTime = _prevTime;
    _prevTime = now;
    bool seen(int i) => i < conf.length && conf[i] > 0.3;
    if (kp.length < 17 || ![_lShoulder, _rShoulder, _lHip, _rHip].every(seen)) {
      _prev.clear();
      speed = 0;
      return _endSwing(threshold);
    }
    final shoulders = (kp[_lShoulder] + kp[_rShoulder]) / 2;
    final hips = (kp[_lHip] + kp[_rHip]) / 2;
    final torso = (shoulders - hips).distance;
    if (torso <= 0) return null;
    final dt = prevTime == null ? 0.0 : _seconds(now.difference(prevTime));

    var best = 0.0;
    Offset? bestWrist;
    for (final w in [_lWrist, _rWrist]) {
      if (!seen(w)) {
        _prev.remove(w);
        continue;
      }
      final rel = (kp[w] - hips) / torso;
      final before = _prev[w];
      _prev[w] = rel;
      if (before == null || dt <= 0 || dt > 0.2) continue;
      final v = (rel - before).distance / dt;
      if (v > 60) continue; // a jump to another person, not a swing
      if (v > best) {
        best = v;
        bestWrist = kp[w];
      }
    }
    speed = best;

    final recentHit = _lastHit != null && now.difference(_lastHit!).inMilliseconds < 400;
    if (best > threshold && (_peakTime != null || !recentHit)) {
      if (best > _peak) {
        _peak = best;
        _peakTime = now;
        final up = (shoulders.dy - bestWrist!.dy) / torso; // wrist above shoulders
        _peakContact = up > 0.3
            ? Contact.overhead
            : up < -0.6
            ? Contact.low
            : Contact.mid;
      }
      return null;
    }
    return best < threshold * 0.6 ? _endSwing(threshold) : null;
  }

  ({DateTime time, Contact contact, double swing})? _endSwing(double threshold) {
    final t = _peakTime;
    if (t == null) return null;
    final swing = (time: t, contact: _peakContact, swing: _peak);
    _lastHit = t;
    _peakTime = null;
    _peak = 0;
    return swing;
  }

  void reset() {
    _prev.clear();
    _prevTime = _peakTime = _lastHit = null;
    _peak = speed = 0;
  }
}

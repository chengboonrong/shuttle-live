import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_live/analysis.dart';
import 'package:shuttle_live/court.dart';
import 'package:shuttle_live/main.dart';
import 'package:shuttle_live/video.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'fonts.dart';

const demoCorners = [Offset(0.3, 0.22), Offset(0.7, 0.22), Offset(0.96, 0.94), Offset(0.04, 0.94)];

/// One player's keypoints: shoulders y=100, hips y=150 (torso 50); the right wrist is the racket hand.
List<Offset> pose(double wristY) => [
  for (var i = 0; i < 17; i++)
    switch (i) {
      5 => const Offset(90, 100),
      6 => const Offset(110, 100),
      10 => Offset(110, wristY),
      11 => const Offset(92, 150),
      12 => const Offset(108, 150),
      _ => const Offset(100, 120),
    },
];

/// The court lines, rings and P1/P2 tags drawn over the picture.
final overlay = find.byWidgetPredicate(
  (w) => w is CustomPaint && '${w.painter.runtimeType}' == '_OverlayPainter',
);

/// Some [method] call (#drawCircle, #drawRect) is painted in [colour]. A Paint keeps
/// its colour as float32, so compare the 8-bit values.
PaintPattern paintsIn(Symbol method, Color colour) => paints
  ..something(
    (m, args) => m == method && (args.last as Paint).color.toARGB32() == colour.toARGB32(),
  );

/// A phone screen at 3x, as board_test sets it.
void phone(WidgetTester tester, Size size, [double textScale = 1]) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Taps the four demo corners on the frame on screen; the fourth starts counting.
Future<void> setCourt(WidgetTester tester) async {
  final pic = tester.getRect(find.byType(RawImage));
  for (final c in demoCorners) {
    await tester.tapAt(pic.topLeft + Offset(c.dx * pic.width, c.dy * pic.height));
  }
}

/// Lets the clip play to its last frame.
Future<void> playToEnd(WidgetTester tester, dynamic s) async {
  for (var i = 0; s.playing as bool && i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(s.playing, isFalse, reason: 'the clip should have ended');
  await tester.pump(); // the last frame's build
}

/// Pumps the page and opens a mocked 2 s 1920×1080 clip of 5 frames (or one per
/// thumbValue), 33333 µs apart. Frame i's thumbnail is filled with thumbValues[i]
/// (100 by default).
/// The pose model is mocked too: every predict finds [people] (0–1 boxes), or nobody.
/// [sound] is the open reply's envelope, as the native readers send it; null leaves the key out.
Future<dynamic> openMockClip(
  WidgetTester tester, {
  List<int>? thumbValues,
  List<Rect> people = const [],
  Float32List? sound,
  void Function(dynamic s)? beforeOpen,
}) async {
  await tester.pumpWidget(MaterialApp(theme: theme, home: const LivePage()));
  final s = tester.state(find.byType(LivePage)) as dynamic;
  final png = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF2E7D32), BlendMode.src);
    final image = await recorder.endRecording().toImage(16, 9);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
  final messenger = tester.binding.defaultBinaryMessenger;
  var i = 0;
  messenger.setMockMethodCallHandler(VideoFrames.channel, (call) async {
    switch (call.method) {
      case 'open':
        return {'durationUs': 2000000, 'width': 1920, 'height': 1080, 'sound': ?sound};
      case 'next':
        if (i == (thumbValues?.length ?? 5)) return null;
        final thumb = Uint8List(576)..fillRange(0, 576, thumbValues?.elementAtOrNull(i) ?? 100);
        return {'jpeg': png, 'timeUs': 33333 * i++, 'thumb': thumb};
    }
    return null;
  });
  const yolo = MethodChannel(ChannelConfig.singleImageChannel);
  messenger.setMockMethodCallHandler(yolo, (call) async {
    switch (call.method) {
      case 'loadModel':
        return true;
      case 'predictSingleImage':
        // The plugin builds its detections from these two lists.
        return {
          'boxes': [
            for (final r in people)
              {
                'class': 'person',
                'confidence': 0.9,
                'x1_norm': r.left,
                'y1_norm': r.top,
                'x2_norm': r.right,
                'y2_norm': r.bottom,
              },
          ],
          'keypoints': [for (final _ in people) {'coordinates': []}],
        };
    }
    return null;
  });
  // The mocks stay up to the end: unmounting the page closes the clip on the channel.
  beforeOpen?.call(s);
  await tester.runAsync(() => s.openVideo('x.mp4') as Future<void>);
  await tester.pump();
  // predict finds the model's files before it loads them: give it an empty stand-in where
  // the plugin keeps its download (YOLOModelResolver, on a Mac host), so nothing downloads.
  // After the open, so the camera view that just left keeps failing to load as before.
  final docs = Directory.systemTemp.createTempSync('shuttle_live_test');
  File('${docs.path}/mobile-standard-v1/yolo26n-pose.mlpackage/Manifest.json')
      .createSync(recursive: true);
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(paths, (call) async => docs.path);
  addTearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
    docs.deleteSync(recursive: true);
  });
  return s;
}

void main() {
  // Real fonts, so the fit checks measure what a phone shows.
  setUpAll(loadRealFonts);

  Uint8List flat(int v) => Uint8List(576)..fillRange(0, 576, v);

  test('thumbDiff is the mean gray difference', () {
    expect(thumbDiff(flat(100), flat(100)), 0);
    expect(thumbDiff(flat(100), flat(160)), 60);
  });

  test('two frames over the threshold pause counting; three under resume it', () {
    final c = CutDetector(flat(100));
    final cut = flat(100 + cutThreshold.toInt() + 10), court = flat(105);
    expect([c.update(cut), c.update(cut)], [false, true]);
    expect([c.update(court), c.update(court), c.update(court)], [true, true, false]);
  });

  test('a single odd frame never toggles', () {
    final c = CutDetector(flat(100));
    final cut = flat(100 + cutThreshold.toInt() + 10), court = flat(100);
    expect([c.update(cut), c.update(court), c.update(cut), c.update(court)], everyElement(false));
  });

  test('loseTrack keeps totals but forgets the track', () {
    final p = Player(Side.near, nearColour);
    final t0 = DateTime(2026);
    for (var i = 0; i <= 10; i++) {
      p.update(Offset(1 + i * 0.1, 10), t0.add(Duration(milliseconds: 100 * i)));
    }
    final (distance, top) = (p.distance, p.topSpeed);
    expect(distance, greaterThan(0));
    p.loseTrack();
    expect(p.pos, isNull);
    expect(p.trail, isEmpty);
    expect(p.speed, 0);
    expect((p.distance, p.topSpeed), (distance, top));
    // First position after the cut, 2 m away: no distance added.
    p.update(const Offset(3, 10), t0.add(const Duration(seconds: 5)));
    expect(p.distance, distance);
  });

  test('racket sounds become hits: who from the swing, when from the sound', () {
    final far = Player(Side.far, farColour), near = Player(Side.near, nearColour);
    final match = Match();
    final base = DateTime(2000);
    final sounds = SoundHits(const [Duration(milliseconds: 1000), Duration(milliseconds: 1800)], base);
    final heard = <Side>[];
    // 40 ms frames to 2.2 s. Far swings 200 ms after the first sound, near 200 ms before the
    // second: the wrist jumps 30 px up, 15 torso lengths/s. The hits still take the sounds' times,
    // and the first one is only heard once its swing has been seen.
    for (var i = 0; i <= 55; i++) {
      final now = base.add(Duration(milliseconds: 40 * i));
      for (final (p, at, swingFrame) in [(far, const Offset(3, 2), 30), (near, const Offset(3, 11), 40)]) {
        p.update(at, now);
        p.swing.update(pose(i < swingFrame ? 100 : 70), List.filled(17, 0.9), now, 8);
      }
      heard.addAll(sounds.hear(now, far, near, match, 8));
    }
    expect(heard, [Side.far, Side.near]);
    expect(match.hits.map((h) => (h.side, h.time)), [
      (Side.far, base.add(const Duration(milliseconds: 1000))),
      (Side.near, base.add(const Duration(milliseconds: 1800))),
    ]);
    expect(match.hits.first.contact, Contact.overhead);
    expect(match.hits.first.speedKmh, closeTo(126, 1)); // 9 m in 0.8 s
  });

  testWidgets('a clip with sound has its racket sounds', (tester) async {
    final db = Float32List(400)..fillRange(0, 400, -60);
    final s = await openMockClip(tester, sound: db..[200] = -30);
    expect(s.clip.sounds, [soundStep * 200]);
  });

  testWidgets('a clip without sound has none', (tester) async {
    final s = await openMockClip(tester);
    expect(s.clip.sounds, isNull);
  });

  testWidgets('a silent sound track counts as no sound', (tester) async {
    final s = await openMockClip(tester, sound: Float32List(400)..fillRange(0, 400, -100));
    expect(s.clip.sounds, isNull);
  });

  testWidgets('a clip with sound counts no swing away from its sounds; the camera counts it', (
    tester,
  ) async {
    // The clip's one racket sound is at 1.5 s; the whip is over by 0.3 s.
    final s = await openMockClip(tester, sound: Float32List(400)..fillRange(0, 400, -60)..[300] = -30);
    void court() {
      s.recalibrate();
      s.taps.addAll(demoCorners);
      s.toCourt = Homography.fit(demoCorners, courtCorners);
      s.toFrame = Homography.fit(courtCorners, demoCorners);
      s.calibrating = false;
    }

    // A near player whose right wrist whips up 40 px a frame, ~24 torso lengths/s.
    void whip() {
      for (final (i, y) in const <double>[100, 100, 100, 60, 20, 40, 40, 40, 40].indexed) {
        s.onResult([
          YOLOResult(
            classIndex: 0,
            className: 'person',
            confidence: 0.9,
            boundingBox: Rect.zero,
            normalizedBox: const Rect.fromLTRB(0.47, 0.6, 0.53, 0.8),
            keypoints: [for (final k in pose(y)) Keypoint(k.dx, k.dy)],
            keypointConfidences: List.filled(17, 0.9),
          ),
        ], DateTime(2000).add(Duration(milliseconds: 33 * i)));
      }
    }

    court();
    whip();
    expect(s.match.hits, isEmpty);
    await s.closeVideo();
    court();
    whip();
    expect(s.match.hits, hasLength(1));
  });

  testWidgets('onResult runs on the time it is given', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: theme, home: const LivePage()));
    final s = tester.state(find.byType(LivePage)) as dynamic;
    // The page is pre-seeded under DEMO=true; start from a clean court.
    s.recalibrate();
    const corners = [Offset(0.3, 0.22), Offset(0.7, 0.22), Offset(0.96, 0.94), Offset(0.04, 0.94)];
    s.taps.addAll(corners);
    s.toCourt = Homography.fit(corners, courtCorners);
    s.toFrame = Homography.fit(courtCorners, corners);
    s.calibrating = false;
    YOLOResult person(double x) => YOLOResult(
      classIndex: 0,
      className: 'person',
      confidence: 0.9,
      boundingBox: Rect.zero,
      normalizedBox: Rect.fromLTRB(x - 0.03, 0.6, x + 0.03, 0.8),
    );
    final t0 = DateTime(2026);
    // Called within microseconds of wall time; only video time can give a speed.
    for (final (i, x) in [0.45, 0.5, 0.55].indexed) {
      s.onResult([person(x)], t0.add(Duration(milliseconds: 300 * i)));
    }
    expect(s.near.speed as double, greaterThan(0));
  });

  testWidgets('video mode replaces the camera and shows the clip whole', (tester) async {
    await openMockClip(tester);
    expect(find.byType(YOLOView), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    final box = tester.getSize(find.byType(RawImage));
    expect(box.width / box.height, closeTo(16 / 9, 0.01));
    expect(find.text('Tap the far-left corner'), findsOneWidget);
  });

  testWidgets('tap while playing pauses and takes no corner', (tester) async {
    final s = await openMockClip(tester);
    s.togglePlay();
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(RawImage)));
    expect(s.playing, isFalse);
    expect(s.taps, isEmpty);
  });

  testWidgets('frame and its time change together', (tester) async {
    final s = await openMockClip(tester);
    // A new frame must never appear with the old time, nor a new time with the old frame.
    final seen = <(int, Duration)>[];
    s.togglePlay();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      seen.add((identityHashCode(s.frame), s.frameTime as Duration));
    }
    // ...and the loop really advanced, or the check above passes on a stuck clip.
    expect(seen.map((e) => e.$2).toSet().length, greaterThan(1));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i].$1 != seen[i - 1].$1, seen[i].$2 != seen[i - 1].$2);
    }
  });

  testWidgets('closing the clip restores the camera court', (tester) async {
    final s = await openMockClip(
      tester,
      beforeOpen: (s) {
        s.recalibrate();
        s.taps.addAll(demoCorners);
        s.toCourt = Homography.fit(demoCorners, courtCorners);
        s.toFrame = Homography.fit(courtCorners, demoCorners);
        s.calibrating = false;
      },
    );
    await s.closeVideo();
    await tester.pump();
    expect(find.byType(YOLOView), findsOneWidget);
    expect(s.taps, hasLength(4));
    expect(s.calibrating, isFalse);
    expect(s.match.hits, isEmpty);
  });

  testWidgets('the video card fits a small phone at the largest text', (tester) async {
    phone(tester, const Size(375, 667), 1.3);
    final s = await openMockClip(tester);
    await setCourt(tester);
    s.match.hits.add(
      Hit(Side.near, DateTime(2000), const Offset(3, 10), Contact.overhead, 12, serve: true)
        ..type = ShotType.smash
        ..speedKmh = 139,
    );
    await playToEnd(tester, s);
    await tester.pump(const Duration(milliseconds: 400)); // the card has flipped
    expect(tester.takeException(), isNull);
    // On the last-shot card; HARDEST on the board shows the same number.
    final shot = find.descendant(of: find.byType(FlipCard), matching: find.text('~139 km/h'));
    expect(shot, findsOneWidget);
    // Its width on screen (so a FittedBox scale shows) against its own natural width
    // (which carries the letter spacing the page's text style adds).
    final natural = tester.renderObject<RenderBox>(shot).getMaxIntrinsicWidth(double.infinity);
    expect(natural, greaterThan(150)); // 22 sp at 1.3x
    expect(tester.getRect(shot).width, closeTo(natural, 1));
    expect(find.textContaining(' / '), findsOneWidget); // the time
    // The shot name keeps room to be read beside the speed.
    final name = find.descendant(of: find.byType(FlipCard), matching: find.text('SMASH'));
    expect(tester.getRect(name).width, greaterThanOrEqualTo(40));
    // ✕ sits in the top bar, right of HIT AT, at a full 48 dp and on screen.
    final close = tester.getRect(find.byTooltip('Back to the camera'));
    final hitAt = tester.getRect(
      find.ancestor(of: find.textContaining('HIT AT'), matching: find.byType(OutlinedButton)),
    );
    expect(close.left, greaterThanOrEqualTo(hitAt.right));
    expect(close.top, lessThan(hitAt.bottom));
    expect(close.right, lessThanOrEqualTo(375));
    expect(close.width >= 48 && close.height >= 48, isTrue);
    // The top bar at its widest chip, a two-digit rate.
    s.playRate = 88.8;
    s.playing = true;
    tester.element(find.byType(LivePage)).markNeedsBuild();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('~88.8× speed'), findsOneWidget);
  });

  testWidgets('a model error keeps the way back to the camera', (tester) async {
    final s = await openMockClip(tester);
    await setCourt(tester); // past the corner steps, whose card has its own ✕
    s.error = 'no model';
    tester.element(find.byType(LivePage)).markNeedsBuild();
    await tester.pump();
    expect(find.textContaining('did not load'), findsOneWidget);
    expect(find.byTooltip('Back to the camera'), findsOneWidget);
  });

  testWidgets('the speed chip waits for a measured rate', (tester) async {
    phone(tester, const Size(393, 852));
    final s = await openMockClip(tester, thumbValues: List.filled(40, 100));
    Future<void> playUntil(bool Function() done) async {
      for (var i = 0; !done() && i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(done(), isTrue);
    }

    // A setup play, to find the court, measures a rate of its own.
    s.togglePlay();
    await playUntil(() => s.playRate > 0);
    s.togglePlay();
    await tester.pump();
    await setCourt(tester); // the fourth corner starts counting
    await tester.pump();
    expect(s.playing, isTrue);
    expect(s.playRate, 0);
    expect(find.text('Playing'), findsOneWidget);
    await playUntil(() => s.playRate > 0);
    expect(find.textContaining('× speed'), findsOneWidget);
    // A new clip starts from no rate too.
    await tester.runAsync(() => s.openVideo('y.mp4') as Future<void>);
    expect(s.playRate, 0);
  });

  testWidgets('a cut hides the tags and shows the scrim', (tester) async {
    phone(tester, const Size(393, 852));
    // A far player on every counted frame; the court frame's thumb is 100, frames 2–4 a cut.
    final s = await openMockClip(
      tester,
      thumbValues: [100, 100, 200, 200, 200],
      people: [const Rect.fromLTRB(0.47, 0.15, 0.53, 0.3)],
    );
    await setCourt(tester);
    await playToEnd(tester, s);
    expect(s.offCourt, isTrue);
    expect(find.text('NOT THE COURT'), findsOneWidget);
    // P1 keeps the place before the cut, but neither ring nor tag is drawn. The cut's
    // first frame (the 2-in rule needs a second) was not counted: one point, not two.
    expect(s.far.pos, isNotNull);
    expect(s.far.trail, hasLength(1));
    expect(tester.renderObject(overlay), isNot(paintsIn(#drawRect, farColour)));
  });

  testWidgets('a hit on a clip fills the ring until its flash time', (tester) async {
    phone(tester, const Size(393, 852));
    final s = await openMockClip(tester, people: [const Rect.fromLTRB(0.47, 0.6, 0.53, 0.8)]);
    await setCourt(tester);
    await playToEnd(tester, s);
    final fill = paintsIn(#drawCircle, nearColour.withValues(alpha: 0.35));
    expect(tester.renderObject(overlay), paintsIn(#drawCircle, nearColour)); // P2's ring
    expect(tester.renderObject(overlay), isNot(fill));
    // Video time runs from DateTime(2000); the flash ends just after the frame on screen.
    final shown = DateTime(2000).add(s.frameTime as Duration);
    s.flashUntil[Side.near] = shown.add(const Duration(milliseconds: 1));
    expect(tester.renderObject(overlay), fill);
    // ...under a paper stroke, so no circle is drawn in P2's own colour.
    expect(tester.renderObject(overlay), isNot(paintsIn(#drawCircle, nearColour)));
    s.flashUntil[Side.near] = shown;
    expect(tester.renderObject(overlay), isNot(fill));
  });

  testWidgets('back on the court, the players start a fresh track', (tester) async {
    phone(tester, const Size(393, 852));
    // Off the court from frame 3, back on frame 6 (the third frame under the threshold).
    final s = await openMockClip(
      tester,
      thumbValues: [100, 100, 200, 200, 100, 100, 100],
      people: [const Rect.fromLTRB(0.47, 0.15, 0.53, 0.3)],
    );
    await setCourt(tester);
    await playToEnd(tester, s);
    expect(s.offCourt, isFalse);
    expect(find.text('NOT THE COURT'), findsNothing);
    // Seen on frames 1 and 6 (frame 2 is the cut's first, not counted); the cut forgot frame 1.
    expect(s.far.trail, hasLength(1));
  });

  testWidgets('a clip with no frame says so', (tester) async {
    await openMockClip(tester, thumbValues: []);
    await tester.pump();
    expect(find.text("That video can't be read"), findsOneWidget);
  });

  testWidgets('the app going inactive pauses the clip', (tester) async {
    final s = await openMockClip(tester, thumbValues: List.filled(40, 100));
    await setCourt(tester); // the fourth corner starts counting
    expect(s.playing, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(s.playing, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // A model error from the background is gone once the clip plays again.
    s.error = 'no model';
    s.togglePlay();
    expect(s.error, isNull);
    s.togglePlay();
  });

  testWidgets('the end of the clip names its last shot', (tester) async {
    final s = await openMockClip(tester);
    await setCourt(tester);
    final hit = Hit(Side.near, DateTime(2000), const Offset(3, 10), Contact.overhead, 12, serve: false);
    s.match.hits.add(hit);
    await playToEnd(tester, s);
    expect(hit.type, isNotNull); // live names it 3 s later; the clip has no later
  });

  testWidgets('a camera result that outlives the switch is dropped', (tester) async {
    final s = await openMockClip(tester);
    s.onResult([
      YOLOResult(
        classIndex: 0,
        className: 'person',
        confidence: 0.9,
        boundingBox: Rect.zero,
        normalizedBox: const Rect.fromLTRB(0.4, 0.6, 0.5, 0.8),
      ),
    ]);
    expect(s.feet, isEmpty);
  });

  testWidgets('opening or closing a clip drops a pending UNDO', (tester) async {
    final s = await openMockClip(tester);
    final messenger = ScaffoldMessenger.of(tester.element(find.byType(LivePage)));
    Future<void> pendingUndo() async {
      messenger.showSnackBar(const SnackBar(content: Text('stats reset')));
      await tester.pump();
      expect(find.text('stats reset'), findsOneWidget);
    }

    await pendingUndo();
    await tester.runAsync(() => s.openVideo('y.mp4') as Future<void>);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('stats reset'), findsNothing);
    await pendingUndo();
    await s.closeVideo();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('stats reset'), findsNothing);
  });

  testWidgets('a pick that fails says so', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: theme, home: const LivePage()));
    final s = tester.state(find.byType(LivePage)) as dynamic;
    const picker = MethodChannel('plugins.flutter.io/image_picker');
    var code = 'already_active';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      picker,
      (_) async => throw PlatformException(code: code),
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, null));
    // A second tap while the picker is up stays quiet: the first pick is still coming.
    await tester.runAsync(() => s.pickVideo() as Future<void>);
    await tester.pump();
    expect(find.text("That video can't be read"), findsNothing);
    code = 'invalid_image';
    await tester.runAsync(() => s.pickVideo() as Future<void>);
    await tester.pump();
    expect(find.text("That video can't be read"), findsOneWidget);
  });

  testWidgets('a play tap waits while another clip opens', (tester) async {
    final s = await openMockClip(tester);
    await tester.runAsync(() async {
      final open = s.openVideo('y.mp4') as Future<void>;
      s.togglePlay(); // the reader may already be on the new clip
      expect(s.playing, isFalse);
      await open;
    });
    await tester.pump();
    expect(s.frame, isNotNull);
    expect(s.playing, isFalse);
  });
}

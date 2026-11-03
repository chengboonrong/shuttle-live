import 'dart:io';
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
Future<dynamic> openMockClip(
  WidgetTester tester, {
  List<int>? thumbValues,
  List<Rect> people = const [],
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
        return {'durationUs': 2000000, 'width': 1920, 'height': 1080};
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
    expect(find.text('VIDEO'), findsOneWidget); // the top bar was measured too
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
    // P1 keeps the place the cut found them in, but neither ring nor tag is drawn.
    expect(s.far.pos, isNotNull);
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
    // Seen on frames 1, 2 and 6; the cut forgot the first two.
    expect(s.far.trail, hasLength(1));
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

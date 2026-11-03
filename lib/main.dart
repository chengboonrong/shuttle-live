import 'dart:math' as math;
import 'dart:ui' as ui show Image;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'analysis.dart';
import 'court.dart';
import 'video.dart';

/// Both platforms capture 4:3 frames and show them portrait, cropped to fill
/// the view (resizeAspectFill on iOS, FILL_CENTER on Android).
// ponytail: fixed frame shape; if the foot dots sit off the players on a phone, read the real frame size instead.
const frameAspect = 3 / 4;

// The umpire's flip scoreboard: black stand, steel frame, card-white cards.
const ink = Color(0xFF121212);
const raised = Color(0xFF1C1C1C);
const steel = Color(0xFF8A9099);
const paper = Color(0xFFF4F2EC);
const farColour = Color(0xFFD6342C);
const nearColour = Color(0xFF1F5FBF);
const cornerNames = ['far-left', 'far-right', 'near-right', 'near-left'];

/// Shot types with their own card under each count; the rest share one line.
const cardTypes = [
  ShotType.smash,
  ShotType.clear,
  ShotType.drop,
  ShotType.lift,
  ShotType.net,
  ShotType.drive,
];

/// Fills the board with made-up rallies, for screenshots:
/// flutter run --dart-define=DEMO=true
const demo = bool.fromEnvironment('DEMO');

TextStyle numerals(double size, [Color colour = ink]) => TextStyle(
  fontFamily: 'Archivo',
  fontWeight: FontWeight.w900,
  fontSize: size,
  height: 1,
  color: colour,
  fontFeatures: const [FontFeature.tabularFigures()],
);

TextStyle caps(double size, [Color colour = paper]) => TextStyle(
  fontFamily: 'Archivo Narrow',
  fontWeight: FontWeight.w700,
  fontSize: size,
  height: 1.15,
  letterSpacing: size * 0.1,
  color: colour,
);

TextStyle body(double size, [Color colour = paper, FontWeight weight = FontWeight.w500]) =>
    TextStyle(
      fontFamily: 'Archivo Narrow',
      fontWeight: weight,
      fontSize: size,
      height: 1.25,
      color: colour,
    );

/// m:ss, for a clip's time.
String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

final theme = ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'Archivo Narrow',
  scaffoldBackgroundColor: ink,
  colorScheme: const ColorScheme.dark(
    primary: paper,
    onPrimary: ink,
    secondary: steel,
    surface: raised,
    onSurface: paper,
    outline: steel,
    error: farColour,
  ),
  sliderTheme: const SliderThemeData(
    activeTrackColor: paper,
    inactiveTrackColor: Color(0xFF3A3D42),
    thumbColor: paper,
    activeTickMarkColor: ink,
    inactiveTickMarkColor: steel,
    valueIndicatorColor: paper,
    valueIndicatorTextStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: paper,
      side: const BorderSide(color: steel, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: caps(14),
      minimumSize: const Size(48, 48),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: paper,
      textStyle: caps(14),
      minimumSize: const Size(48, 48),
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: raised,
    showDragHandle: true,
    dragHandleColor: steel,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: paper,
    contentTextStyle: body(15, ink, FontWeight.w700),
    actionTextColor: ink,
  ),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light); // over the camera
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      // The board is a fixed panel; past 1.3x its labels no longer fit.
      builder: (context, child) =>
          MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: const LivePage(),
    ),
  );
}

/// One player's court position and movement, all in metres.
class Player {
  Player(this.side, this.colour);
  final Side side;
  final Color colour;
  final swing = SwingDetector();

  Offset? pos;
  int unseen = 0; // results in a row without this player
  Offset? _anchor;
  final _recent = <(DateTime, Offset)>[];
  final trail = <Offset>[];
  double distance = 0, speed = 0, topSpeed = 0;

  void update(Offset p, DateTime now) {
    unseen = 0;
    final last = pos;
    // A big jump means the track switched to someone else: restart, don't count it.
    final jump = last != null && (p - last).distance > 3;
    pos = last == null || jump ? p : Offset.lerp(last, p, 0.35)!;
    final cur = pos!;
    if (jump) {
      _anchor = cur;
      _recent.clear();
    }

    // Count distance in 20 cm steps so standing still adds nothing.
    final anchor = _anchor ??= cur;
    final step = (cur - anchor).distance;
    if (step > 0.2) {
      distance += step;
      _anchor = cur;
    }

    // Speed over the last half second.
    _recent.add((now, cur));
    _recent.removeWhere((e) => now.difference(e.$1).inMilliseconds > 500);
    final (t0, p0) = _recent.first;
    final dt = now.difference(t0).inMicroseconds / 1e6;
    if (dt > 0.25) {
      final v = (cur - p0).distance / dt;
      if (v < 9) {
        speed = v;
        topSpeed = math.max(topSpeed, v);
      }
    }

    trail.add(cur);
    if (trail.length > 240) trail.removeAt(0);
  }

  /// Where they stood nearest to [t] in the last half second; null when nothing is in it.
  Offset? posAt(DateTime t) => _recent.isEmpty
      ? null
      : _recent
            .reduce((a, b) => a.$1.difference(t).abs() <= b.$1.difference(t).abs() ? a : b)
            .$2;

  /// After a TV cut: forget where they were, keep what they did.
  void loseTrack() {
    pos = _anchor = null;
    _recent.clear();
    trail.clear();
    speed = 0;
    unseen = 0;
    swing.reset();
  }

  void reset() {
    loseTrack();
    distance = topSpeed = 0;
  }
}

/// A clip's racket sounds, each turned into a hit once the swings around it have been seen.
class SoundHits {
  SoundHits(List<Duration> sounds, DateTime base) : _times = [for (final s in sounds) base.add(s)];
  final List<DateTime> _times;
  int _next = 0; // the first sound not yet heard

  /// Hears every sound at least [soundWindow] before [now]; returns the sides of the hits it added.
  List<Side> hear(DateTime now, Player far, Player near, Match match, double threshold) {
    final sides = <Side>[];
    for (; _next < _times.length && !now.isBefore(_times[_next].add(soundWindow)); _next++) {
      final t = _times[_next];
      final f = far.swing.peakNear(t), n = near.swing.peakNear(t);
      final prev = match.hits.lastOrNull;
      final last = prev != null && t.difference(prev.time) <= Match.rallyGap ? prev.side : null;
      final side = soundHitter(f.swing, n.swing, last, threshold);
      if (side == null) continue; // nobody swung: a setup, a TV cut or another court's sound
      final (p, peak) = side == Side.far ? (far, f) : (near, n);
      final pos = p.posAt(t) ?? p.pos;
      if (pos != null && match.addHit(side, t, pos, peak.contact, peak.swing) != null) {
        sides.add(side);
      }
    }
    return sides;
  }
}

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final taps = <Offset>[]; // court corners in frame coordinates (0–1)
  Homography? toCourt, toFrame;
  bool calibrating = true;
  bool badCorners = false; // the last four taps did not make a court
  var far = Player(Side.far, farColour), near = Player(Side.near, nearColour);
  var match = Match();
  // ponytail: one swing threshold for everyone; tune on court with the slider.
  double threshold = 8; // wrist speed for a hit, torso lengths per second
  List<Offset> feet = []; // every detected person's feet, frame coordinates
  double fps = 0;
  String? error;
  Size viewSize = Size.zero;
  // Our own controller: the view's built-in one resets the threshold to 0.25 when it attaches.
  // The plugin's boxes, labels and skeletons are off; the overlay tags the two players itself.
  final camera = YOLOViewController()
    ..setConfidenceThreshold(0.35)
    ..setShowOverlays(false);

  // Video mode: a saved clip in place of the camera.
  VideoClip? clip; // null: the live camera
  SoundHits? _sounds; // a clip with sound: its hits are timed by the racket, not the wrist
  bool playing = false;
  ui.Image? frame; // the clip frame on screen
  Duration frameTime = Duration.zero;
  Uint8List? _thumb; // the thumbnail of the frame on screen
  CutDetector? _cut; // from the frame the court was tapped on
  bool offCourt = false; // a TV cut is on screen: nothing is counted
  final flashUntil = <Side, DateTime>{}; // a clip's hit flash, in video time
  double playRate = 0; // video seconds per wall second, smoothed
  DateTime? _shownAt; // wall time of the last frame shown while playing
  YOLO? _yolo;
  late final AppLifecycleListener _lifecycle;
  int _run = 0; // bumped to end the play loop: a pause, ✕ or another clip
  int? _opening; // the _run of an open still waiting for its first frame
  ({List<Offset> taps, Homography? toCourt, Homography? toFrame, bool calibrating})? _cameraCourt;
  // A clip runs on its own time from a fixed base, so speeds and rally gaps follow the video.
  static final _videoBase = DateTime(2000);

  @override
  void initState() {
    super.initState();
    // A backgrounded app loses the decoder, and a clip can't seek back: stop on the way out.
    _lifecycle = AppLifecycleListener(onInactive: () {
      if (playing) togglePlay();
    });
    if (demo) seedDemo();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    closeVideo();
    camera.dispose();
    super.dispose();
  }

  /// Where the 0–1 frame sits on screen: the camera's after its fill-and-crop,
  /// or the whole box for a clip, which is shown uncropped.
  Rect get frameRect {
    final w = viewSize.width, h = viewSize.height, aspect = clip?.aspect ?? frameAspect;
    final shown = w / h > aspect ? Size(w, w / aspect) : Size(h * aspect, h);
    return Rect.fromLTWH(
      (w - shown.width) / 2,
      (h - shown.height) / 2,
      shown.width,
      shown.height,
    );
  }

  Offset toScreen(Offset f) =>
      frameRect.topLeft + Offset(f.dx * frameRect.width, f.dy * frameRect.height);

  Offset toFrameCoords(Offset s) => Offset(
    (s.dx - frameRect.left) / frameRect.width,
    (s.dy - frameRect.top) / frameRect.height,
  );

  void onTap(TapUpDetails d) {
    if (!calibrating) return;
    // Corners are only taken on a still frame.
    if (clip != null && playing) {
      togglePlay();
      return;
    }
    setState(() {
      badCorners = false;
      taps.add(toFrameCoords(d.localPosition));
      if (taps.length == 4) {
        try {
          toCourt = Homography.fit(taps, courtCorners);
          toFrame = Homography.fit(courtCorners, taps);
          calibrating = false;
          if (clip != null) {
            _cut = CutDetector(_thumb!);
            playRate = 0; // the setup play only decoded, so its rate says nothing
          }
        } on ArgumentError {
          taps.clear();
          badCorners = true;
        }
      }
    });
    // Counting starts from the frame the corners were tapped on.
    if (clip != null && !calibrating) togglePlay();
  }

  void resetStats() {
    far.reset();
    near.reset();
    match.reset();
    flashUntil.clear();
  }

  void _clearCourt() {
    taps.clear();
    toCourt = toFrame = null;
    calibrating = true;
    badCorners = false;
    offCourt = false;
    resetStats();
  }

  void recalibrate() {
    if (playing) togglePlay(); // a clip's court is tapped on a still frame
    setState(_clearCourt);
  }

  /// Opens a clip from the photo library; a cancel does nothing.
  Future<void> pickVideo() async {
    XFile? file;
    try {
      file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } on PlatformException catch (e) {
      // A second tap while the picker is up: the first pick is still on its way.
      if (mounted && e.code != 'already_active') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That video can't be read")),
        );
      }
      return;
    }
    if (file != null) await openVideo(file.path);
  }

  /// Swaps the camera for the clip at [path], paused on its first frame, with
  /// fresh stats and no court. The camera's court is kept for the way back.
  Future<void> openVideo(String path) async {
    final run = ++_run; // ends the loop on any clip before
    // Until the new clip shows, play/pause would read its frames as the old one's.
    _opening = run;
    VideoClip? opened;
    try {
      opened = await VideoFrames.open(path);
    } on PlatformException {
      // Unreadable: said below.
    }
    if (run != _run || !mounted) return;
    if (opened != null) {
      final sounds = opened.sounds;
      setState(() {
        if (clip == null) {
          _cameraCourt = (
            taps: [...taps],
            toCourt: toCourt,
            toFrame: toFrame,
            calibrating: calibrating,
          );
        }
        clip = opened;
        _sounds = sounds == null ? null : SoundHits(sounds, _videoBase);
        playing = false;
        _shownAt = null;
        playRate = 0;
        frame?.dispose();
        frame = null;
        _cut = null;
        feet = [];
        error = null; // the camera's; the clip loads the model itself
        _clearCourt();
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar(); // its UNDO would mix timelines
      _yolo ??= YOLO(modelPath: 'yolo26n-pose', task: YOLOTask.pose);
      await _step(run);
      if (run != _run || !mounted) return;
    }
    _opening = null;
    if (opened != null && frame != null) return;
    // Not a video, or not one frame in it. Close first: closing hides the current SnackBar.
    if (clip != null) await closeVideo();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("That video can't be read")),
    );
  }

  /// Plays or pauses the clip. A pause stops decoding, so video time stands still.
  void togglePlay() {
    if (_opening == _run) return; // the reader may already be on the next clip
    final run = ++_run; // a pause ends the loop; a frame still being read is dropped
    _shownAt = null; // the rate restarts, so a pause never counts as slow playback
    setState(() {
      playing = !playing;
      if (playing) error = null; // a stale model error from before a pause
    });
    if (playing) _play(run);
  }

  Future<void> _play(int run) async {
    while (await _step(run)) {}
  }

  /// Reads the next frame and, once the court is set, finds the people in it;
  /// then shows the frame and its results in one build. False at the end of
  /// the clip, or once a pause, ✕ or another clip has taken over.
  Future<bool> _step(int run) async {
    // Belt and braces: a read that fails ends the clip like its last frame.
    final f = await VideoFrames.next().catchError((_) => null);
    if (run != _run) return false;
    if (f == null) {
      setState(() {
        playing = false;
        if (!calibrating) {
          // No later frame comes to settle the last sounds: hear them on the swings seen so far.
          _sounds?.hear(_videoBase.add(frameTime + soundWindow), far, near, match, threshold);
          // Live names the last shot 3 s later; the clip's end must too.
          match.tick(_videoBase.add(frameTime + Match.rallyGap * 2));
        }
      });
      return false;
    }
    final image = await decodeImageFromList(f.jpeg);
    // Once the court is set, a frame that isn't the court (a TV cut) shows but isn't counted.
    final counting = run == _run && _cut != null && !calibrating;
    final off = counting && _cut!.update(f.thumb);
    // The detector needs 2 frames to call a cut; the first one is already not the court.
    final cutFrame = counting && thumbDiff(f.thumb, _cut!.reference) > cutThreshold;
    List<YOLOResult>? results;
    if (counting && !off && !cutFrame) {
      try {
        final out = await _yolo!.predict(f.jpeg, confidenceThreshold: 0.35);
        results = [for (final d in out['detections'] as List) YOLOResult.fromMap(d as Map)];
      } catch (e) {
        image.dispose();
        if (run == _run) {
          setState(() {
            playing = false;
            error = '$e';
          });
        }
        return false;
      }
    }
    if (run != _run) {
      image.dispose();
      return false;
    }
    final now = _videoBase.add(f.time);
    setState(() {
      final wall = DateTime.now();
      if (_shownAt case final t? when wall.isAfter(t)) {
        final rate = (f.time - frameTime).inMicroseconds / wall.difference(t).inMicroseconds;
        playRate = playRate == 0 ? rate : playRate + 0.2 * (rate - playRate);
      }
      _shownAt = wall;
      frame?.dispose();
      frame = image;
      frameTime = f.time;
      _thumb = f.thumb;
      if (counting) {
        // Back from a cut: where they stood before it says nothing about now.
        if (offCourt && !off) {
          far.loseTrack();
          near.loseTrack();
        }
        offCourt = off;
      }
      if (off) {
        feet = [];
        match.tick(now); // a rally that stops at a cut still ends and gets named
      } else if (results != null) {
        onResult(results, now);
      }
    });
    return true;
  }

  /// Back to the live camera and its own court, with fresh stats.
  Future<void> closeVideo() async {
    _run++; // ends the play loop, or an openVideo still waiting on the channel
    if (clip == null) return;
    // Fields now, setState last: dispose() calls this too.
    final yolo = _yolo;
    _yolo = null;
    clip = null;
    _sounds = null;
    playing = false;
    frame?.dispose();
    frame = null;
    _thumb = null;
    _cut = null;
    offCourt = false;
    feet = [];
    error = null; // the clip's; the camera loads the model itself
    resetStats();
    final court = _cameraCourt!;
    _cameraCourt = null;
    taps
      ..clear()
      ..addAll(court.taps);
    toCourt = court.toCourt;
    toFrame = court.toFrame;
    calibrating = court.calibrating;
    badCorners = false;
    await VideoFrames.close();
    // After the first await: dispose() reaches here unmounted, and has no context to use.
    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar(); // its UNDO would mix timelines
    await yolo?.dispose();
    if (mounted) setState(() {});
  }

  /// Made-up rallies played through the real analysis, so the full board can
  /// be seen without a court.
  void seedDemo() {
    taps.addAll(const [
      Offset(0.3, 0.22),
      Offset(0.7, 0.22),
      Offset(0.96, 0.94),
      Offset(0.04, 0.94),
    ]);
    toCourt = Homography.fit(taps, courtCorners);
    toFrame = Homography.fit(courtCorners, taps);
    calibrating = false;
    final rnd = math.Random(4);
    var t = DateTime.now().subtract(const Duration(minutes: 6));
    for (var rally = 0; rally < 5; rally++) {
      var side = rally.isEven ? Side.far : Side.near;
      for (var shot = 0, n = 4 + rnd.nextInt(8); shot < n; shot++) {
        final p = side == Side.far ? far : near;
        final to = Offset(
          0.4 + rnd.nextDouble() * 5.3,
          side == Side.far ? 0.6 + rnd.nextDouble() * 5.6 : 7.2 + rnd.nextDouble() * 5.6,
        );
        final from = p.pos ?? to;
        for (var k = 1; k <= 12; k++) {
          p.update(
            Offset.lerp(from, to, k / 12)!,
            t.subtract(Duration(milliseconds: 40 * (12 - k))),
          );
        }
        match.addHit(side, t, p.pos!, Contact.values[rnd.nextInt(3)], 6 + rnd.nextDouble() * 18);
        t = t.add(Duration(milliseconds: 500 + rnd.nextInt(1100)));
        side = side == Side.far ? Side.near : Side.far;
      }
      t = t.add(const Duration(seconds: 5));
      match.tick(t);
    }
  }

  /// Reads one frame of people. [at] is the frame's own time (video playback);
  /// the live camera leaves it out and gets the wall clock.
  void onResult(List<YOLOResult> results, [DateTime? at]) {
    if (at == null && clip != null) return; // a camera result that outlived the switch
    final now = at ?? DateTime.now();
    final h = toCourt;
    YOLOResult? bestFar, bestNear;
    Offset? farPos, nearPos;
    final found = <Offset>[];
    for (final r in results) {
      final b = r.normalizedBox;
      final foot = Offset(b.center.dx, b.bottom);
      found.add(foot);
      if (h == null) continue;
      final c = h.map(foot);
      // Ignore people well outside the court (spectators, next court).
      if (c.dx < -1 || c.dx > courtWidth + 1 || c.dy < -2 || c.dy > courtLength + 2) {
        continue;
      }
      if (c.dy < netY) {
        if (bestFar == null || r.confidence > bestFar.confidence) {
          bestFar = r;
          farPos = c;
        }
      } else if (bestNear == null || r.confidence > bestNear.confidence) {
        bestNear = r;
        nearPos = c;
      }
    }
    setState(() {
      feet = found;
      final swings = <(Player, ({DateTime time, Contact contact, double swing}))>[];
      for (final (p, r, c) in [(far, bestFar, farPos), (near, bestNear, nearPos)]) {
        if (c != null) {
          p.update(c, now);
        } else {
          p.unseen++;
        }
        final kp = r?.keypoints, conf = r?.keypointConfidences;
        // An unseen player still gets a frame, so a swing in progress ends now.
        final s = c == null || kp == null || conf == null
            ? p.swing.update(const [], const [], now, threshold)
            : p.swing.update([for (final k in kp) Offset(k.x, k.y)], conf, now, threshold);
        if (s != null && p.pos != null) swings.add((p, s));
      }
      final hitters = <Side>[];
      if (_sounds case final sounds?) {
        // A clip with sound: the swings only say who hit at each racket sound.
        hitters.addAll(sounds.hear(now, far, near, match, threshold));
      } else {
        swings.sort((a, b) => a.$2.time.compareTo(b.$2.time));
        for (final (p, s) in swings) {
          if (match.addHit(p.side, s.time, p.pos!, s.contact, s.swing) != null) hitters.add(p.side);
        }
      }
      // On a clip the tag flashes HIT for half a second of video time; live is unchanged.
      if (clip != null) {
        for (final side in hitters) {
          flashUntil[side] = now.add(const Duration(milliseconds: 500));
        }
      }
      match.strongSwing = threshold * 2;
      match.tick(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            // A clip starts below the status bar, so its top edge (often the far corners)
            // shows and takes taps; the camera still runs up under it. This also keeps the
            // top bar's own SafeArea from padding twice.
            child: SafeArea(
              top: clip != null,
              bottom: false,
              left: false,
              right: false,
              child: LayoutBuilder(
              builder: (context, box) {
                if (clip case final c?) {
                  // The whole clip, never cropped: the largest box of its shape that fits.
                  final w = math.min(box.maxWidth, box.maxHeight * c.aspect);
                  viewSize = Size(w, w / c.aspect);
                } else {
                  // Never taller than the 3:4 frame, so its sides (and the court's
                  // corners) are never cut off; spare height goes above the board.
                  viewSize = Size(box.maxWidth, math.min(box.maxHeight, box.maxWidth / frameAspect));
                }
                return SizedBox.fromSize(
                  size: viewSize,
                  child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Out of the tree in video mode, which turns the camera off.
                    if (clip == null)
                      YOLOView(
                        modelPath: 'yolo26n-pose',
                        task: YOLOTask.pose,
                        controller: camera,
                        // The default stream leaves keypoints out, and the swing detector needs them.
                        streamingConfig: const YOLOStreamingConfig(includePoses: true),
                        onResult: (r) => onResult(r),
                        onPerformanceMetrics: (m) => setState(() => fps = m.fps),
                        onModelError: (e, _, _) => setState(() => error = '$e'),
                      )
                    else
                      RawImage(image: frame, fit: BoxFit.fill),
                    // Corners set on the full frame can fall outside the camera once it
                    // shrinks for the board; clip the drawing, not the native view.
                    ClipRect(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: onTap,
                        child: CustomPaint(painter: _OverlayPainter(this)),
                      ),
                    ),
                    // A TV cut: the picture dims and says counting has stopped.
                    if (offCourt)
                      ColoredBox(
                        color: ink.withValues(alpha: 0.55),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: ink,
                              border: Border.all(color: steel, width: 2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('NOT THE COURT', style: caps(15)),
                                const SizedBox(height: 2),
                                Text('Counting paused', style: body(14, steel)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      top: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(padding: const EdgeInsets.only(top: 8), child: topBar()),
                      ),
                    ),
                  ],
                ),
                );
              },
            ),
            ),
          ),
          SafeArea(top: false, child: board()),
        ],
      ),
    );
  }

  Widget topBar() {
    // A clip's way back, once its court is set; a model error must not hide it.
    final close = clip == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message: 'Back to the camera',
              child: OutlinedButton(
                onPressed: closeVideo,
                style: OutlinedButton.styleFrom(
                  backgroundColor: ink.withValues(alpha: 0.85),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.close),
              ),
            ),
          );
    if (error case final e?) {
      final box = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: farColour, borderRadius: BorderRadius.circular(6)),
        // 19 sp bold is large text, so card white on red passes 3:1; smaller text would need 4.5:1.
        child: Text('The pose model did not load: $e', style: body(19, paper, FontWeight.w700)),
      );
      if (close == null) return box;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: box), close],
      );
    }
    // The corner steps sit on the board, so nothing covers the court's far corners.
    if (calibrating) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.85),
            border: Border.all(color: steel),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: clip == null
                ? [
                    Text(fps > 0 ? '${fps.round()} FPS' : 'CAMERA STARTING', style: caps(12)),
                    Text(
                      'Swing ${far.swing.speed.round()} far · ${near.swing.speed.round()} near',
                      style: body(12, steel),
                    ),
                  ]
                : [
                    Text('VIDEO', style: caps(12)),
                    // A clip plays as fast as the phone analyses it, so the rate is an estimate.
                    // No number until two frames have been timed.
                    Text(
                      !playing
                          ? 'Paused'
                          : playRate > 0
                          ? '~${playRate.toStringAsFixed(1)}× speed'
                          : 'Playing',
                      style: body(12, steel),
                    ),
                  ],
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: openSettings,
          style: OutlinedButton.styleFrom(backgroundColor: ink.withValues(alpha: 0.85)),
          icon: const Icon(Icons.tune, size: 18),
          label: Text('HIT AT ${threshold.round()}'),
        ),
        ?close,
      ],
    );
  }

  // A clip's own controls: both on the corner-step card, then play/pause on the
  // last-shot card and ✕ in the top bar.
  Widget playButton() => IconButton.filled(
    onPressed: togglePlay,
    style: IconButton.styleFrom(backgroundColor: ink, foregroundColor: paper),
    tooltip: playing ? 'Pause' : 'Play',
    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
  );

  Widget closeButton() => IconButton(
    onPressed: closeVideo,
    color: ink,
    tooltip: 'Back to the camera',
    icon: const Icon(Icons.close),
  );

  Widget cornerStep() => Row(
    children: [
      // A clip can play during setup, to find a frame that shows the court.
      if (clip != null) playButton(),
      SizedBox(
        width: 52,
        child: Center(child: Text('${taps.length + 1}', style: numerals(40))),
      ),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              badCorners
                  ? "Those corners don't make a court"
                  : 'Tap the ${cornerNames[taps.length]} corner',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(17, ink, FontWeight.w700),
            ),
            Text(
              badCorners
                  ? 'Start again at far-left · 1 of 4'
                  : 'Outer doubles lines · ${taps.length + 1} of 4',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(13, const Color(0xFF4A4F57)),
            ),
          ],
        ),
      ),
      if (taps.isNotEmpty)
        TextButton(
          onPressed: () => setState(() {
            taps.removeLast();
          }),
          style: TextButton.styleFrom(foregroundColor: ink),
          child: const Text('UNDO'),
        )
      // The court isn't kept between launches, so a clip can be opened before it is set.
      else if (clip == null)
        TextButton(
          onPressed: pickVideo,
          style: TextButton.styleFrom(foregroundColor: ink),
          child: const Text('VIDEO'),
        ),
      if (clip != null) closeButton(),
    ],
  );

  void clearStats() {
    final (oldFar, oldNear, oldMatch) = (far, near, match);
    setState(() {
      far = Player(Side.far, farColour);
      near = Player(Side.near, nearColour);
      match = Match();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Stats cleared'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => setState(() {
            far = oldFar;
            near = oldNear;
            match = oldMatch;
          }),
        ),
      ),
    );
  }

  void openSettings() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HIT SENSITIVITY', style: caps(15)),
              const SizedBox(height: 6),
              Text(
                'A swing counts as a hit when the wrist moves faster than this. '
                'Lower it if soft shots are missed; raise it if practice swings count.',
                style: body(14, steel),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: threshold,
                      min: 4,
                      max: 16,
                      divisions: 12,
                      label: '${threshold.round()}',
                      onChanged: (v) {
                        setState(() => threshold = v);
                        setSheet(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${threshold.round()}',
                      textAlign: TextAlign.end,
                      style: numerals(24, paper),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Setting the court again clears the stats.', style: body(14, steel)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      pickVideo();
                    },
                    child: const Text('ANALYSE A VIDEO'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      recalibrate();
                    },
                    child: const Text('SET COURT AGAIN'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      clearStats();
                    },
                    child: const Text('RESET STATS'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget board() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: steel, width: 3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: playerColumn(far, 'FAR')),
              const SizedBox(width: 8),
              SizedBox(width: 64, child: calibrating ? null : rallyColumn()),
              const SizedBox(width: 8),
              Expanded(child: playerColumn(near, 'NEAR')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 60, child: lastShot()),
      ],
    ),
  );

  Widget playerColumn(Player p, String name) {
    final mine = match.hits.where((h) => h.side == p.side).toList();
    final counts = <ShotType, int>{};
    for (final h in mine) {
      if (h.type case final t?) counts[t] = (counts[t] ?? 0) + 1;
    }
    final best = mine.map((h) => h.speedKmh).nonNulls.fold<double?>(
      null,
      (a, b) => a == null ? b : math.max(a, b),
    );
    final others = [
      for (final t in ShotType.values)
        if (!cardTypes.contains(t) && counts[t] != null) '${counts[t]} ${t.label.toLowerCase()}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 19 sp bold is large text, so card white on the side colours passes 3:1.
        Container(
          height: 28,
          alignment: Alignment.center,
          color: p.colour,
          child: Text(name, style: caps(19)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 92,
          child: FlipCard(
            value: mine.length,
            hinge: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 5),
              child: Column(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${mine.length}', style: numerals(64)),
                    ),
                  ),
                  // Shot totals, so the two cards never read as a score.
                  Text('SHOTS', style: caps(10.5, const Color(0xFF4A4F57))),
                ],
              ),
            ),
          ),
        ),
        // Until the court is set everything below reads 0 or –, and the camera
        // needs the height to show the whole frame for the corner taps.
        if (!calibrating) ...[
        const SizedBox(height: 4),
        for (final row in [cardTypes.sublist(0, 3), cardTypes.sublist(3)]) ...[
          Row(
            spacing: 4,
            children: [
              for (final t in row) Expanded(child: typeCard(t, counts[t] ?? 0)),
            ],
          ),
          const SizedBox(height: 4),
        ],
        // Always two lines tall, so the board (and the camera above it) never jumps.
        Stack(
          children: [
            Text(' \n ', style: body(12, steel)),
            Text(
              others.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: body(12, steel),
            ),
          ],
        ),
        stat('RUN', p.distance == 0 ? '–' : '~${p.distance.round()} m'),
        // Short labels: at 1.3x text a 375–411 dp column has ~50 dp beside "~139 km/h".
        stat('SPRINT', p.topSpeed == 0 ? '–' : '~${(p.topSpeed * 3.6).round()} km/h'),
        stat('HARDEST', best == null ? '–' : '~${best.round()} km/h'),
        ],
      ],
    );
  }

  Widget typeCard(ShotType t, int n) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
    decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(3)),
    child: Column(
      children: [
        Text('$n', style: numerals(15)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(t.label.toUpperCase(), style: caps(11, ink)),
        ),
      ],
    ),
  );

  Widget stat(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        // Shrinks rather than cuts: "BEST …" would no longer say which speed it is.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, style: caps(10.5, steel)),
          ),
        ),
        const SizedBox(width: 4),
        Text(value, style: body(13, paper, FontWeight.w700)),
      ],
    ),
  );

  Widget rallyColumn() {
    final shots = match.rallyShots;
    return Column(
      children: [
        Text('RALLY', style: caps(10.5, steel)),
        const SizedBox(height: 2),
        Text('${match.rallies}', style: numerals(24, paper)),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: courtWidth / courtLength,
          child: CustomPaint(painter: MiniCourtPainter(far, near, match)),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('$shots IN RALLY', style: caps(10.5)),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('LONGEST ${match.longestRally}', style: caps(10.5, steel)),
        ),
        const SizedBox(height: 22),
        // Sits level with the RUN and speed lines on both sides, which carry only the ~.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('~ = ESTIMATE', style: caps(10.5, steel)),
        ),
      ],
    );
  }

  Widget lastShot() {
    if (calibrating) {
      return FlipCard(value: (taps.length, badCorners), child: cornerStep());
    }
    // A shot is named when its reply lands, so show the newest named one.
    final last = match.hits.where((h) => h.type != null).lastOrNull ?? match.hits.lastOrNull;
    final speed = last?.speedKmh;
    final c = clip;
    // A clip's time goes under the side tag: beside the speed the row would run past a
    // 375 dp phone at 1.3x even with no shot name. It flips with the card, but both cards
    // show the same m:ss.
    final time = c == null
        ? null
        : Text(
            '${_clock(frameTime)} / ${_clock(c.duration)}',
            style: body(12, const Color(0xFF4A4F57), FontWeight.w700),
          );
    final card = FlipCard(
      value: last == null ? 'waiting' : (last, last.type),
      child: last == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Waiting for the first hit', style: body(17, ink, FontWeight.w700)),
                ?time,
              ],
            )
          : Padding(
              // On a clip, play/pause takes the 48 dp on the left. A narrow right edge
              // keeps the shot name 40 dp at 375 dp and 1.3x beside the speed.
              padding: c == null
                  ? const EdgeInsets.fromLTRB(10, 8, 14, 4)
                  : const EdgeInsets.fromLTRB(52, 4, 8, 3),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        color: last.side == Side.far ? farColour : nearColour,
                        child: Text(last.side == Side.far ? 'FAR' : 'NEAR', style: caps(19)),
                      ),
                      ?time,
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        (last.type?.label ?? 'Hit').toUpperCase(),
                        style: numerals(34),
                      ),
                    ),
                  ),
                  if (speed != null)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('~${speed.round()} km/h', style: numerals(22)),
                        Text('ESTIMATE', style: caps(10, const Color(0xFF4A4F57))),
                      ],
                    ),
                ],
              ),
            ),
    );
    if (c == null) return card;
    // The controls and the progress line stay put while the card flips under them.
    return Stack(
      fit: StackFit.expand,
      children: [
        card,
        Align(alignment: Alignment.centerLeft, child: playButton()),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 3,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (frameTime.inMicroseconds / math.max(1, c.duration.inMicroseconds))
                  .clamp(0.0, 1.0),
              child: const ColoredBox(color: ink),
            ),
          ),
        ),
      ],
    );
  }
}

/// A ring-bound scoreboard card. When [value] changes, the new card falls
/// over the top rings onto the old one.
class FlipCard extends StatelessWidget {
  const FlipCard({super.key, required this.value, required this.child, this.hinge = false});
  final Object value;
  final Widget child;
  final bool hinge; // the fold line across a number card; it would strike through words

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: Duration(milliseconds: still ? 0 : 280),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (card, t) => card.key != ValueKey(value)
          ? card // the old card stays put under the falling one
          : AnimatedBuilder(
              animation: t,
              child: card,
              builder: (context, card) => Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002)
                  ..rotateX(-(1 - t.value) * math.pi / 2),
                child: card,
              ),
            ),
      child: DecoratedBox(
        key: ValueKey(value),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 4),
          ],
        ),
        child: Stack(
          children: [
            if (hinge)
              Center(child: Container(height: 1.5, color: ink.withValues(alpha: 0.25))),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [for (var i = 0; i < 2; i++) const _Ring()],
                ),
              ),
            ),
            Center(child: child),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring();

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(color: Color(0xFF3A3D42), shape: BoxShape.circle),
  );
}

/// Draws the tapped court, each person's feet and the P1/P2 tags over the camera.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.s);
  final _LivePageState s;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = paper
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final pts = s.taps.map(s.toScreen).toList();
    if (pts.length > 1) {
      canvas.drawPath(Path()..addPolygon(pts, pts.length == 4), line);
    }
    final toFrame = s.toFrame;
    if (toFrame != null) {
      canvas.drawLine(
        s.toScreen(toFrame.map(const Offset(0, netY))),
        s.toScreen(toFrame.map(const Offset(courtWidth, netY))),
        line..strokeWidth = 4,
      );
    }
    if (s.calibrating) {
      for (final (i, p) in pts.indexed) {
        canvas.drawCircle(p, 11, Paint()..color = paper);
        final label = TextPainter(
          text: TextSpan(text: '${i + 1}', style: numerals(13)),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, p - Offset(label.width / 2, label.height / 2));
        label.dispose();
      }
    }
    for (final f in s.feet) {
      canvas.drawCircle(s.toScreen(f), 4, Paint()..color = steel);
    }
    // Nobody is tagged on a TV cut: the scrim says counting has stopped.
    if (toFrame != null && !s.offCourt) {
      final shown = _LivePageState._videoBase.add(s.frameTime);
      for (final (p, tag) in [(s.far, 'P1'), (s.near, 'P2')]) {
        // ~1 s unseen: drop the ring and tag rather than leave them where the player left the frame.
        if (p.pos case final pos? when p.unseen < 30) {
          final at = s.toScreen(toFrame.map(pos));
          // A hit on a clip: the ring fills under a card-white edge and the tag says HIT.
          final flash = s.flashUntil[p.side]?.isAfter(shown) ?? false;
          if (flash) canvas.drawCircle(at, 10, Paint()..color = p.colour.withValues(alpha: 0.35));
          canvas.drawCircle(
            at,
            10,
            Paint()
              ..color = flash ? paper : p.colour
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
          // 19 sp Archivo Black is large text, so card white clears 3:1 on red as on the error banner.
          final label = TextPainter(
            text: TextSpan(text: flash ? '$tag HIT' : tag, style: numerals(19, paper)),
            textDirection: TextDirection.ltr,
          )..layout();
          final chip = Size(label.width + 12, label.height + 8);
          // Under the feet ring, or over it when that would run off the camera.
          final top = at.dy + 14 + chip.height <= size.height ? at.dy + 14 : at.dy - 14 - chip.height;
          final left = (at.dx - chip.width / 2).clamp(0.0, size.width - chip.width);
          final box = Offset(left, top) & chip;
          canvas.drawRect(box, Paint()..color = p.colour);
          label.paint(canvas, box.topLeft + const Offset(6, 4));
          label.dispose();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}

/// Top-down court: players, their recent paths, and where each shot was hit.
class MiniCourtPainter extends CustomPainter {
  MiniCourtPainter(this.far, this.near, this.match);
  final Player far, near;
  final Match match;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / courtWidth;
    Offset at(Offset m) => Offset(m.dx * k, m.dy * k);
    final line = Paint()
      ..color = steel
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, line);
    for (final y in [netY - 1.98, netY + 1.98]) {
      canvas.drawLine(at(Offset(0, y)), at(Offset(courtWidth, y)), line);
    }
    for (final (a, b) in [(0.0, netY - 1.98), (netY + 1.98, courtLength)]) {
      canvas.drawLine(at(Offset(courtWidth / 2, a)), at(Offset(courtWidth / 2, b)), line);
    }
    canvas.drawLine(
      at(const Offset(0, netY)),
      at(const Offset(courtWidth, netY)),
      Paint()
        ..color = paper
        ..strokeWidth = 2,
    );

    // Where the last 40 shots were hit from, newest brightest.
    final shots = match.hits.length > 40
        ? match.hits.sublist(match.hits.length - 40)
        : match.hits;
    for (final (i, h) in shots.indexed) {
      final c = h.side == Side.far ? farColour : nearColour;
      canvas.drawCircle(
        at(h.pos),
        2.5,
        Paint()..color = c.withValues(alpha: 0.3 + 0.7 * (i + 1) / shots.length),
      );
    }
    final lastShot = match.hits.where((h) => h.to != null).lastOrNull;
    if (lastShot != null) {
      canvas.drawLine(
        at(lastShot.pos),
        at(lastShot.to!),
        Paint()
          ..color = paper
          ..strokeWidth = 1.5,
      );
    }

    for (final p in [far, near]) {
      if (p.trail.length > 1) {
        canvas.drawPoints(
          PointMode.polygon,
          p.trail.map(at).toList(),
          Paint()
            ..color = p.colour.withValues(alpha: 0.45)
            ..strokeWidth = 1.2,
        );
      }
      if (p.pos case final pos?) {
        canvas.drawCircle(at(pos), 4.5, Paint()..color = p.colour);
        canvas.drawCircle(
          at(pos),
          4.5,
          Paint()
            ..color = paper
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MiniCourtPainter old) => true;
}

# Video Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pick a saved TV clip, tap its court, and watch Shuttle Live analyse it frame by frame with the same pipeline and board as the live camera.

**Architecture:**
- A small native frame reader in the Runner app (AVAssetReader on iOS, MediaMetadataRetriever on Android) hands Dart one frame at a time. Each frame comes with a JPEG, its video timestamp and a 32×18 gray thumbnail.
- Dart runs the plugin's single-image `predict()` on the JPEG. It then shows the frame and its results in one build and feeds the existing `onResult` with video time.
- A pure-Dart `CutDetector` compares thumbnails against the court frame to pause counting on TV cuts.

**Tech Stack:**
- Flutter 3.38 (`fvm flutter`), with `ultralytics_yolo` vendored at `third_party/ultralytics_yolo`.
- `image_picker` 1.x.
- Swift with AVFoundation and CoreImage; Kotlin with MediaMetadataRetriever.

**Spec:** `docs/superpowers/specs/2026-11-03-video-analysis-design.md`. Read it first; this plan argues from it.

**No commits:** `~/shuttle-live` is not a git repo, so tasks end with a check, not a commit.

## Global Constraints

- Run everything through `fvm flutter`. The project is not under git.
- The pose model is `yolo26n-pose`, AGPL: private testing only. No APK or Drive upload unless the owner asks.
- Android is built but reported "unchecked". Never run anything on an Android emulator.
- The live camera is unchanged: 1× lens, `setShowOverlays(false)`, confidence 0.35. No plugin boxes, labels or skeletons anywhere.
- Every speed keeps its "~" prefix. Nothing may read as a match score.
- Controls are Material, using the existing theme helpers in `lib/main.dart` (`caps`, `body`, `numerals`, `ink`, `paper`, `steel`, `farColour`, `nearColour`).
- No seeking, speed controls, export or audio.
- On the iPhone, no screen sharing or mirroring while frames matter: iOS blanks camera frames then.
- Done means: `fvm flutter analyze` is clean, `fvm flutter test` passes, and `fvm flutter test --dart-define=DEMO=true` passes.

## Review Focus

1. **A clip that opens on a non-court frame** (a title card): the clip plays without counting during setup, and a tap while playing only pauses it. Covered by Task 5's widget test `tap while playing pauses and takes no corner`.
2. **Overlay one frame off the picture:** the frame and its results must swap in one `setState`, after the JPEG is decoded. Covered by Task 5's widget test `frame and its time change together`.
3. **A cut mid-run:**
   - A player's first position after the cut must not add distance, and no swing may span the cut. Covered by Task 1's `loseTrack keeps totals but forgets the track`.
   - Brief flicker must not toggle the scrim. Covered by Task 2's hysteresis tests.
4. **The bottom card with video controls at 375 dp and 1.3× text** must not overflow, and the speed must stay readable. Covered by Task 6's `the video card fits a small phone at the largest text`.
5. **Going back to the camera after a clip:**
   - The camera's own court corners come back.
   - The stats are fresh.
   - The `YOLOView` is back in the tree.

   Covered by Task 5's widget test `closing the clip restores the camera court`.

---

## File Structure

- `lib/video.dart` (new): `VideoClip`, `VideoFrame`, the `VideoFrames` channel wrapper, `thumbDiff`, `CutDetector`. Everything video-specific that isn't widget state.
- `lib/main.dart` (modify):
  - `Player.loseTrack()`.
  - `onResult` takes a time.
  - Video mode state and the play loop in `_LivePageState`.
  - The picture box, the corner-step card and the last-shot card in video mode.
  - The hit flash and the cut scrim in `_OverlayPainter`.
- `ios/Runner/VideoFrameReader.swift` (new): reads a clip with AVFoundation and CoreImage only (no Flutter import), so it can be probed on the Mac.
- `ios/Runner/AppDelegate.swift` (modify): registers the `shuttle_live/video_frames` channel.
- `ios/Runner/Info.plist` (modify): adds `NSPhotoLibraryUsageDescription`.
- `android/app/src/main/kotlin/com/chengboonrong/shuttle_live/VideoFrames.kt` (new): the reader and the channel handler.
- `android/app/src/main/kotlin/com/chengboonrong/shuttle_live/MainActivity.kt` (modify): `configureFlutterEngine` registers the channel.
- `test/video_test.dart` (new): tests for Tasks 1, 2, 5 and 6.
- `DESIGN.md` and `.impeccable/surfaces/lib-main-dart.md` (modify): record the video mode, as was done for the P1/P2 tags.

### Channel contract (Tasks 3, 4 and 5 all use it)

Channel `shuttle_live/video_frames` (MethodChannel, standard codec):

| method | args | returns |
|---|---|---|
| `open` | `{path: String}` | `{durationUs: int, width: int, height: int}`, size after rotation; throws `PlatformException(code: 'unreadable')` if the file isn't a readable video |
| `next` | none | `{jpeg: Uint8List, timeUs: int, thumb: Uint8List}` or `null` at the end |
| `close` | none | `null` |

Rules for both platforms:
- **Order and rate:** frames come in presentation order. A frame is skipped when its time is under `32333` µs after the last frame returned, so a 60 fps clip yields every other frame and a 25/30 fps clip yields all of them.
- **jpeg:** upright (rotation applied), longest side ≤ 1280 px, quality 0.8.
- **thumb:** exactly 32×18 = 576 bytes of 8-bit gray, row-major, the whole frame scaled to that size whatever its aspect.
- **Sessions:** one clip at a time; `open` closes any open one.
- **Threads:** decoding runs off the platform main thread; replies come on it.

---

### Task 1: Analysis runs on a given time; players can lose their track

**Files:**
- Modify: `lib/main.dart:133-190` (Player), `lib/main.dart:322-371` (`onResult`), `lib/main.dart:390-399` (the YOLOView `onResult:` argument)
- Test: `test/video_test.dart`

**Interfaces:**
- Produces:
  - `void Player.loseTrack()`.
  - `void onResult(List<YOLOResult> results, [DateTime? at])` on `_LivePageState`. With `at` null it uses `DateTime.now()`. The camera passes `onResult: (r) => onResult(r)`.

- [ ] **Step 1: Write the failing tests** in `test/video_test.dart`:

```dart
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
  const corners = [Offset(0.3, 0.22), Offset(0.7, 0.22), Offset(0.96, 0.94), Offset(0.04, 0.94)];
  s.taps.addAll(corners);
  s.toCourt = Homography.fit(corners, courtCorners);
  s.toFrame = Homography.fit(courtCorners, corners);
  s.calibrating = false;
  YOLOResult person(double x) => YOLOResult(
    classIndex: 0, className: 'person', confidence: 0.9,
    boundingBox: Rect.zero, normalizedBox: Rect.fromLTRB(x - 0.03, 0.6, x + 0.03, 0.8),
  );
  final t0 = DateTime(2026);
  // Called within microseconds of wall time; only video time can give a speed.
  for (final (i, x) in [0.45, 0.5, 0.55].indexed) {
    s.onResult([person(x)], t0.add(Duration(milliseconds: 300 * i)));
  }
  expect(s.near.speed as double, greaterThan(0));
});
```

Imports: `flutter/material.dart`, `flutter_test`, `package:shuttle_live/main.dart`, `analysis.dart`, `court.dart`, `package:ultralytics_yolo/ultralytics_yolo.dart`.

- [ ] **Step 2: Run them and see them fail**

Run: `cd ~/shuttle-live && fvm flutter test test/video_test.dart`
Expected: FAIL. `loseTrack` isn't defined; `onResult` takes 1 positional argument.

- [ ] **Step 3: Add `Player.loseTrack()`.** Clear `pos`, `_anchor`, `_recent` and `trail`; set `speed = 0` and `unseen = 0`; call `swing.reset()`. Keep `distance` and `topSpeed`. Doc comment: "After a TV cut: forget where they were, keep what they did."

- [ ] **Step 4: Make `onResult` take `[DateTime? at]`.** Use `final now = at ?? DateTime.now();` and change the YOLOView argument to `onResult: (r) => onResult(r)`.

- [ ] **Step 5: Run the tests**

Run: `fvm flutter test test/video_test.dart && fvm flutter test && fvm flutter analyze`
Expected: all pass; analyze reports no issues.

---

### Task 2: Cut detector

**Files:**
- Create: `lib/video.dart` (this task adds only `thumbDiff` and `CutDetector`)
- Test: `test/video_test.dart`

**Interfaces:**
- Produces:
  - `double thumbDiff(Uint8List a, Uint8List b)`: mean absolute difference, 0–255. Both inputs are 576 bytes.
  - `class CutDetector { CutDetector(Uint8List reference); bool offCourt; bool update(Uint8List thumb); }`. `update` returns the new `offCourt`.
  - `const cutThreshold = 40.0;` (top-level), with the comment `// ponytail: tuned on the owner's first clip (Task 7); broadcast cameras pan a little.`

- [ ] **Step 1: Write the failing tests:**

```dart
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
```

- [ ] **Step 2: Run and see them fail**

Run: `fvm flutter test test/video_test.dart`
Expected: FAIL, because `thumbDiff`, `CutDetector` and `cutThreshold` aren't defined.

- [ ] **Step 3: Implement them in `lib/video.dart`.** Keep a run counter that resets whenever a frame agrees with the current state. Flip to off-court at 2 in a row over the threshold, and back at 3 in a row at or under it.

- [ ] **Step 4: Run the tests**

Run: `fvm flutter test test/video_test.dart && fvm flutter analyze`
Expected: PASS, no issues.

---

### Task 3: iOS frame reader

**Files:**
- Create: `ios/Runner/VideoFrameReader.swift`. Add it to the Runner target in `ios/Runner.xcodeproj/project.pbxproj` (PBXFileReference, PBXBuildFile, the Runner group, and the Sources build phase, as `AppDelegate.swift` is).
- Modify: `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist`

**Interfaces:**
- Produces the channel contract above on iOS.
- `final class VideoFrameReader { init(url: URL) throws; let durationUs: Int64; let width: Int; let height: Int; func next() -> (jpeg: Data, timeUs: Int64, thumb: Data)? }`. Imports only Foundation, AVFoundation, CoreImage and CoreGraphics.

- [ ] **Step 1: Write `VideoFrameReader`.**
  - **Reading:** `AVURLAsset` and its first video track, read by an `AVAssetReader` + `AVAssetReaderTrackOutput` with `kCVPixelFormatType_32BGRA`.
  - **Rotation:** apply `track.preferredTransform` to the `CIImage`, then translate it back to the origin. `width`/`height` are the transformed size.
  - **Rate:** skip frames under 32333 µs after the last frame returned.
  - **jpeg:** scale to longest side ≤ 1280 with `CIContext.jpegRepresentation`, quality 0.8, device RGB.
  - **thumb:** scale the oriented image to exactly 32×18 and render it with `CIContext.render(_:toBitmap:rowBytes:bounds:format:colorSpace:)` in `.L8` and a gray colour space, giving 576 bytes.
  - **Errors:** `init` throws when the asset has no video track or the reader can't start.
  - Use one `CIContext` per reader.

- [ ] **Step 2: Probe it on the Mac.** First make a test clip: 60 fps, 3 s, with rotation metadata.

```bash
cd /private/tmp/claude-501/-Users-chrischeng/63919ae3-347e-58e7-a044-e95f73b4f613/scratchpad
ffmpeg -y -f lavfi -i testsrc=size=1920x1080:rate=60 -t 3 -pix_fmt yuv420p clip60.mp4
ffmpeg -y -i clip60.mp4 -c copy -display_rotation 90 clip60-rot.mp4
```

Write `probe.swift` (scratchpad). It opens the path given in argv, prints `durationUs width height`, then for each frame prints `timeUs jpegBytes`, and writes the first frame's JPEG to `first.jpg`. Then:

Run: `swiftc -O ~/shuttle-live/ios/Runner/VideoFrameReader.swift probe.swift -o probe && ./probe clip60.mp4 | head -5 && ./probe clip60.mp4 | tail -n +2 | wc -l && ./probe clip60-rot.mp4 | head -1`

Expected:
- `3000000 1920 1080` (±1 frame of duration).
- Times 0, 33333, 66666… (every other frame).
- About 90 frame lines.
- The rotated clip reports `… 1080 1920`.

Then open `first.jpg` with the Read tool: it must be upright testsrc, 1280×720.

- [ ] **Step 3: Register the channel in `AppDelegate.didInitializeImplicitFlutterEngine`.**
  - Get the messenger via `engineBridge.pluginRegistry.registrar(forPlugin: "VideoFrames")!.messenger()`.
  - Hold one `VideoFrameReader?` and run `open`/`next` on a serial `DispatchQueue`.
  - Reply on the main queue.
  - Wrap `jpeg` and `thumb` in `FlutterStandardTypedData(bytes:)`.
  - Throws become `FlutterError(code: "unreadable", …)`.

- [ ] **Step 4: Add `NSPhotoLibraryUsageDescription` to `Info.plist`:** "Shuttle Live analyses a match video you pick."

- [ ] **Step 5: Build**

Run: `cd ~/shuttle-live && fvm flutter build ios --profile`
Expected: `✓ Built build/ios/iphoneos/Runner.app`.

---

### Task 4: Android frame reader

**Files:**
- Create: `android/app/src/main/kotlin/com/chengboonrong/shuttle_live/VideoFrames.kt`
- Modify: `android/app/src/main/kotlin/com/chengboonrong/shuttle_live/MainActivity.kt`

**Interfaces:**
- Produces the channel contract above on Android.
- `class VideoFrames(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler`, registered in `MainActivity.configureFlutterEngine` via `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shuttle_live/video_frames")`.

- [ ] **Step 1: Write `VideoFrames.kt`.**
  - **Opening:** `MediaMetadataRetriever.setDataSource(path)`. Read the duration, width, height and rotation; swap width/height for 90/270.
  - **Frames, API 28+:** `getFrameAtIndex(i)` over `METADATA_KEY_VIDEO_FRAME_COUNT`, with time `i × durationUs / frameCount` and a `// ponytail: even spacing; variable-frame-rate clips drift a little` note.
  - **Frames, below 28:** `getFrameAtTime(t, OPTION_CLOSEST)` stepping t by 33333 µs.
  - **Rate:** apply the 32333 µs skip rule.
  - **Rotation:** rotate the bitmap only if its width/height don't already match the rotated size. Some devices hand back frames already rotated.
  - **jpeg:** scale to longest side ≤ 1280 and compress as JPEG at quality 80.
  - **thumb:** `Bitmap.createScaledBitmap(…, 32, 18, true)`, gray = (77R + 150G + 29B) >> 8 per pixel, giving 576 bytes.
  - **Threads:** work on a single-thread `Executor`; reply through `Handler(Looper.getMainLooper())`.
  - **Errors:** a bad file gives `result.error("unreadable", …)`.

- [ ] **Step 2: Register it in `MainActivity.configureFlutterEngine`**, calling `super.configureFlutterEngine(flutterEngine)` first.

- [ ] **Step 3: Build**

Run: `cd ~/shuttle-live && fvm flutter build apk --release`
Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`. Android stays **unchecked**: no phone, no emulator.

---

### Task 5: Video mode: pick, set the court on a clip, play, go back

**Files:**
- Modify: `pubspec.yaml` (`fvm flutter pub add image_picker`), `lib/video.dart`, `lib/main.dart`
- Test: `test/video_test.dart`

**Interfaces:**
- Consumes: the channel contract; `onResult(results, at)` and `Player.loseTrack()` (Task 1); `CutDetector` (Task 2).
- Produces, in `lib/video.dart`:
  - `class VideoClip { const VideoClip({required this.duration, required this.width, required this.height}); final Duration duration; final int width, height; double get aspect => width / height; }`
  - `class VideoFrame { final Uint8List jpeg, thumb; final Duration time; }`
  - `abstract final class VideoFrames { static const channel = MethodChannel('shuttle_live/video_frames'); static Future<VideoClip> open(String path); static Future<VideoFrame?> next(); static Future<void> close(); }`
- Produces, on `_LivePageState`:
  - `VideoClip? clip` (null means camera mode).
  - `bool playing`.
  - `ui.Image? frame`.
  - `Duration frameTime`.
  - `Future<void> openVideo(String path)`.
  - `Future<void> closeVideo()`.
  - `void togglePlay()`.

Behaviour, from the spec's Flow (steps 1–7). The pinned details:

- **Entry points:**
  - **ANALYSE A VIDEO**, an `OutlinedButton` in `openSettings()` placed before SET COURT AGAIN. The `Row` becomes a `Wrap` with `spacing: 12, runSpacing: 8` so three buttons fit.
  - **VIDEO**, a `TextButton` in `cornerStep()` that shows when `taps.isEmpty && clip == null` (UNDO keeps its slot once there are taps).
  - Both call `ImagePicker().pickVideo(source: ImageSource.gallery)` and then `openVideo(file.path)`. A cancel does nothing.
- **`openVideo`:**
  - **Save the camera court:** if `clip == null`, keep the camera's `taps`, `toCourt`, `toFrame` and `calibrating` in fields (`_cameraCourt`).
  - **Start fresh:** `resetStats()` and clear the court (as `recalibrate()` does, without its `setState`).
  - **Open:** call `VideoFrames.open`, create `YOLO(modelPath: 'yolo26n-pose', task: YOLOTask.pose)` once (kept in a field), and show the first frame from `next()`. `playing = false`.
  - **Errors:** on `PlatformException`, show a SnackBar ("That video can't be read") and stay in camera mode.
- **Play loop:**
  - Shape: one `async` loop guarded by an `int _run` generation counter, so pause, close or a new clip ends the old loop.
  - Each pass: `next()`, then `decodeImageFromList(jpeg)`. Then, only while counting (court set and not off-court), `predict(jpeg, confidenceThreshold: 0.35)` and map `detections` with `YOLOResult.fromMap`. Then one `setState` that swaps `frame` (disposing the old `ui.Image`), sets `frameTime`, updates the cut state and calls `onResult(results, _videoBase.add(time))`. `_videoBase` is a fixed `DateTime(2000)`.
  - End of clip (`next()` returns null): `playing = false`, keep the stats and the last frame.
- **Court setup on a clip:**
  - Playing shows frames without `predict` or `onResult`.
  - `onTap` while `clip != null && playing` pauses and doesn't take the tap.
  - The 4th good tap sets `_cut = CutDetector(currentThumb)` and starts playing.
- **SET COURT AGAIN in video mode:** pause, then `recalibrate()` (stats clear, as the sheet already says); the next 4 taps make a new `CutDetector`.
- **`closeVideo` (✕):**
  - Bump `_run` and call `VideoFrames.close()`.
  - Dispose `frame` and the `YOLO` (`dispose()`).
  - `clip = null`; `resetStats()`; restore `_cameraCourt`.
  - Also call it from `dispose()`.
- **Picture box:**
  - Camera mode is unchanged.
  - In video mode the box is the largest `clip.aspect` box that fits the space, centred horizontally (contain, never cropped).
  - `frameRect` uses `clip?.aspect ?? frameAspect`. With the box at the clip's aspect, that gives the whole box.
  - Draw the frame with `RawImage(image: frame, fit: BoxFit.fill)` in place of `YOLOView`. `YOLOView` is in the tree only when `clip == null`, which is what turns the camera off.
- **Corner-step card in video mode:** a round play/pause `IconButton` (ink circle, paper icon, 48 dp target) on the left, and an ✕ `IconButton` on the right after UNDO.

- [ ] **Step 1: Write the failing widget tests.**
  - **Shared helper:** `Future<dynamic> openMockClip(WidgetTester tester, {List<int>? thumbValues})` in `test/video_test.dart`, also used by Task 6. It:
    - Pumps `LivePage`.
    - Mocks `VideoFrames.channel` with `tester.binding.defaultBinaryMessenger.setMockMethodCallHandler`:
      - `open` returns `{durationUs: 2000000, width: 1920, height: 1080}`.
      - `next` returns up to 5 frames 33333 µs apart, then `null`. `jpeg` is a valid 16×9 PNG made once with `ui.PictureRecorder` → `toImage` → `toByteData(format: png)`. `thumb` for frame i is filled with `thumbValues?[i] ?? 100`.
    - Also mocks the plugin's single-image channel `yolo_single_image_channel` (`ChannelConfig.singleImageChannel`; check the exact name for the default instance in `lib/config/channel_config.dart`). Any model-load call returns `true`, and `predict` returns `{'boxes': [], 'detections': []}`, so counting passes run without a model.
    - Calls `openVideo('x.mp4')` on `tester.state(find.byType(LivePage)) as dynamic` inside `tester.runAsync` (image decoding is real async), pumps, and returns that state.

```dart
// 'video mode replaces the camera and shows the clip whole'
expect(find.byType(YOLOView), findsNothing);
expect(find.byType(RawImage), findsOneWidget);
final box = tester.getSize(find.byType(RawImage));
expect(box.width / box.height, closeTo(16 / 9, 0.01));
expect(find.text('Tap the far-left corner'), findsOneWidget);

// 'tap while playing pauses and takes no corner'
s.togglePlay(); await tester.pump();
await tester.tapAt(tester.getCenter(find.byType(RawImage)));
expect(s.playing, isFalse);
expect(s.taps, isEmpty);

// 'frame and its time change together': play during setup and, after each pump, record
// (identityHashCode(s.frame), s.frameTime). A new frame must never appear with the old time,
// nor a new time with the old frame. The results are set in the same setState as the time.
final seen = <(int, Duration)>[];
s.togglePlay();
for (var i = 0; i < 6; i++) {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  seen.add((identityHashCode(s.frame), s.frameTime as Duration));
}
for (var i = 1; i < seen.length; i++) {
  expect(seen[i].$1 != seen[i - 1].$1, seen[i].$2 != seen[i - 1].$2);
}

// 'closing the clip restores the camera court'
// before openVideo: set the camera taps to the four demo corners and calibrating = false
await s.closeVideo(); await tester.pump();
expect(find.byType(YOLOView), findsOneWidget);
expect(s.taps, hasLength(4));
expect(s.match.hits, isEmpty);
```
- [ ] **Step 2: Run and see them fail**

Run: `fvm flutter test test/video_test.dart`
Expected: FAIL, because `openVideo`, `togglePlay` and `closeVideo` aren't defined.

- [ ] **Step 3: Add the packages and code.** Run `fvm flutter pub add image_picker`. Write `VideoClip`, `VideoFrame` and `VideoFrames` in `lib/video.dart`, then the state, loop, picture box and card changes above in `lib/main.dart`.

- [ ] **Step 4: Run all checks**

Run: `fvm flutter test && fvm flutter test --dart-define=DEMO=true && fvm flutter analyze`
Expected: all pass, no issues. `test/board_test.dart` still finds `YOLOView` in camera mode.

---

### Task 6: Counting on a clip: cut scrim, hit flash, speed chip, video bottom card

**Files:**
- Modify: `lib/main.dart` (`topBar()`, `lastShot()`, `_OverlayPainter`, the play loop from Task 5), `DESIGN.md`, `.impeccable/surfaces/lib-main-dart.md`
- Test: `test/video_test.dart`

**Interfaces:**
- Consumes: `CutDetector`, `Player.loseTrack()`, `clip`, `playing`, `frameTime`, and the play loop (Task 5).
- Produces, on `_LivePageState`:
  - `bool offCourt`.
  - `Map<Side, DateTime> flashUntil`.
  - `double playRate`: video seconds per wall second, smoothed.

Pinned details:

- **Cut gating:** each counting pass does `offCourt = _cut!.update(thumb)`.
  - While `offCourt`: no `predict`; `feet = []`; and still `match.tick(_videoBase.add(time))`.
  - On the change from off-court back to court: `far.loseTrack(); near.loseTrack();`.
- **Scrim:** while `offCourt`, an ink scrim at 55% over the picture, with a centred card (ink, 2 px steel border, radius 6) reading `NOT THE COURT` in `caps(15)` over `Counting paused` in `body(14, steel)`. Rings and tags are hidden.
- **Hit flash (video mode only):** when `match.addHit` returns non-null, set `flashUntil[side] = now.add(const Duration(milliseconds: 500))`, where `now` is the frame's video time.
  - The painter compares against the last frame time.
  - While flashing, the ring is filled with the side colour at 35% under the 3 px paper stroke, and the tag reads `P1 HIT` / `P2 HIT`.
  - Live mode is unchanged.
- **Top-left chip (video mode):** line 1 is `VIDEO` (`caps(12)`); line 2 is `~${playRate.toStringAsFixed(1)}× speed` while playing, or `Paused` when not. This replaces the FPS line.
  - `playRate` is an exponential average (α = 0.2) of Δvideo / Δwall per frame.
  - The swing line is dropped in video mode; the chip stays two lines.
- **Bottom card (video mode, court set):**
  - The 60 dp card keeps the existing last-shot content.
  - A round play/pause `IconButton` sits on the left. On the right, a time text `m:ss / m:ss` (`body(12, Color(0xFF4A4F57), FontWeight.w700)`), then an ✕ `IconButton`.
  - A 3 px ink progress bar runs along the card's top edge (`frameTime / clip.duration`).
  - The controls sit outside the `FlipCard`'s keyed child (a `Stack` or `Row` around it), so they don't flip with each shot.
  - The shot name may shrink (it is already in a `FittedBox`); the `~… km/h` text must not.
- **DESIGN.md:** add a "Video mode" paragraph under the overlay section, describing the picture box, the scrim, the flash and the bottom card. Update the surface brief's purpose line to mention "or a saved clip".

- [ ] **Step 1: Write the failing tests.**

```dart
testWidgets('the video card fits a small phone at the largest text', (tester) async {
  // 375×667 at 1.3× text, as board_test does; s = await openMockClip(tester),
  // set four corners so calibrating is false, add one named hit with speedKmh 139.
  expect(tester.takeException(), isNull);
  expect(find.text('~139 km/h'), findsOneWidget);
  final speed = tester.getSize(find.text('~139 km/h'));
  final natural = (TextPainter(text: TextSpan(text: '~139 km/h', style: numerals(22)), textScaler: const TextScaler.linear(1.3), textDirection: TextDirection.ltr)..layout()).width;
  expect(speed.width, closeTo(natural, 1));
  expect(find.textContaining(' / '), findsOneWidget); // the time
});

testWidgets('a cut hides the tags and shows the scrim', (tester) async {
  // s = await openMockClip(tester, thumbValues: [100, 100, 200, 200, 200]); tap the four demo
  // corners on frame 0 (the reference is 100), then let it play to the end.
  expect(s.offCourt, isTrue);
  expect(find.text('NOT THE COURT'), findsOneWidget);
  expect(find.text('P1'), findsNothing);
});
```

- [ ] **Step 2: Run and see them fail**

Run: `fvm flutter test test/video_test.dart`
Expected: FAIL, because there's no time text, no scrim and no speed fit yet.

- [ ] **Step 3: Implement the details above.**

- [ ] **Step 4: Run all checks**

Run: `fvm flutter test && fvm flutter test --dart-define=DEMO=true && fvm flutter analyze`
Expected: all pass, no issues.

---

### Task 7: Tune the cut threshold on the owner's clip, then check on the iPhone

**Needs the owner:** a landscape TV/YouTube clip saved to Photos, with a copy AirDropped to the Mac (in `~/Downloads`).

- [ ] **Step 1: Measure the thumb differences.** Extend `probe.swift` (Task 3) with a `--diff <refTimeUs>` mode. It prints `timeUs diff` for every frame against the thumb at `refTimeUs` (a main-camera frame the owner names, or the first court frame seen). Use the same `thumbDiff` formula as Task 2.

Run: `./probe --diff <refTimeUs> ~/Downloads/<clip> > diffs.txt`

To see what the numbers mean, pull frames around the jumps with `ffmpeg -ss <t> -i <clip> -frames:v 1 f.png` and look at them with the Read tool.

- [ ] **Step 2: Set `cutThreshold`.** Put it midway between the highest main-camera diff and the lowest close-up/replay diff. Note both numbers in the `ponytail:` comment. If the two ranges overlap, stop and tell the owner, with the numbers.

- [ ] **Step 3: Build and install on the iPhone**

```bash
cd ~/shuttle-live && fvm flutter build ios --profile
U=<iphone-udid>  # xcrun devicectl list devices
xcrun devicectl device install app --device $U build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device $U --terminate-existing com.chengboonrong.shuttleLive
```

- [ ] **Step 4: The owner runs the clip** (screen sharing off). The owner opens the clip, plays it to a court frame, taps the corners and lets it run through at least one cut. Stay quiet while they use the phone. Then take screenshots (`xcrun devicectl device capture screenshot --device $U --destination v.png`) and check:
  - tags follow the players
  - `P2 HIT` flashes on hits
  - the scrim shows on a close-up and clears afterwards
  - the card shows time and progress
  - ✕ brings the live camera back on the 1× lens

  Report what you saw, including the playback rate the chip shows.

- [ ] **Step 5: Android:** `fvm flutter build apk --release` only. Report Android as unchecked. Don't upload.

- [ ] **Step 6: Update the project memory** (`badminton-live-analysis.md`) with the threshold, the rate seen, and anything the run showed.

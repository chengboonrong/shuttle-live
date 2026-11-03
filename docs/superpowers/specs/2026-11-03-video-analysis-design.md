# Video analysis: run the stats on a saved clip

Status: approved by the owner 2026-11-03 after the builder check. Source only, no release.

## Why

Shuttle Live has never been tried on a real court. The owner wants to load a saved TV or YouTube badminton clip and watch the app analyse it. That way they can judge, without going to a court, whether shot counts, shot types and the estimated speeds come out right on real rallies.

Success: the owner picks a clip on the iPhone, taps the court once, and watches it play with the P1/P2 tags. They can see each counted hit as it happens and judge it against the picture. The board fills exactly as it would live.

## Goals

- Pick a video from the phone's photo library and analyse it with the same pipeline as the live camera: court mapping, Player, SwingDetector, Match, and the board.
- **Exact sync (owner's choice).** Each frame is shown only after it has been analysed, so the picture, the tags, the hit flash and the board always agree. Playback runs at whatever speed the phone manages and may be slower than real time.
- **Pause on a TV cut (owner's choice).** When the picture stops matching the court the owner tapped (a close-up, a replay from another angle, crowd shots), counting stops and the screen says so. Counting resumes when the main camera returns.
- **Controls on the bottom card (owner's choice, layout B).** See "Screen".

## Non-goals

- No seeking, scrubbing or skipping ahead. The clip plays from the start, with pause and resume only.
- No playback speed control and no real-time-speed mode.
- No export or saving of results.
- No automatic court detection; the owner taps four corners as with the camera.
- No audio playback. (Update 2026-11-03, owner's choice: hits on a clip are timed by its racket sounds; the sound is read, never played.)
- No release. No APK upload or Drive upload unless the owner asks.

## Anti-goals (would make it a failure even if it works)

- Counting hits, distance or speed from close-ups or replays, or from a cut that makes a player seem to jump across the court.
- A picture that runs ahead of or behind its overlay; the owner can't judge a hit then.
- Cropping off a corner of the clip, so the court can't be tapped.
- Any speed without its "~" estimate mark, or anything that suggests a match score.
- Plugin boxes, labels or skeletons. Only the app's own rings, P1/P2 tags and court lines are drawn.

## Constraints (standing rules for this project)

- Flutter 3.38 via `fvm flutter`. The project is not under git.
- The pose model is `yolo26n-pose` via the vendored `third_party/ultralytics_yolo` (0.7.1 plus "Shuttle Live patch" changes). It is AGPL: private testing only.
- iPhone 15 Plus (iOS 27) is the test phone. Android is built but reported "unchecked" until it runs on a real phone. Never use an emulator.
- The live camera keeps its rules: 1× wide lens, no plugin overlays.
- Controls stay Material and use the existing theme, fonts and colours (`lib/main.dart`, DESIGN.md "Umpire Flip Scoreboard").
- Speeds are estimates and keep the "~" prefix. Never invent accuracy claims.

## How it works

### Flow

1. The HIT AT sheet (`openSettings()` in `lib/main.dart`) gets a new outlined button, **ANALYSE A VIDEO**, beside SET COURT AGAIN. It opens the photo library video picker.
   - The HIT AT button is hidden while the live court is being set (`topBar()`; DESIGN.md: "Nothing over the camera while setting the court"). The court isn't kept between launches, so the corner-step card also gets a **VIDEO** text button (`cornerStep()`, where UNDO goes) that opens the same picker. Keep it until the first tap; after that, UNDO takes the spot. Without it the owner would have to tap a fake court on every launch before they could open a clip.
2. The clip opens **paused on its first frame**. The live camera stops: the `YOLOView` leaves the widget tree, which turns the camera off and saves CPU and battery.
3. **Court setup on a clip.** TV clips often open on a title card or a close-up, so the clip can **play during setup without counting**: no Player, SwingDetector or Match updates, just frames.
   - The corner-step card gets the round pause/play button on its left and ✕ on its right, so there is a way back before the court is set.
   - The owner plays to a frame that shows the court and pauses.
   - Tapping a corner while playing pauses the clip first; corners are only taken on a still frame.
   - The court steps then run exactly as live (`cornerStep()`, the four taps, UNDO, bad-corners message).
4. After the fourth tap the clip plays from where it was paused, and counting starts. The frame the corners were tapped on is the cut-detection reference.
5. **Pause** stops decoding; video time stands still, so pausing never affects speeds. While paused, the HIT AT sheet still works. SET COURT AGAIN goes back to step 3 on the current frame, and **clears the stats as it does live** (the sheet already says "Setting the court again clears the stats."). The new court frame becomes the new cut reference, which covers a broadcast that moved its camera.
6. At the end the clip stops on its last frame, and the stats stay on the board.
7. **✕** on the bottom card goes back to the live camera, and the camera's own court corners come back. Stats start fresh each time you switch, into a video or back to the camera.

### Screen (layout B, as mocked up)

- **Picture:** the clip fills the camera box. The **whole frame is always visible and never cropped**, unlike the camera's fill-and-crop. A landscape 16:9 TV clip is fit to the screen width, so the box is shorter than the camera's 3:4. The board below keeps the room it gets (the board already shrinks or grows with the space; see `test/board_test.dart`).
- **Top-left chip:** "VIDEO" plus the playback rate as an estimate, e.g. "~0.6× speed" (analysed video seconds ÷ wall-clock seconds, smoothed). It replaces "N FPS" while in video mode. The swing readout line can stay.
- **Top right:** the HIT AT button, unchanged.
- **Bottom card** (the white last-shot strip): a round pause/play button on the left, then the last named shot as today ("NEAR PUSH"), then "0:42 / 2:10", then ✕. A thin ink progress line runs along the top edge of the card.
- **Overlay:** court lines, feet rings and P1/P2 tags as live (`_OverlayPainter`).
- **Hit flash:** when `match.addHit` returns a new hit, that player's ring fills and their tag is replaced for ~0.5 s of video time. See "Hit flash text" below for what it reads.
- **TV cut:** the picture dims (ink scrim) and a centred card reads "NOT THE COURT" / "Counting paused". The rings and tags are hidden while it shows.

Mockup: `.superpowers/brainstorm/55747-1793679165/content/video-screen.html`, layout B. The mockup draws a portrait picture; a real TV clip is landscape, as described above.

### Hit flash text

A shot's type is only known once its reply arrives or the rally ends (`Hit.type`, `Match._finish` in `lib/analysis.dart`), so at the moment of the hit the app can't name it yet. The mockup's "P2 SMASH" therefore can't appear at hit time. **Owner's choice (2026-11-03):** the tag reads "P2 HIT" at the hit, and the shot's name shows on the bottom card once named, as it does today. No second flash when the name arrives.

### Frames from the video

There is no maintained pub.dev package that decodes every frame of a video in order on both platforms. The packages that exist grab single frames at chosen times (snapframes, video_snapshot_generator) and are too slow and too new. So add a small platform channel of our own in the Runner app, not in the vendored plugin:

- **iOS:** `AVAssetReader` with an `AVAssetReaderTrackOutput`, reading frames in order. Honour the track's `preferredTransform` so rotated phone recordings come out upright.
- **Android:** `MediaMetadataRetriever`. Use `getFrameAtIndex` (API 28+), and fall back to `getFrameAtTime(…, OPTION_CLOSEST)` below API 28 (minSdk is 24). Honour the rotation metadata. Unchecked until a real phone.
- **Per frame, the channel returns:** a JPEG (longest side about 1280 px), the presentation time in microseconds, the frame size, and a small grayscale thumbnail (about 32×18) for cut detection.
- **Rate:** frames are taken in order, and a frame is skipped when it lands less than 1/30 s of video time after the last frame taken. A 50/60 fps clip is therefore analysed at ≤30 frames per second, the rate the live camera and swing detector run at. A 25/30 fps clip is analysed whole.
- **Lifecycle:** open(path) returns the duration, size and frame rate; next() returns the next frame or the end; close(). Only one clip is open at a time. Close it on ✕, on picking another clip, and on dispose.

Pick the video with `image_picker` (flutter.dev, BSD-3) `pickVideo(source: ImageSource.gallery)`. It returns a file path both native readers can open. Add the iOS photo library usage string that its README asks for.

### Pose on each frame

Use the plugin's single-image API on the vendored package: `YOLO(modelPath: 'yolo26n-pose', task: YOLOTask.pose)`, then `predict(jpegBytes, confidenceThreshold: 0.35)`. Turn the `detections` into `YOLOResult`s with `YOLOResult.fromMap`. The live path depends on keypoints, so confirm that the detections carry `keypoints` and `keypointConfidences`; if they don't, build them from the `keypoints` field of the result. The confidence matches the live controller (0.35).

Loop: next frame, then predict, then show that frame and its results together, then the next frame. The frame and its overlay **must change in the same build**. Plain `Image.memory` decodes asynchronously and can show the overlay one frame ahead of the picture, so decode the JPEG to a `ui.Image` first and swap both together. How to do that is left to the builder.

### Reusing the analysis

`onResult` in `lib/main.dart` takes the time from `DateTime.now()`. Give it the time instead, so the video passes **a fixed base DateTime plus the frame's presentation time**. Everything downstream (Player speed, SwingDetector, Match rally gap, the ~1 s "unseen" rule) then runs on video time. The live camera keeps passing `DateTime.now()`.

`normalizedBox` from `predict()` is relative to the whole frame. With the frame uncropped, `frameRect` is simply the picture's box in video mode, and the overlay mapping (`toScreen`, `toFrameCoords`) works unchanged. `frameAspect` becomes the current source's aspect: 3:4 for the camera, the clip's own for video.

### Spotting a TV cut

When the court is set, keep that frame's thumbnail as the reference. For every frame, compare its thumbnail with the reference: mean absolute difference of the gray values, 0–255. Above a threshold the frame counts as "not the court".

- Use a named constant for the threshold, with a `ponytail:` note saying it is tuned on clips. Start around 40 and adjust after the first real clips. Broadcast cameras pan a little, and players and score graphics move.
- To avoid flicker, switch to "not the court" after 2 frames in a row over the threshold, and back after 3 in a row under it.
- While "not the court": don't call `Player.update` or `SwingDetector.update`, don't add hits, and show the scrim. Do keep calling `match.tick` with video time, so a rally that stops at a cut is named and ends normally.
- When counting resumes, both players **lose their track but keep their totals**: clear pos, anchor, recent positions, trail and swing state, but keep distance, top speed and counts. Then the first position after the cut never counts as running, and no swing spans the cut. `Player.reset()` clears totals too, so add a method that keeps them.

Known limit: a slow-motion replay shot from the main camera angle looks like the court and will be counted. The owner can trim such clips. Note it; don't solve it.

### Tests

Keep to one small check per piece of new logic, in line with the existing `test/` files:

- The cut detector (threshold and the 2-in / 3-out frames) on made-up thumbnails.
- "Lose track, keep totals" on `Player`.
- `onResult` on a given time: two results 1 s apart in video time give a speed calculated over that 1 s, whatever the wall clock says.

Plus `flutter analyze` clean, and the existing tests passing, both normal and with `--dart-define=DEMO=true`.

**Test clips (owner's choice):** the owner saves a landscape TV/YouTube clip to Photos (a downloaded file, not a screen recording with player controls) and AirDrops a copy to the Mac. Use the Mac copy during the build to tune the cut threshold: run the same thumbnail difference over its frames, e.g. with a small script, and pick the threshold from where close-ups and replays fall. There is no debug-only path to open a clip; the owner picks and taps.

Device check on the iPhone, with no screen sharing during the check because that blanks frames. The owner picks the clip and taps the corners; Claude installs, launches, and reads `devicectl` screenshots and the xctrace Logging output:

- Pick a TV clip and tap the corners.
- See the tags follow the players, a flash on hits, the scrim on a close-up, and the bottom card controls working.
- Go back to the camera and see live mode still work, on the 1× lens.

Android: build the APK only, and report the Android side as unchecked.

## Left to the builder

- Channel names, file layout, and Swift/Kotlin structure; JPEG quality.
- How the loop is scheduled: a simple async loop is fine.
- The exact look of the pause/play button and the scrim card, within the existing theme.
- How to get from `predict()` maps to `YOLOResult`.
- Whether the playback-rate estimate is shown when paused. Hiding it is fine.
- Whether to downscale frames before `predict()` beyond the 1280 px JPEG.

## Calls made without the owner (check these)

- 50/60 fps clips are analysed at up to 30 frames per second.
- Stats start fresh on each switch between camera and video; the camera's court is kept.
- SET COURT AGAIN in video mode re-taps on the current frame, resets the cut reference, and clears the stats, as it does live.
- The clip can play without counting during court setup, so a clip that opens on a non-court frame still works; the corner card carries pause/play and ✕.
- A VIDEO button on the corner-step card, so a clip can be opened before the live court is set.
- The whole clip is shown uncropped, so a landscape clip makes a shorter picture box.
- The cut check compares each frame with the court frame; it doesn't look for jumps between frames.
- A home-made platform channel instead of a package; `image_picker` for picking.

## Open questions

- None. The builder check (2026-11-03) raised four; two were settled from the conversation, one as a call above, and the owner answered the clip source and the flash text.

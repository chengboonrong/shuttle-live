---
name: Shuttle Live
description: Live singles badminton analysis on one phone, shown as an umpire's flip scoreboard.
colors:
  ink: "#121212"
  raised: "#1C1C1C"
  steel: "#8A9099"
  paper: "#F4F2EC"
  far: "#D6342C"
  near: "#1F5FBF"
  caption-grey: "#4A4F57"
  ring: "#3A3D42"
typography:
  numerals-count:
    fontFamily: "Archivo"
    fontSize: "64px"
    fontWeight: 900
    lineHeight: 1
    fontFeature: "tnum"
  numerals-step:
    fontFamily: "Archivo"
    fontSize: "40px"
    fontWeight: 900
    lineHeight: 1
    fontFeature: "tnum"
  numerals-shot:
    fontFamily: "Archivo"
    fontSize: "34px"
    fontWeight: 900
    lineHeight: 1
    fontFeature: "tnum"
  numerals-small:
    fontFamily: "Archivo"
    fontSize: "24px"
    fontWeight: 900
    lineHeight: 1
    fontFeature: "tnum"
  numerals-tile:
    fontFamily: "Archivo"
    fontSize: "15px"
    fontWeight: 900
    lineHeight: 1
    fontFeature: "tnum"
  caps-strip:
    fontFamily: "Archivo Narrow"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.1em"
  caps-button:
    fontFamily: "Archivo Narrow"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.1em"
  caps-label:
    fontFamily: "Archivo Narrow"
    fontSize: "10.5px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.1em"
  body-lead:
    fontFamily: "Archivo Narrow"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.25
  body:
    fontFamily: "Archivo Narrow"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.25
  body-small:
    fontFamily: "Archivo Narrow"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.25
rounded:
  tile: "3px"
  card: "4px"
  frame: "6px"
spacing:
  hair: "2px"
  xs: "4px"
  sm: "8px"
  gutter: "10px"
  md: "12px"
  lg: "16px"
  sheet: "20px"
components:
  flip-card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
  count-card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.numerals-count}"
    rounded: "{rounded.card}"
    height: "92px"
    padding: "12px 6px 5px"
  last-shot-card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.numerals-shot}"
    rounded: "{rounded.card}"
    height: "60px"
    padding: "8px 14px 4px 10px"
  type-tile:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.numerals-tile}"
    rounded: "{rounded.tile}"
    padding: "3px 2px"
  side-strip-far:
    backgroundColor: "{colors.far}"
    textColor: "{colors.paper}"
    typography: "{typography.caps-strip}"
    height: "28px"
  side-strip-near:
    backgroundColor: "{colors.near}"
    textColor: "{colors.paper}"
    typography: "{typography.caps-strip}"
    height: "28px"
  board-frame:
    backgroundColor: "{colors.ink}"
    rounded: "{rounded.frame}"
    padding: "8px"
  button-outlined:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.caps-button}"
    rounded: "{rounded.frame}"
    height: "48px"
  button-text:
    textColor: "{colors.paper}"
    typography: "{typography.caps-button}"
    height: "48px"
  status-chip:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.frame}"
    padding: "6px 10px"
  bottom-sheet:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.paper}"
    padding: "0 20px 12px"
  snackbar:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
---

# Design System: Shuttle Live

## Overview

**Creative North Star: "The Umpire's Flip Scoreboard"**

The one screen is a scoreboard on an umpire's stand, set under a live camera. A matte black stand carries a steel frame; card-white flip cards hang from two top rings and carry heavy black numerals; the far player is red and the near player blue, used as header strips, on-court rings, mini-court dots and trails. When a number changes, its new card falls over the top rings onto the old one. That flip is the system's one signature move.

The mode is Operate. The player reads it from the near half of the court with a glance, and walks up between games for detail, so type is either very big (numerals) or a dense, tracked caption. Everything that needs a touch happens before the first serve: corner setup on the board, and the rare controls behind one button in a Material bottom sheet. The layout is fixed, not responsive; one look on iPhone and Pixel, portrait only.

The build is flat apart from one soft shadow under each flip card. It refuses the fitness-app grid of small dark stat tiles with a neon accent: no neon, no glass blur, no gradients.

Shipping rasters and fonts: the launcher icons are the app's own mark, drawn by hand in icon/icon.svg. It is a card-white flip card with ring holes and a hinge line, an ink shuttlecock on the card, and the red and blue side strips above it, all on Stand Black. icon/build.sh renders it to every iOS and Android size; Android 8+ gets an adaptive icon with a Stand Black background and the same art as the foreground. The iOS launch image is still the template's 1x1 transparent placeholder over a Stand Black launch screen. The bundled faces are Archivo Black and Archivo Narrow under the SIL OFL (fonts/OFL.txt).

**Key Characteristics:**
- Black stand, steel frame, card-white cards, black numerals.
- Red is far, blue is near, everywhere a side is shown.
- Cards flip over their top rings when their value changes.
- Every estimated number starts with "~"; nothing reads as a match score.
- Text scale is clamped at 1.3x because the board is a fixed panel.

## Colors

A near-black and card-white scoreboard with exactly two side colours; no other hue appears.

### Primary
- **Card White** (paper): every flip card and type tile, the court overlay lines on the camera, the mini-court net and last-shot line, the corner-tap dots, the slider, the snackbar, and caption text on the stand. It is Material `primary`.

### Secondary
- **Far Red** (far): the FAR header strip, the FAR tag on the last-shot card, the far player's ring on the camera, and far dots and trails on the mini court. Also Material `error` and the background of the model-load error banner, whose card-white text is 19 sp bold: large text, so it clears 3:1 on red where smaller text would miss 4.5:1.
- **Near Blue** (near): the same jobs for the near player.

### Neutral
- **Stand Black** (ink): the scaffold, the launch screens on both platforms, every numeral and word on a card, and the 85% translucent backing of the status chip and HIT AT button over the camera. At 25% it draws the hinge line across count cards.
- **Raised Black** (raised): the bottom sheet (Material `surface`).
- **Steel** (steel): the 3 px board frame, the 2 px outline of outlined buttons, the 1 px status chip border, mini-court lines, detected feet on the camera, the drag handle, and secondary captions on the stand (stat labels, RALLY, LONGEST, other shot types, sheet help text).
- **Caption Grey** (caption-grey): the only grey on paper: the SHOTS caption, the ESTIMATE caption, and the corner-step subline.
- **Ring Grey** (ring): the two ring holes at the top of every flip card, and the slider's inactive track.

### Named Rules
**The Two Sides Rule.** Red always means far and blue always means near. Neither is ever an accent, a status colour for something else, or a decoration; the one exception in the build is the error banner, which reuses red as Material `error`.

**The Paper Carries Ink Rule.** Text on paper is ink, or caption grey for captions. Text on the stand is paper, or steel for secondary labels. No other text colours.

## Typography

**Display Font:** Archivo Black (Archivo, weight 900), bundled under the SIL OFL.
**Body Font:** Archivo Narrow (500 and 700), bundled under the SIL OFL.

**Character:** A blunt, wide scoreboard numeral against a condensed, tracked label face; the pair reads like painted card numbers and stencilled captions.

The three styles are functions in `lib/main.dart`: `numerals(size)` (Archivo 900, line height 1, tabular figures, ink by default), `caps(size)` (Archivo Narrow 700, line height 1.15, tracking 0.1 em, paper by default) and `body(size)` (Archivo Narrow 500 or 700, line height 1.25, paper by default). New text uses one of these, never a raw TextStyle.

### Hierarchy
- **Count numerals** (numerals 64): shot totals on the two count cards, scaled down to fit the 92 px card.
- **Step numeral** (numerals 40): the 1–4 corner number on the setup card.
- **Shot name** (numerals 34): the newest named shot on the last-shot card, uppercased, scaled down to fit.
- **Small numerals** (numerals 24 and 22): the rally number and slider value (paper on the stand), and the shot speed on the last-shot card (22).
- **Tile numerals** (numerals 15, and 13 for corner-dot labels): shot-type counts.
- **Strip caps** (caps 19): FAR and NEAR on the side strips and the last-shot tag. 19 sp bold is large text, so paper on red and blue passes 3:1.
- **Title and button caps** (caps 15, 14): the sheet heading and every button label.
- **Label caps** (caps 12, 11, 10.5, 10): FPS, shot-type names, SHOTS, stat labels, RALLY, IN RALLY, LONGEST, ESTIMATE, and the "~ = ESTIMATE" key.
- **Body lead** (body 17, 700): the corner instruction and "Waiting for the first hit".
- **Body** (body 15, 14, 13): snackbar (15, 700), sheet help (14), stat values (13, 700), corner subline (13).
- **Body small** (body 12): the swing readout and the other-shot-types line.

### Named Rules
**The Two Voices Rule.** Numbers are Archivo Black; words are Archivo Narrow. A word set in Archivo Black is allowed only as the shot name on the last-shot card.

**The 1.3x Clamp Rule.** The app wraps every route in `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)`. The board is a fixed panel; past 1.3x its labels no longer fit. Fixed-size type inside cards uses FittedBox scale-down, not wrapping.

## Layout

Portrait only. The screen is a column: the camera on top, the board at the bottom, and any spare height between them (space-between), so the setup card always sits at the bottom of the screen.

- **Camera.** Never taller than its 3:4 frame (height = min(available, width / 0.75)), so the frame's sides, and the court's side corners, are never cut off. It runs under the status bar; its overlay content sits in a top safe area with a 10 px gutter and 8 px top inset.
- **Nothing over the camera while setting the court.** During setup the top bar is empty; the corner step lives on the board.
- **Board.** 10 px side gutter, 8 px top and bottom, bottom safe area. A steel-framed panel (3 px, 8 px inside) holds FAR column | 64 px rally column | NEAR column with 8 px gaps; below it, 8 px down, a 60 px wide card.
- **Reduced board while calibrating.** Only the side strips, the count cards and the corner-step card show; the rally column is an empty 64 px slot. The camera then shows the whole frame on phones 812 dp tall or more; a 667 dp phone loses about 6% of the frame at each end.
- **Full board after setup.** Each player column adds two rows of three type tiles (4 px gaps), a two-line other-shots line that always reserves two lines so the board never jumps, and three stat rows (RUN, SPRINT for top running speed, HARDEST for the fastest shuttle). A stat label shrinks to fit, by 15% at most (test/board_test.dart checks 375x667 at 1.3x), never ellipsizes, and keeps a 4 px gap before its value. The camera gives up the height; the overlay keeps mapping through the fill-and-crop and is clipped to the camera, so corners set on the full frame never paint over the board.
- **Spacing rhythm.** 4 px between stacked cards and tiles, 8 px between board blocks, 10 px screen gutter, 12–16 px inside the sheet, 20 px sheet sides.

## Elevation & Depth

Flat. Depth is tonal: paper cards on a black stand, a raised black sheet. The single shadow is under flip cards, a soft drop that makes them hang off the rings rather than lie printed on the board.

### Shadow Vocabulary
- **Card hang** (0 2 px 4 px blur, black at 60%): every flip card (count cards and the last-shot card). Not on type tiles, strips, the frame or buttons.

### Named Rules
**The One Shadow Rule.** Only flip cards cast a shadow, and it is soft. No hard offset shadows, no glows, no blur behind panels.

## Shapes

Small, tight corners: 3 px on type tiles, 4 px on flip cards, 6 px on the board frame, buttons, the status chip and the error banner. Side strips and the last-shot side tag are square. Lines are steel at 1 px (chip, mini court), 2 px (buttons) and 3 px (board frame). Every flip card carries two 6 px ring holes 16 px apart, 5 px from its top edge; count cards add a 1.5 px hinge line at mid-height. Word cards never get the hinge, because it would strike through the words.

## Components

### Flip Card (signature)
A ring-bound scoreboard card. Paper, 4 px corners, card-hang shadow, two ring holes at the top, optional hinge. When its value changes, the new card falls over the top rings onto the old one: rotateX from -90° to 0° about the top edge, perspective 0.002, 280 ms easeOutCubic; the old card stays still underneath. When the platform asks for no animations (iOS Reduce Motion, Android remove animations) the duration is 0 ms. Used for the two count cards (keyed by shot total), the corner-step card (keyed by tap count and bad-corner state) and the last-shot card (keyed by the newest named shot).

### Count Card
92 px tall flip card with hinge: the shot total in count numerals, captioned SHOTS in caption grey so the two cards read as shot totals, never a score.

### Last-Shot Card
60 px flip card. During setup it holds the corner step: the step numeral in a 52 px slot, "Tap the far-left corner" in body lead, "Outer doubles lines · 1 of 4" in caption grey, and an ink UNDO text button once a corner is set. After setup it shows a FAR/NEAR side tag, the shot name, and, when known, "~138 km/h" over an ESTIMATE caption.

### Side Strips and Type Tiles
28 px strips in the side colour with FAR/NEAR in strip caps. Type tiles are paper, 3 px corners, a tile numeral over an ink caps-11 label, one per shot type (smash, clear, drop, lift, net, drive); the rest share one steel line.

### Buttons
Material buttons themed in ThemeData. Outlined: paper text, 2 px steel border, 6 px corners, caps 14, 48 x 48 minimum; over the camera it gets an 85% ink fill (the HIT AT n button, with an 18 px Material tune icon). Text: paper caps 14, 48 x 48 minimum; on paper cards it switches to ink.

### Status Chip
Over the camera after setup: 85% ink, 1 px steel border, 6 px corners, FPS in caps 12 and the swing readout in steel body 12.

### Bottom Sheet and Slider
Raised black sheet with a steel drag handle: HIT SENSITIVITY title, steel help text, a 4–16 slider in 12 steps (paper track and thumb, ring-grey inactive track, ink active ticks, steel inactive ticks, paper value bubble with ink bold text) beside its value in small numerals, then SET COURT AGAIN (outlined) and RESET STATS (text).

### Snackbar
Paper with ink body 15 bold and an ink UNDO action; used for "Stats cleared".

### Camera Overlay and Mini Court
Overlay: court outline in paper 2 px, net 4 px, corner taps as 11 px paper dots with ink numerals, detected feet as 4 px steel dots, each tracked player as a 10 px ring in their side colour, 3 px stroke, with a square side-colour tag 4 px below it reading P1 (far) or P2 (near) in 19 sp card-white numerals (large text, so it clears 3:1 on red); the tag flips above the ring when it would leave the camera, stays inside its side edges, and ring and tag drop after about a second without that player. The plugin's own boxes, labels and skeletons are switched off. Mini court: steel 1 px lines, paper net, the last 40 hit points as side-coloured dots fading from 30% to 100% by age, the last shot as a paper line, trails at 45%, players as side-coloured dots with a paper edge.

**Video mode.** A saved clip takes the camera's place, shown whole and never cropped: the picture box is the largest box of the clip's shape that fits, so a 16:9 TV clip runs screen-wide and is shorter than the camera, and it starts below the status bar so its top corners can be tapped. The status chip reads VIDEO (caps 12) over "~0.6× speed" (steel body 12): analysed video seconds per wall second, smoothed, or "Paused". The swing line is dropped. On a TV cut (a close-up, a replay, the crowd), a 55% ink scrim dims the picture. A centred ink card with a 2 px steel border and 6 px corners reads NOT THE COURT (caps 15) over "Counting paused" (steel body 14), and the rings and tags stay hidden until the court is back. When a hit counts, that player's ring fills with their side colour at 35% under a 3 px card-white edge, and the tag reads P1 HIT or P2 HIT for half a second of video time. The shot's name follows on the last-shot card once it is known; live mode has no flash. The last-shot card carries the clip's controls, which stay put while the card flips under them: a round ink play/pause button on the left, ✕ (back to the camera) on the right, and a 3 px ink progress line along the top edge. The time ("0:42 / 2:10", caption-grey body 12 bold) sits under the side tag, because beside the speed the row runs past a 375 dp phone at 1.3x.

## Do's and Don'ts

### Do:
- **Do** put every changing number on a Flip Card, and key it by the value so it flips only when the value changes.
- **Do** honour `MediaQuery.disableAnimationsOf`: the flip drops to 0 ms.
- **Do** start every estimated figure with "~" (run distance, sprint, hardest hit, shot speed), caption the headline shot speed ESTIMATE, and keep the "~ = ESTIMATE" key in the board's middle column, level with the stat lines.
- **Do** caption player totals SHOTS so the two big numbers never read as a match score.
- **Do** keep the camera no taller than its 3:4 frame, and keep anything off the camera while the court is being set.
- **Do** keep touch targets at 48 x 48 or larger and keep controls in the bottom sheet, never on the board.
- **Do** use the `numerals`, `caps` and `body` helpers and the six colour constants plus the two greys (caption grey, ring grey); launch screens stay Stand Black.

### Don't:
- **Don't** use red or blue for anything but far and near.
- **Don't** add neon accents, glass blur, gradients, glows or hard offset shadows.
- **Don't** put the hinge line on a card that carries words.
- **Don't** let any number or label read as a score, a line call or a precise measurement.
- **Don't** raise the text-scale clamp above 1.3x without reworking the board.

# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Recreational badminton players filming their own singles matches. One of them sets a phone on a tripod high behind one baseline, starts the app, and plays. During play they glance at the screen from the court, several metres away; that glance is the main way the screen is read.

## Product Purpose

Live singles match analysis that runs entirely on a phone, with no desktop GPU and no upload. The owner's five objectives: shot counts, shot type (serve, smash, clear, drop, lift, net, drive, block, push), a court map, player stats (distance run, speed), and shuttle speed. Success is a player glancing over mid-match and reading the number they care about without walking to the phone.

## Positioning

Nothing else does live badminton analysis on a phone: SwingVision covers tennis and pickleball only, and the open-source badminton projects need a desktop GPU. Shuttle Live gets every number from one on-device pose model: hits from wrist swings, shot type from contact height and where and when the reply comes, and shuttle speed from hit-to-hit time corrected for air drag.

## Operating Context

- Indoor badminton hall, phone upright (portrait, locked) on a tripod behind one baseline, plugged in, screen kept awake.
- Setup: tap the four outer court corners on the camera view (far-left, far-right, near-right, near-left). After that, nobody touches the phone during play.
- Two players: "far" (across the net) and "near" (closest to the camera).
- A rally ends after 3 s with no hit; each shot is named when its reply arrives or the rally ends.

## Capabilities and Constraints

- One look on both iPhone and Pixel (one Flutter codebase, its own design rather than per-OS styling). Material structure underneath; on iPhone the OS guarantees still apply (safe areas, Reduce Motion).
- Singles only. One camera cannot make line calls or keep score.
- Shot types are rule-of-thumb labels; shuttle speed is an estimate and needs a returned shot; arcing shots (clears, lifts) read low.
- A hit-threshold slider tunes swing sensitivity on court; the live swing speeds are shown so it can be tuned.
- First launch downloads the pose model (needs internet). The Ultralytics model is AGPL: private testing only, not for public release yet.

## Brand Commitments

Working name "Shuttle Live". No logo, colours or other assets yet.

## Evidence on Hand

None. The app has not been tested on a real court; there are no accuracy figures, users or testimonials, and none may be invented.

## Product Principles

1. Readable from the court: the numbers that matter must be legible from several metres away at a glance.
2. Hands off during play: everything that needs a touch happens before the first serve.
3. Honest numbers: estimates look like estimates, and nothing claims a precision the app does not have.
4. Fast setup: from opening the app to tracking in under a minute.

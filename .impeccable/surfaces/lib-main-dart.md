---
version: 1
slug: "lib-main-dart"
primary_target: "lib/main.dart"
related_targets: []
---

## Scope

The one live screen of Shuttle Live (lib/main.dart): the camera, or a saved clip, with court calibration and P1/P2 player tags, then the live board. Mode: Operate. Audience: recreational players filming their own singles match from a tripod behind the baseline, glancing from the court; they walk up between games for detail. Constraint: one look on both iPhone and Pixel; native Material controls; every speed is an estimate and says so.

## Direction contract

THESIS: Every number a player needs sits on flip cards that can be read from the near half of the court and at a walk-up, and the cards flip on each hit. A phone held to the camera budget cannot carry type readable from the far baseline (~13 m), so the build claims only what it delivers. It refuses the fitness-app grid of small dark stat tiles with a neon accent.

OWN-WORLD: The umpire-stand scoreboard. Matte black #121212 ground, steel #8a9099 frame lines, card-white #f4f2ec flip cards with a hinge line and two ring holes, heavy Archivo 900 numerals in black. Far side red #d6342c, near side blue #1f5fbf, as header strips, court dots and trails. Archivo Narrow tracked caps for labels. No neon, glass or gradients.

STORY: From the court the player reads who hit what and how many. Between games they read the shot types, distance run and estimated shuttle speed. They trust it because estimates are labelled and nothing claims to be a score.

FIRST VIEWPORT: The camera sits on top with nothing over it while setting the court, so all four corners can be tapped. The camera is never taller than its 3:4 frame, so the side corners are never cut off. While the court is being set, the board holds only the side strips, the count cards and the corner step, so the camera shows the whole frame on phones 812 dp tall or more. A 667 dp phone still loses about 6% of the frame at each end. Spare height sits between the camera and the board, keeping the corner card at the bottom. Below the camera is a steel-framed board: FAR card | top-down court with the rally number | NEAR card. Each card shows the shot total huge (~64sp, captioned SHOTS), with six small shot-type cards and run and speed lines under it. Then a wide card that holds the flipping 1–4 corner step during setup, and afterwards the newest named shot ("NEAR · SMASH · ~138 km/h · ESTIMATE"). The controls (hit-threshold slider, Set court again, Reset stats) live in a Material bottom sheet behind a "HIT AT n" button on the camera. A 48 dp controls row would crop the 3:4 camera frame past the near corners, and the controls are touched rarely, never mid-rally.

FORM: Umpire flip scoreboard, the pick card (second on the hand, after the roll's Shuttle Tube); seed:75e1c2058650d7b6. Signature move: the count cards and the last-shot card flip over their top rings on each hit.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

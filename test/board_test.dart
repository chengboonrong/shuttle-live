import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_live/main.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'fonts.dart';

void main() {
  // Real fonts, so the overflow check measures what a phone shows.
  setUpAll(loadRealFonts);

  // A 667-tall phone still loses ~6% of the frame at each end while the court is set.
  for (final (name, size, textScale, wholeFrame) in [
    ('small phone', const Size(375, 667), 1.0, false),
    ('small phone at the largest text', const Size(375, 667), 1.3, false),
    ('large phone', const Size(430, 932), 1.0, true),
  ]) {
    testWidgets('the board fits a $name', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const LivePage()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('FAR'), findsOneWidget);
      // Run again with --dart-define=DEMO=true to check a full board too.
      expect(find.text('Tap the far-left corner'), demo ? findsNothing : findsOneWidget);
      // The camera never runs taller than the frame, so the court's side corners stay on screen.
      final camera = tester.getSize(find.byType(YOLOView));
      final frame = camera.width / frameAspect;
      expect(camera.height, lessThanOrEqualTo(frame + 0.01));
      if (!demo && wholeFrame) expect(camera.height, closeTo(frame, 0.01));
      // Stat labels shrink to fit (they show once the court is set), but by 15% at most.
      for (final label in ['RUN', 'SPRINT', 'HARDEST']) {
        final texts = find.text(label);
        for (var i = 0; i < texts.evaluate().length; i++) {
          final box = find.ancestor(of: texts.at(i), matching: find.byType(FittedBox)).first;
          final scale = tester.getSize(box).width / tester.getSize(texts.at(i)).width;
          expect(scale, greaterThanOrEqualTo(0.85), reason: '$label on a $name');
        }
      }
    });
  }
}

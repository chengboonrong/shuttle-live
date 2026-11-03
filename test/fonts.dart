import 'dart:io';

import 'package:flutter/services.dart';

/// The app's bundled faces, so a widget test measures what a phone shows
/// rather than the square test glyphs.
Future<void> loadRealFonts() async {
  for (final (family, files) in [
    ('Archivo', ['Archivo-Black.ttf']),
    ('Archivo Narrow', ['ArchivoNarrow-Medium.ttf', 'ArchivoNarrow-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File('fonts/$f').readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await loader.load();
  }
}

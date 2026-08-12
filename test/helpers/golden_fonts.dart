import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' show fail;

/// Loads the real Roboto + MaterialIcons fonts from the Flutter SDK cache
/// so golden-image tests capture actual glyphs instead of the Ahem
/// placeholder. Fail-fast: if the fonts can't be found, the test errors
/// rather than silently rendering Ahem-block goldens.
///
/// Call from `setUpAll` in golden test files ONLY — every other suite must
/// keep the strict wide-block Ahem font (that strictness is what makes the
/// 320px overflow regression tests catch layout bugs, so it must NOT be
/// loaded globally).
Future<void> loadRealFonts() async {
  // Walk up from the flutter_tester binary (…/bin/cache/artifacts/engine/
  // <platform>/flutter_tester.exe) to the SDK root, which holds the
  // material fonts under bin/cache/artifacts/material_fonts/.
  Directory? sdkRoot;
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8 && dir.parent.path != dir.path; i++, dir = dir.parent) {
    if (dir.path.endsWith('bin') &&
        Directory('${dir.path}/cache/artifacts/material_fonts').existsSync()) {
      sdkRoot = dir.parent;
      break;
    }
  }
  sdkRoot ??= Directory(
    Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter_windows_3.27.3-stable',
  );

  final fontDir = Directory(
    '${sdkRoot.path}/bin/cache/artifacts/material_fonts',
  );
  if (!fontDir.existsSync()) {
    fail(
      'Material fonts not found under ${fontDir.path}. '
      'Install the Flutter SDK or set FLUTTER_ROOT before regenerating goldens.',
    );
  }

  final roboto = FontLoader('Roboto');
  for (final f in fontDir.listSync().whereType<File>()) {
    final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
    if (name.startsWith('roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(f.readAsBytes().then((b) => ByteData.sublistView(b)));
    }
  }
  await roboto.load();

  final iconsFile = File(
    '${fontDir.path}${Platform.pathSeparator}materialicons-regular.otf',
  );
  if (iconsFile.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(iconsFile.readAsBytes().then((b) => ByteData.sublistView(b)));
    await icons.load();
  }
}

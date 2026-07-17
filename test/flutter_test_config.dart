import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers the fonts the goldens render with.
///
/// A widget test builds no asset bundle, so every glyph — text *and* icons —
/// otherwise comes out as a placeholder box. A golden of a screen of boxes would
/// pass forever and prove nothing, so this is what makes the goldens legible.
///
/// The two app families are read off disk (the paths mirror `pubspec.yaml`).
/// MaterialIcons is not ours: it ships with the SDK, and `uses-material-design`
/// only bundles it into a real build, never into a test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final family in const ['Outfit', 'JetBrainsMono']) {
    await _register(family, 'assets/fonts/$family.ttf');
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError(
      'FLUTTER_ROOT is unset, so MaterialIcons cannot be loaded and every icon '
      'in a golden would render as an empty box. Run these tests with '
      '`flutter test`.',
    );
  }

  await _register(
    'MaterialIcons',
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );

  return testMain();
}

Future<void> _register(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) throw StateError('Missing font for $family: $path');

  final loader = FontLoader(family)
    ..addFont(
      file.readAsBytes().then(ByteData.sublistView),
    );
  await loader.load();
}

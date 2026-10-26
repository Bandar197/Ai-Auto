import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The OBD engine must stay pure Dart (no Flutter, no UI, no diagnosis).
void main() {
  test('lib/obd has no Flutter or app-layer imports', () {
    final offenders = <String>[];
    for (final f in Directory('lib/obd').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final line in f.readAsLinesSync()) {
        final l = line.trim();
        if (!l.startsWith('import ')) continue;
        if (l.contains('package:flutter') || l.contains('package:automind_app/') || l.contains('../core/') || l.contains('../state/') ||
            l.contains('../features/') || l.contains('../platform/') || l.contains('../ui/')) {
          offenders.add('${f.path}: $l');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}

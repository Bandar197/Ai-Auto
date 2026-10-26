import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fails when mobile/assets/shared drifts from ../shared. Fix with
/// `tools/sync_shared.sh` from the repository root.
void main() {
  const dirs = ['obd', 'scenarios', 'kb', 'schemas', 'diag'];
  final shared = Directory('../shared');

  test('shared contracts are present', () {
    expect(shared.existsSync(), isTrue, reason: 'run tests from mobile/ inside the monorepo');
    expect(File('assets/shared/obd/pids.json').existsSync(), isTrue);
  });

  for (final d in dirs) {
    test('assets/shared/$d mirrors shared/$d byte-for-byte', () {
      final src = Directory('../shared/$d');
      final dst = Directory('assets/shared/$d');
      List<String> names(Directory x) => x.existsSync()
          ? (x.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).where((n) => n.endsWith('.json')).toList()..sort())
          : <String>[];
      final a = names(src);
      final b = names(dst);
      expect(b, a, reason: 'file set differs — run tools/sync_shared.sh');
      for (final n in a) {
        expect(File('${dst.path}/$n').readAsBytesSync(), File('${src.path}/$n').readAsBytesSync(),
            reason: '$d/$n is out of date — run tools/sync_shared.sh');
      }
    });
  }
}

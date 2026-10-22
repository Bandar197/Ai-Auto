import 'dart:io';

import 'package:automind_app/core/kb/local_kb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('list format', () {
    final kb = LocalKb.fromJsonString('[{"code":"p0171","description_en":"System too lean","description_ar":"خليط فقير","severity":"medium"}]');
    expect(kb.lookup('P0171')!.description('ar'), 'خليط فقير');
    expect(kb.lookup('P0171')!.severity, 'medium');
    expect(kb.lookup('P9999'), isNull);
  });

  test('map format nested under dtcs with version', () {
    final kb = LocalKb.fromJsonString('{"version":"2026.10","dtcs":{"P0300":{"description_en":"Random misfire","common_causes":["plugs","coils"]}}}');
    expect(kb.version, '2026.10');
    expect(kb.lookup('p0300')!.description('ar'), 'Random misfire'); // falls back to English
    expect(kb.lookup('P0300')!.causesEn, ['plugs', 'coils']);
  });

  test('invalid codes are ignored', () {
    final kb = LocalKb.fromJsonString('[{"code":"X1234"},{"code":"P01"}]');
    expect(kb.isEmpty, isTrue);
  });

  test('bundled KB asset (shared/kb/dtc_definitions.json) parses when present', () {
    final f = File('assets/shared/kb/dtc_definitions.json');
    if (!f.existsSync()) {
      markTestSkipped('KB not shipped yet');
      return;
    }
    final kb = LocalKb.fromJsonString(f.readAsStringSync());
    expect(kb.isEmpty, isFalse);
    expect(kb.version, isNotNull);
    for (final code in ['P0106', 'P0171', 'P0128', 'P0302', 'P0562']) {
      final e = kb.lookup(code);
      expect(e, isNotNull, reason: code);
      expect(e!.description('ar'), isNotEmpty);
      expect(e.description('en'), isNotEmpty);
    }
  });
}

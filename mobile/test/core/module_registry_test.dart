import 'dart:io';

import 'package:automind_app/core/module_registry.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ModuleRegistry reg;

  setUpAll(() {
    // Load the real bundled registry so the test guards the shipped data too.
    final src = File('assets/shared/obd/modules.json').readAsStringSync();
    reg = ModuleRegistry.fromJsonString(src);
  });

  test('parses profiles and a generic profile exists', () {
    expect(reg.profiles, isNotEmpty);
    expect(reg.generic, isNotNull);
  });

  test('make match comes before generic, de-duped', () {
    final fca = reg.candidatesFor('Dodge'); // alias of chrysler
    expect(fca, isNotEmpty);
    // FCA airbag is 29-bit; it must appear and precede any generic 11-bit fallback.
    final airbags = fca.where((m) => m.category == ModuleCategory.airbag).toList();
    expect(airbags.first.idBits, 29);
    // No duplicate addresses.
    final keys = fca.map((m) => '${m.requestId}:${m.responseId}:${m.idBits}').toList();
    expect(keys.toSet().length, keys.length);
  });

  test('unknown make → generic only', () {
    final g = reg.candidatesFor('NoSuchMake');
    final gen = reg.generic!.modules.length;
    expect(g.length, gen);
  });

  test('empty make → generic only', () {
    expect(reg.candidatesFor(null).length, reg.generic!.modules.length);
    expect(reg.candidatesFor('').length, reg.generic!.modules.length);
  });

  test('case-insensitive alias match', () {
    expect(reg.candidatesFor('KIA'), isNotEmpty);
    expect(reg.candidatesFor('lexus'), isNotEmpty);
  });

  test('only approved registry addresses — no blind 0x700–0x7EF band', () {
    for (final make in ['hyundai', 'kia', 'toyota', 'ford', 'gm', 'chrysler', 'NoSuchMake']) {
      final c = reg.candidatesFor(make);
      expect(c.length, lessThan(16), reason: make);
    }
    final h = reg.candidatesFor('hyundai');
    expect(h.any((m) => m.requestId == 0x7D4), isTrue);
  });

  test('verified flag is carried; shipped Hyundai SRS 7D4 is NOT verified', () {
    final srs = reg.candidatesFor('hyundai').firstWhere((m) => m.requestId == 0x7D4);
    expect(srs.verified, isFalse);
    final r = ModuleRegistry.fromJsonString(
        '{"profiles":[{"make":"x","modules":[{"key":"srs","request":"7D0","response":"7D8","verified":true}]}]}');
    expect(r.candidatesFor('x').single.verified, isTrue);
  });
}

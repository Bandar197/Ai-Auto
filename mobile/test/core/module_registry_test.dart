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
}

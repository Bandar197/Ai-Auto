import 'dart:io';

import 'package:automind_app/core/controller_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ControllerCatalog cat;

  setUpAll(() {
    cat = ControllerCatalog.fromJsonString(File('assets/shared/diag/controller_identifiers.json').readAsStringSync());
  });

  test('loads 459 identifiers, 55 Hyundai', () {
    expect(cat.entries.length, 459);
    expect(cat.filter(make: 'hyundai').length, 55);
  });

  test('all entries are unique ids', () {
    final ids = cat.entries.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('filter by make and query', () {
    final srs = cat.filter(make: 'hyundai', query: 'restraint');
    expect(srs, isNotEmpty);
    expect(srs.every((e) => e.make == 'hyundai'), isTrue);
  });

  test('label strips make prefix and _controller suffix', () {
    final bcm = cat.entries.firstWhere((e) => e.id == 'hyundai_bcm_controller');
    expect(bcm.label.toLowerCase(), 'bcm');
  });
}

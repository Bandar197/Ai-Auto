import 'package:automind_app/core/vehicle_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every model make is a known make', () {
    for (final make in kModels.keys) {
      expect(kMakes.containsKey(make), isTrue, reason: 'model make "$make" is not in kMakes');
    }
  });

  test('no empty model lists and no duplicate models per make', () {
    kModels.forEach((make, models) {
      expect(models, isNotEmpty, reason: '$make has an empty model list');
      expect(models.toSet().length, models.length, reason: '$make has duplicate models');
    });
  });

  test('modelsFor resolves known makes and is empty for unknown/null', () {
    expect(modelsFor('Toyota'), contains('Camry'));
    expect(modelsFor('Dodge'), contains('Challenger'));
    expect(modelsFor('NoSuchMake'), isEmpty);
    expect(modelsFor(null), isEmpty);
  });

  test('fuel and transmission enums have bilingual labels', () {
    for (final v in kFuelTypes.values) {
      expect(v.$1.trim(), isNotEmpty);
      expect(v.$2.trim(), isNotEmpty);
    }
    for (final v in kTransmissions.values) {
      expect(v.$1.trim(), isNotEmpty);
      expect(v.$2.trim(), isNotEmpty);
    }
  });
}

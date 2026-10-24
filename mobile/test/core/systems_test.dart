import 'package:automind_app/core/systems.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DTC → system by letter and subsystem', () {
    expect(systemIdForDtc('P0301', subsystem: 'ignition'), 'engine');
    expect(systemIdForDtc('P0171', subsystem: 'fuel'), 'engine');
    expect(systemIdForDtc('P0420', subsystem: 'emissions'), 'emissions');
    expect(systemIdForDtc('P0442', subsystem: 'evap'), 'emissions');
    expect(systemIdForDtc('P0700', subsystem: 'transmission'), 'transmission');
    expect(systemIdForDtc('P0620', subsystem: 'charging'), 'electrical');
    expect(systemIdForDtc('P0606', subsystem: 'electrical'), 'electrical');
    expect(systemIdForDtc('C0035'), 'abs');
    expect(systemIdForDtc('U0100'), 'network');
    expect(systemIdForDtc('B0051', subsystem: 'airbag'), 'airbag');
    expect(systemIdForDtc('B1013'), 'body');
  });

  test('powertrain code with unknown subsystem defaults to engine', () {
    expect(systemIdForDtc('P1234'), 'engine');
    expect(systemIdForDtc('P0101'), 'engine');
  });

  test('module category → system', () {
    expect(systemIdForModuleCategory(ModuleCategory.airbag), 'airbag');
    expect(systemIdForModuleCategory(ModuleCategory.abs), 'abs');
    expect(systemIdForModuleCategory(ModuleCategory.other), 'body');
  });

  test('catalogue ids are unique and resolvable', () {
    final ids = kVehicleSystems.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(systemById(id).id, id);
    }
  });
}

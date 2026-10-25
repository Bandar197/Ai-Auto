import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/full_scan_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// buildFullScanRecording must carry the honest module-scan outcomes and the OBD
/// codes into an upload-ready recording (so the server report shows SRS/ABS/body).
void main() {
  ModuleScan airbag(ModuleOutcome o, {List<UdsDtc> dtcs = const []}) => ModuleScan(
        module: const UdsModule(
          key: 'srs', nameEn: 'Airbag (SRS)', nameAr: 'الإيرباق',
          requestId: 0x7D0, responseId: 0x7D8, category: ModuleCategory.airbag,
        ),
        dtcs: dtcs,
        outcome: o,
      );

  test('carries module scans + obd codes + vehicle, and maps outcomes', () {
    final rec = buildFullScanRecording(
      dataMode: 'live',
      obdDtcs: const [Dtc('P0106', DtcStatus.stored)],
      moduleScans: [airbag(ModuleOutcome.noResponse)],
      vehicle: const {'make': 'Hyundai', 'model': 'Sonata', 'model_year': 2012},
    );
    expect(rec.dataMode, 'live');
    expect(rec.source['app'], 'full_scan');
    expect(rec.vehicle['make'], 'Hyundai');
    expect(rec.dtcs.single.code, 'P0106');
    expect(rec.moduleScans.single.outcome, 'no_response');
    expect(rec.moduleScans.single.address, '7D0');

    // The recording serializes module_scans for upload.
    final j = rec.toJson();
    expect((j['module_scans'] as List).single['outcome'], 'no_response');
  });

  test('a module that did not answer carries no codes even if some were passed', () {
    final rec = buildFullScanRecording(
      dataMode: 'live',
      obdDtcs: const [],
      moduleScans: [airbag(ModuleOutcome.noResponse, dtcs: const [UdsDtc(code: 'B0051', ftb: 0, status: 9, flags: ['confirmed'])])],
    );
    expect(rec.moduleScans.single.codes, isEmpty);
  });
}

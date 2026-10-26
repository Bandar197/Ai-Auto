import 'package:automind_app/core/recording/session_journal.dart';
import 'package:automind_app/state/connection_controller.dart';
import 'package:automind_app/state/providers.dart';
import 'package:automind_app/state/scan_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('full scan in demo mode: steps, local report, offline upload queue', () async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...await testOverrides(),
        scanCaptureDurationProvider.overrideWithValue(const Duration(seconds: 1)),
      ],
    );
    addTearDown(container.dispose);
    final assets = container.read(appAssetsProvider);
    final r = await container.read(connectionProvider.notifier).connectDemo(assets.scenario('p0106_map_sensor')!);
    expect(r.ecuOk, isTrue);
    expect(container.read(connectionProvider).isDemo, isTrue);

    await container.read(scanProvider.notifier).run();
    final s = container.read(scanProvider);
    expect(s.error, isNull);
    for (final step in ScanStep.values.where((x) => x != ScanStep.upload)) {
      expect(s.step(step).status, StepStatus.done, reason: '$step ${s.step(step).detail}');
    }
    expect(s.step(ScanStep.dtcs).detail, contains('P0106'));
    expect(s.step(ScanStep.upload).status, StepStatus.skipped); // no account → queued
    expect(s.queued, isTrue);

    final store = container.read(localStoreProvider);
    final report = await store.loadReport(s.reportId!);
    expect(report!.dataMode, 'demo');
    expect(report.simulator, isTrue);
    expect(report.scenarioKey, 'p0106_map_sensor');
    expect(report.dtcs.map((d) => d['code']), containsAll(['P0106']));
    expect(report.freezeFrames.single['dtc'], 'P0106');
    expect(report.milOn, isTrue);
    expect(await store.readQueue(), [report.id]);
    final rec = await store.loadRecording(report.recordingId!);
    expect(rec!.dataMode, 'demo');
    expect(rec.samples.length, greaterThan(5));
    expect(rec.source['kind'], 'simulator');
    // Full TX/RX traffic is kept with the local recording (incl. the VIN request).
    expect(rec.txRxFrames.where((f) => f.dir == 'tx').map((f) => f.data), contains('0902'));
    expect(rec.txRxFrames.length.isEven, isTrue);
    // A scan that finished normally leaves no journal behind to 'recover'.
    expect(await SessionJournal.interrupted(store.root), isEmpty);
  });
}

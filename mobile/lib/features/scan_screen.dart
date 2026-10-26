import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/connection_controller.dart';
import '../state/scan_controller.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(scanProvider).running) ref.read(scanProvider.notifier).run();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scan = ref.watch(scanProvider);
    final conn = ref.watch(connectionProvider);
    final names = {
      ScanStep.adapter: l.stepAdapter,
      ScanStep.init: l.stepInit,
      ScanStep.protocol: l.stepProtocol,
      ScanStep.ecu: l.stepEcu,
      ScanStep.supported: l.stepSupported,
      ScanStep.vin: l.stepVin,
      ScanStep.dtcs: l.stepDtcs,
      ScanStep.freeze: l.stepFreeze,
      ScanStep.capture: l.stepCapture,
      ScanStep.upload: l.stepUpload,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.scanTitle)),
      body: Column(children: [
        if (conn.mode != null)
          ModeBanner(mode: conn.mode!.apiValue, originalMode: conn.replay?.dataMode, simulator: conn.isSimulator),
        if (conn.client != null) Padding(padding: const EdgeInsets.all(8), child: StatusChips(status: conn.status, simulator: conn.isSimulator)),
        Expanded(
          child: ListView(children: [
            for (final s in ScanStep.values)
              ListTile(
                leading: _icon(scan.step(s).status),
                title: Text(names[s]!),
                subtitle: _subtitle(context, s, scan),
              ),
            if (scan.error != null && scan.error != 'cancelled')
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.scanFailed(scan.error!), style: const TextStyle(color: Colors.red)),
                  Text(linkMessageText(l, conn.status.message)),
                ]),
              ),
            if (scan.queued) Padding(padding: const EdgeInsets.all(16), child: Text(l.scanQueued)),
            if (scan.verificationId != null && !scan.running)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(l.viewVerification),
                  onPressed: () => context.push('/verify/${scan.verificationId}'),
                ),
              ),
            // When codes are found, offer to clear them right here. The clear screen
            // carries the full warning (codes return if the fault is real) and the
            // engine-off / stopped safety checks.
            if (!scan.running &&
                scan.reportId != null &&
                scan.dtcCount > 0 &&
                conn.client != null &&
                conn.mode?.apiValue != 'replay')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(l.clearCodesCount(scan.dtcCount)),
                    onPressed: () => context.push('/clear-dtcs?report=${scan.reportId}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(l.clearWillReturnNote,
                        style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                  ),
                ]),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: scan.running
              ? OutlinedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: Text(l.cancelScan),
                  onPressed: () => ref.read(scanProvider.notifier).cancel(),
                )
              : Row(children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => ref.read(scanProvider.notifier).run(), child: Text(l.retry)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: scan.reportId == null ? null : () => context.pushReplacement('/report/${scan.reportId}'),
                      child: Text(l.viewReport),
                    ),
                  ),
                ]),
        ),
      ]),
    );
  }

  Widget? _subtitle(BuildContext context, ScanStep s, ScanState scan) {
    final l = context.l10n;
    final st = scan.step(s);
    if (s == ScanStep.capture && st.status == StepStatus.running) {
      return Text(l.captureProgress(scan.captureLeft));
    }
    if (st.status == StepStatus.skipped && st.detail.isEmpty) return Text(l.scanSkipped);
    if (st.detail == 'queued') return Text(l.scanQueued);
    if (st.detail.isEmpty) return null;
    return Text(st.detail, textDirection: TextDirection.ltr);
  }

  Widget _icon(StepStatus s) => switch (s) {
        StepStatus.pending => const Icon(Icons.radio_button_unchecked, color: Colors.grey),
        StepStatus.running => const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        StepStatus.done => const Icon(Icons.check_circle, color: Colors.green),
        StepStatus.failed => const Icon(Icons.error, color: Colors.red),
        StepStatus.skipped => const Icon(Icons.remove_circle_outline, color: Colors.blueGrey),
      };
}

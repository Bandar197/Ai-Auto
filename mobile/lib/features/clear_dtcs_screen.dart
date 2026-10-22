import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Clear DTCs (service 04): server approval + engine off + speed 0 +
/// explicit confirmation. The result is reported back to the server.
class ClearDtcsScreen extends ConsumerStatefulWidget {
  const ClearDtcsScreen({super.key});
  @override
  ConsumerState<ClearDtcsScreen> createState() => _ClearDtcsScreenState();
}

class _ClearDtcsScreenState extends ConsumerState<ClearDtcsScreen> {
  double? _rpm;
  double? _speed;
  bool _busy = false;
  String? _message;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readConditions());
  }

  Future<void> _readConditions() async {
    final c = ref.read(connectionProvider).client;
    if (c == null || !c.isReady) return;
    if (c.supported == null) await c.readSupportedPids();
    Future<double?> read(int pid, String key) async {
      if (!c.supported!.supports(pid)) return null;
      final r = await c.readPid(pid);
      return r.isEmpty ? null : r.first.values[key];
    }

    final rpm = await read(0x0C, 'engine_rpm');
    final speed = await read(0x0D, 'vehicle_speed');
    if (mounted) {
      setState(() {
        _rpm = rpm;
        _speed = speed;
      });
    }
  }

  Future<void> _run() async {
    final l = context.l10n;
    final conn = ref.read(connectionProvider);
    final client = conn.client;
    if (client == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.clearDtcsTitle),
        content: Text('${l.clearDtcsWarning}\n\n${l.clearDtcsChecklist}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.clearDtcsConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final api = ref.read(apiProvider);
    try {
      await _readConditions();
      if (_rpm == null || _speed == null) {
        setState(() => _message = l.clearConditionsFailed('engine speed / vehicle speed not readable'));
        return;
      }
      final user = ref.read(authProvider).value;
      if (user == null || !await api.isReachable()) {
        setState(() => _message = l.clearRequiresServer);
        return;
      }
      final vehicleId = ref.read(settingsProvider).selectedVehicleId;
      final op = await api.requestOperation({
        'procedure_key': 'clear_dtcs',
        if (vehicleId != null && !vehicleId.startsWith('local-')) 'vehicle_id': vehicleId,
        'data_mode': client.dataMode.apiValue,
        'consent_text': l.clearDtcsWarning,
        'confirmed': true,
        'conditions': {'engine_running': _rpm! > 0, 'vehicle_speed_kmh': _speed!},
      });
      final approval = ClearDtcApproval(
        operationId: op['id'] as String,
        status: op['status'] as String,
        commands: [for (final c in (op['commands'] as List? ?? const [])) '$c'],
      );
      if (!approval.approvesClear) {
        setState(() => _message = l.clearRejected('${op['reason'] ?? op['status']}'));
        return;
      }
      ClearDtcOutcome outcome;
      try {
        outcome = await client.clearDtcs(approval);
      } on PolicyViolationException catch (e) {
        await api.reportOperation(approval.operationId, {
          'status': 'failed',
          'request_frames': const <String>[],
          'response_frames': const <String>[],
          'result': {'error': e.message},
        });
        setState(() => _message = l.clearConditionsFailed(e.message));
        return;
      }
      await api.reportOperation(approval.operationId, {
        'status': outcome.success ? 'succeeded' : 'failed',
        'request_frames': outcome.requestFrames,
        'response_frames': outcome.responseFrames,
        'result': {'error': outcome.error},
      });
      setState(() {
        _ok = outcome.success;
        _message = outcome.success ? l.clearSuccess : l.clearFailed;
      });
    } on ApiException catch (e) {
      setState(() => _message = e.isOffline ? l.clearRequiresServer : l.clearRejected(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final conn = ref.watch(connectionProvider);
    final canRun = conn.client != null && conn.ecuReady && conn.mode != DataMode.replay;
    return Scaffold(
      appBar: AppBar(title: Text(l.clearDtcsTitle)),
      body: ListView(children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        if (conn.isDemo) Padding(padding: const EdgeInsets.all(12), child: Text(l.clearDemoNote)),
        SectionCard(
          title: l.clearDtcsTitle,
          icon: Icons.warning_amber,
          child: Text(l.clearDtcsWarning),
        ),
        SectionCard(
          title: l.clearDtcsChecklist,
          icon: Icons.checklist,
          child: Column(children: [
            _cond(context, 'rpm', _rpm, (_rpm ?? 1) == 0),
            _cond(context, 'km/h', _speed, (_speed ?? 1) == 0),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: _readConditions, child: Text(l.retry))),
          ]),
        ),
        if (conn.demo != null)
          SwitchListTile(
            title: Text(l.simulateEngineOff),
            value: !conn.demo!.emulator.engineRunning,
            onChanged: (v) {
              ref.read(connectionProvider.notifier).setEngineRunning(!v);
              _readConditions();
            },
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_message!, style: TextStyle(color: _ok ? Colors.green : Colors.red, fontWeight: FontWeight.w700)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(48)),
            icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_sweep),
            label: Text(l.clearDtcsConfirm),
            onPressed: !canRun || _busy ? null : _run,
          ),
        ),
      ]),
    );
  }

  Widget _cond(BuildContext context, String unit, double? v, bool ok) => ListTile(
        dense: true,
        leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red),
        title: Text(v == null ? '— $unit' : '${v.toStringAsFixed(0)} $unit', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
      );
}

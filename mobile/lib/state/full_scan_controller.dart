import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api/api_client.dart';
import '../core/clear/proven_modules.dart';
import '../core/kb/local_kb.dart';
import '../core/measured_findings.dart';
import '../core/recording/session_journal.dart';
import '../core/storage/scan_report.dart';
import '../core/systems.dart';
import '../obd/obd.dart';
import 'adapter_caps_controller.dart';
import 'connection_controller.dart';
import 'providers.dart';

/// Assemble an upload-ready recording from a full scan, carrying the honest
/// module-scan outcomes (SRS/ABS/body) and the standard OBD codes. Pure so it
/// can be unit-tested without the connection/upload providers.
Recording buildFullScanRecording({
  required String dataMode, // 'live' | 'demo' (a replay is never re-recorded)
  required List<ModuleScan> moduleScans,
  required List<Dtc> obdDtcs,
  Map<String, dynamic>? vehicle,
  String sourceKind = 'elm327_wifi',
  String? protocolName,
  String? scenarioKey,
  AdapterCapabilities? adapterCapabilities,
  List<TxRxFrame> txRxFrames = const [],
  DateTime? startedAt, // TX/RX t_ms are relative to this
  String? vin,
  List<RecordingSample> samples = const [],
}) {
  final now = startedAt ?? DateTime.now().toUtc();
  return Recording(
    recordingId: const Uuid().v4(),
    createdAt: now,
    dataMode: dataMode,
    source: {
      'kind': sourceKind,
      'protocol_name': ?protocolName,
      'demo_scenario': ?scenarioKey,
      'app': 'full_scan',
    },
    vehicle: {
      'make': ?vehicle?['make'],
      'model': ?vehicle?['model'],
      'model_year': ?vehicle?['model_year'],
      'vin': ?vin,
    },
    durationMs: samples.isEmpty ? 0 : samples.last.tMs,
    signals: _signalsOf(samples),
    samples: samples,
    dtcs: obdDtcs,
    moduleScans: [for (final m in moduleScans) RecordingModuleScan.fromScan(m)],
    adapterCapabilities: adapterCapabilities,
    txRxFrames: txRxFrames,
  );
}

List<RecordingSignal> _signalsOf(List<RecordingSample> samples) {
  final seen = <String, RecordingSignal>{};
  for (final s in samples) {
    for (final k in s.values.keys) {
      seen.putIfAbsent(k, () => RecordingSignal(key: k, pid: s.pid));
    }
  }
  return seen.values.toList();
}

/// One fault code found during a full scan, ready for display + "explain".
class ScanCode {
  const ScanCode({required this.code, this.description, this.active = false, this.confirmed = true, this.ecu});
  final String code;
  final String? description;
  final bool active; // module reported it failing now (UDS) — treated as high attention
  final bool confirmed; // stored/confirmed vs pending
  final String? ecu;
}

/// Codes grouped under one vehicle system, with how the read actually went.
class SystemGroup {
  const SystemGroup({
    required this.system,
    this.codes = const [],
    this.checked = false,
    this.refused = false,
    this.readOk = false,
  });
  final VehicleSystem system;
  final List<ScanCode> codes;
  final bool checked; // a read for this system was attempted
  final bool refused; // a module answered but refused (e.g. security gateway)
  final bool readOk; // a genuine, interpretable read happened (the only case "no faults" is honest)

  SystemGroup copy({List<ScanCode>? codes, bool? checked, bool? refused, bool? readOk}) => SystemGroup(
        system: system,
        codes: codes ?? this.codes,
        checked: checked ?? this.checked,
        refused: refused ?? this.refused,
        readOk: readOk ?? this.readOk,
      );
}

class FullScanState {
  const FullScanState({
    this.running = false,
    this.done = false,
    this.error,
    this.stage = '',
    this.groups = const {},
    this.moduleScans = const [],
    this.obdDtcs = const [],
    this.uploading = false,
    this.reportId,
    this.vin,
    this.make,
    this.samples = const [],
    this.measured = const [],
  });

  final bool running;
  final bool done;
  final String? error; // 'not_connected' | other
  final String stage; // current stage label key (system id or '')
  final Map<String, SystemGroup> groups;

  /// Raw results kept so the scan can be uploaded as a recording for a report.
  final List<ModuleScan> moduleScans;
  final List<Dtc> obdDtcs;

  /// Report upload state (for the "view report" action).
  final bool uploading;
  final String? reportId;

  /// VIN read at the start (09 02) and the brand used for descriptions/addresses.
  final String? vin;
  final String? make;

  /// Live values read during the scan (coolant, voltage, rpm, fuel trims) and the
  /// problems they show — faults that often store no code (e.g. overheating).
  final List<RecordingSample> samples;
  final List<MeasuredFinding> measured;
  int get measuredAlerts => measured.where((m) => m.needsAttention).length;

  int get totalCodes => groups.values.fold(0, (n, g) => n + g.codes.length);

  FullScanState copy({
    bool? running,
    bool? done,
    String? error,
    String? stage,
    Map<String, SystemGroup>? groups,
    List<ModuleScan>? moduleScans,
    List<Dtc>? obdDtcs,
    bool? uploading,
    String? reportId,
    String? vin,
    String? make,
    List<RecordingSample>? samples,
    List<MeasuredFinding>? measured,
  }) =>
      FullScanState(
        running: running ?? this.running,
        done: done ?? this.done,
        error: error ?? this.error,
        stage: stage ?? this.stage,
        groups: groups ?? this.groups,
        moduleScans: moduleScans ?? this.moduleScans,
        obdDtcs: obdDtcs ?? this.obdDtcs,
        uploading: uploading ?? this.uploading,
        reportId: reportId ?? this.reportId,
        vin: vin ?? this.vin,
        make: make ?? this.make,
        samples: samples ?? this.samples,
        measured: measured ?? this.measured,
      );
}

class FullScanController extends Notifier<FullScanState> {
  @override
  FullScanState build() => const FullScanState();

  TrafficTap? _traffic;

  Map<String, SystemGroup> _empty() => {for (final s in kVehicleSystems) s.id: SystemGroup(system: s)};

  void _addCode(Map<String, SystemGroup> groups, String systemId, ScanCode c) {
    final g = groups[systemId] ?? SystemGroup(system: systemById(systemId));
    if (g.codes.any((x) => x.code == c.code && x.ecu == c.ecu)) return; // de-dupe
    groups[systemId] = g.copy(codes: [...g.codes, c]);
  }

  Future<void> run() async {
    if (state.running) return;
    final conn = ref.read(connectionProvider);
    final client = conn.client;
    if (client == null || !conn.ecuReady) {
      state = const FullScanState(done: true, error: 'not_connected');
      return;
    }
    final kb = ref.read(appAssetsProvider).kb;
    final lang = ref.read(settingsProvider).locale;
    final groups = _empty();
    state = FullScanState(running: true, groups: groups, stage: 'engine');
    // Capture every command/reply of this scan (kept for the evidence log), and journal
    // it durably so a scan cut short (app killed, link lost) can be recovered.
    await _traffic?.detach();
    final startedAt = DateTime.now().toUtc();
    SessionJournal? journal;
    if (conn.mode == DataMode.live || conn.mode == DataMode.demo) {
      try {
        journal = await SessionJournal.start(ref.read(localStoreProvider).root, {
          'recording_id': const Uuid().v4(),
          'created_at': startedAt.toIso8601String(),
          'data_mode': conn.mode!.apiValue,
          'source': {'kind': conn.sourceKind, 'app': 'full_scan', 'demo_scenario': ?conn.scenarioKey},
        });
      } on Object catch (_) {}
    }
    _traffic = TrafficTap(startedAt: startedAt, onFrame: (f) => journal?.write({'type': 'frame', 'f': f.toJson()}))
      ..attach(client.elm.log);
    void snapshot() => journal?.write({
          'type': 'snapshot',
          'r': {
            'dtcs': [for (final d in state.obdDtcs) d.toJson()],
            'module_scans': [for (final m in state.moduleScans) RecordingModuleScan.fromScan(m).toJson()],
          },
        });
    try {
      await _runStages(client, conn, kb, lang, groups, snapshot);
    } finally {
      await _traffic?.detach();
      // Finished normally → the result is in memory (and saved via finalizeToReport).
      // Thrown midway → keep the journal without an end line for recovery.
      if (state.done) {
        await journal?.complete();
      } else {
        await journal?.close();
      }
    }
  }

  Future<void> _runStages(
    ObdClient client,
    ConnState conn,
    LocalKb kb,
    String lang,
    Map<String, SystemGroup> groups,
    void Function() snapshot,
  ) async {
    // VIN (read-only 09 02) → brand, unless the user picked a vehicle.
    String? vin;
    try {
      vin = (await client.readVin()).vin;
    } on Object catch (_) {}
    final make = effectiveMake(ref.read(selectedVehicleProvider), vin, ref.read(appAssetsProvider));
    state = state.copy(vin: vin, make: make);

    // --- Stage 1: standard OBD codes (engine / emissions / transmission / electrical / network) ---
    final obdDtcs = <Dtc>[];
    try {
      var anyReadOk = false;
      for (final status in DtcStatus.values) {
        final res = await client.readDtcs(status);
        if (res.error == null) anyReadOk = true; // a successful, interpretable read happened
        for (final d in res.dtcs) {
          if (!obdDtcs.any((x) => x.code == d.code && x.ecu == d.ecu)) obdDtcs.add(d);
          final entry = kb.lookupFor(d.code, make: make);
          final sysId = systemIdForDtc(d.code, subsystem: entry?.subsystem);
          _addCode(groups, sysId, ScanCode(
            code: d.code,
            description: entry?.description(lang),
            confirmed: status != DtcStatus.pending,
            ecu: d.ecu,
          ));
        }
      }
      // Mark OBD systems checked; "no faults" is only honest where a read actually succeeded.
      for (final s in kVehicleSystems) {
        if (s.source == ScanSource.obd) groups[s.id] = groups[s.id]!.copy(checked: true, readOk: anyReadOk);
      }
      state = state.copy(groups: {...groups});
    } on Object catch (e) {
      state = state.copy(error: e.toString());
    }

    state = state.copy(obdDtcs: obdDtcs);
    snapshot();

    // --- Stage 1b: measured values (read-only service 01). Many faults store no code —
    // a dead radiator fan, low coolant, a weak alternator — so read what the engine
    // reports right now and judge it. ---
    await _readMeasured(client);

    // --- Stage 2: non-powertrain modules via UDS (SRS / ABS / body) — live only ---
    if (conn.mode != DataMode.replay) {
      state = state.copy(stage: 'modules');
      try {
        final registry = ref.read(appAssetsProvider).modules;
        final candidates = registry.candidatesFor(make);
        final found = await scanModules(
          client.elm,
          candidates: candidates.isNotEmpty ? candidates : kDiscoveryCandidates,
          includeNoResponse: true, // so a module that didn't answer is shown honestly, not as "no faults"
        );
        state = state.copy(moduleScans: found);
        snapshot();
        // A module that answered a read on this car proves its address for this car.
        try {
          await ProvenModulesStore(ref.read(localStoreProvider)).recordFromScan(
            provenVehicleKey(vin: vin, vehicleId: ref.read(settingsProvider).selectedVehicleId),
            found,
            mode: conn.mode ?? DataMode.demo,
          );
        } on Object catch (_) {}
        for (final m in found) {
          final sysId = systemIdForModuleCategory(m.module.category);
          final g = groups[sysId] ?? SystemGroup(system: systemById(sysId));
          groups[sysId] = g.copy(checked: true, refused: g.refused || m.refused, readOk: g.readOk || m.readOk);
          for (final d in m.dtcs) {
            final entry = kb.lookupFor(d.code, make: make);
            _addCode(groups, sysId, ScanCode(
              code: d.code,
              description: entry?.description(lang),
              active: d.active,
              confirmed: d.confirmed,
            ));
          }
        }
        state = state.copy(groups: {...groups});
      } on Object catch (_) {
        // modules are best-effort; engine results already stand.
      }
    }

    state = state.copy(running: false, done: true, stage: '');
  }

  Future<void> _readMeasured(ObdClient client) async {
    final t0 = _traffic?.startedAt ?? DateTime.now().toUtc();
    final samples = <RecordingSample>[];
    var attempted = false;
    try {
      if (client.supported == null) await client.readSupportedPids();
      final sup = client.supported;
      attempted = true;
      final pids = [for (final p in kMeasuredPids) if (sup?.supports(p) ?? false) p];
      for (var round = 0; round < 3; round++) {
        for (final p in pids) {
          try {
            for (final r in await client.readPid(p)) {
              samples.add(RecordingSample(
                tMs: DateTime.now().toUtc().difference(t0).inMilliseconds,
                pid: r.requestId,
                ecu: r.ecu,
                raw: r.raw,
                values: r.values,
              ));
            }
          } on Object catch (_) {}
        }
      }
    } on Object catch (_) {}
    state = state.copy(
      samples: samples,
      measured: measuredFindings(valuesBySignal(samples), coolantAttempted: attempted),
    );
  }

  /// Build a recording from the finished scan (including the honest module-scan
  /// outcomes) and upload it as a session so the server report shows SRS/ABS/body
  /// states. Sets [FullScanState.reportId] on success (queued offline when signed out).
  Future<void> finalizeToReport() async {
    if (state.uploading || !state.done || state.reportId != null) return;
    final conn = ref.read(connectionProvider);
    final mode = conn.mode;
    if (mode == null || mode == DataMode.replay) return; // only a fresh live/demo scan is recordable
    state = state.copy(uploading: true, error: null);

    String? reportId;
    String? error;
    try {
      final rec = buildFullScanRecording(
        dataMode: mode.apiValue,
        moduleScans: state.moduleScans,
        obdDtcs: state.obdDtcs,
        vehicle: ref.read(selectedVehicleProvider),
        vin: state.vin,
        sourceKind: conn.sourceKind,
        scenarioKey: conn.scenarioKey,
        adapterCapabilities: ref.read(adapterCapabilitiesProvider).value,
        txRxFrames: _traffic?.frames ?? const [],
        startedAt: _traffic?.startedAt,
        samples: state.samples,
      );
      final store = ref.read(localStoreProvider);
      await store.saveRecording(rec);
      final vehicleId = ref.read(settingsProvider).selectedVehicleId;
      final report = ScanReport(
        id: const Uuid().v4(),
        createdAt: DateTime.now().toUtc(),
        dataMode: mode.apiValue,
        simulator: conn.isSimulator,
        scenarioKey: conn.scenarioKey,
        recordingId: rec.recordingId,
        vin: state.vin,
        dtcs: [for (final d in rec.dtcs) d.toJson()],
        measured: [for (final m in state.measured) m.toJson()],
        vehicleId: vehicleId != null && !vehicleId.startsWith('local-') ? vehicleId : null,
      );
      await store.saveReport(report);
      reportId = report.id; // saved locally — viewable even if the upload fails

      final queue = ref.read(uploadQueueProvider);
      final user = ref.read(authProvider).value;
      if (user == null) {
        await queue.enqueue(report.id); // offline: report viewable once signed in / online
      } else {
        await queue.uploadOne(report);
      }
    } on ApiException catch (e) {
      error = '${e.code}: ${e.message}'; // report is saved locally; surface the upload error
    } on Object catch (e) {
      error = e.toString();
    } finally {
      // Always clear the spinner; expose the local report id when we got that far.
      state = state.copy(uploading: false, reportId: reportId, error: error);
    }
  }
}

final fullScanProvider = NotifierProvider<FullScanController, FullScanState>(FullScanController.new);

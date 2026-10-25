import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api/api_client.dart';
import '../core/recording/session_journal.dart';
import '../core/storage/clear_entry.dart';
import '../core/storage/scan_report.dart';
import '../obd/obd.dart';
import 'adapter_caps_controller.dart';
import 'connection_controller.dart';
import 'providers.dart';
import 'verification_controller.dart';

enum ScanStep { adapter, init, protocol, ecu, supported, vin, dtcs, freeze, capture, upload }

enum StepStatus { pending, running, done, failed, skipped }

class StepState {
  const StepState(this.status, [this.detail = '']);
  final StepStatus status;
  final String detail;
}

class ScanState {
  const ScanState({
    this.steps = const {},
    this.running = false,
    this.reportId,
    this.error,
    this.captureLeft = 0,
    this.queued = false,
    this.verificationId,
    this.dtcCount = 0,
  });

  final Map<ScanStep, StepState> steps;
  final bool running;
  final String? reportId;
  final String? error;
  final int captureLeft;
  final bool queued;

  /// Number of distinct trouble codes this scan read (drives the "clear codes" action).
  final int dtcCount;

  /// Set when this scan was added as a check to an open clear-and-verify.
  final String? verificationId;

  StepState step(ScanStep s) => steps[s] ?? const StepState(StepStatus.pending);

  ScanState copyWith({
    Map<ScanStep, StepState>? steps,
    bool? running,
    String? reportId,
    String? error,
    int? captureLeft,
    bool? queued,
    String? verificationId,
    int? dtcCount,
  }) =>
      ScanState(
        steps: steps ?? this.steps,
        running: running ?? this.running,
        reportId: reportId ?? this.reportId,
        error: error ?? this.error,
        captureLeft: captureLeft ?? this.captureLeft,
        queued: queued ?? this.queued,
        verificationId: verificationId ?? this.verificationId,
        dtcCount: dtcCount ?? this.dtcCount,
      );
}

/// PIDs captured during a scan (only the supported subset is requested).
const List<int> scanCapturePids = [
  0x0C, 0x0D, 0x05, 0x0B, 0x10, 0x11, 0x04, 0x06, 0x07, 0x08, 0x09, 0x0E, 0x0F, 0x14, 0x15, 0x42, 0x2F, 0x46, 0x33,
  0x03, 0x44, 0x24, 0x34, 0x5C, 0x5E, 0x49, 0x4C, 0x1F,
];

/// One-shot reads included once per scan.
const List<int> scanOncePids = [0x01, 0x1C, 0x51, 0x21, 0x30, 0x31, 0x4D, 0x4E, 0xA6];

/// Live-capture duration during a scan (settings; overridable in tests).
final scanCaptureDurationProvider = Provider<Duration>(
  (ref) => Duration(seconds: ref.watch(settingsProvider.select((s) => s.captureSeconds)).clamp(10, 300)),
);

class ScanController extends Notifier<ScanState> {
  bool _cancel = false;

  @override
  ScanState build() => const ScanState();

  void _set(ScanStep s, StepStatus st, [String detail = '']) {
    state = state.copyWith(steps: {...state.steps, s: StepState(st, detail)});
  }

  void cancel() => _cancel = true;

  Future<void> run() async {
    if (state.running) return;
    _cancel = false;
    state = const ScanState(running: true);
    try {
      final conn = ref.read(connectionProvider);
      if (conn.mode == DataMode.replay && conn.replay != null) {
        await _runReplay(conn);
      } else {
        await _runObd();
      }
    } on Object catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(running: false);
    }
  }

  Future<void> _runObd() async {
    final ctrl = ref.read(connectionProvider.notifier);
    var conn = ref.read(connectionProvider);
    final client = conn.client;
    if (client == null) {
      _set(ScanStep.adapter, StepStatus.failed, 'not connected');
      state = state.copyWith(error: 'not connected');
      return;
    }
    if (!conn.ecuReady) {
      _set(ScanStep.adapter, StepStatus.running);
      final r = await ctrl.reconnect();
      conn = ref.read(connectionProvider);
      if (r == null || !r.adapterOk) {
        _set(ScanStep.adapter, StepStatus.failed, conn.status.detail);
        state = state.copyWith(error: conn.status.message.name);
        return;
      }
    }
    final info = client.info;
    _set(ScanStep.adapter, StepStatus.done, '${client.transport.description}${info.isSimulator ? ' · Simulator' : ''}');
    _set(ScanStep.init, StepStatus.done,
        [info.firmware ?? '', if (info.voltage != null) '${info.voltage!.toStringAsFixed(1)} V'].where((x) => x.isNotEmpty).join(' · '));
    if (!conn.ecuReady) {
      _set(ScanStep.protocol, StepStatus.failed, conn.status.detail);
      state = state.copyWith(error: conn.status.message.name);
      return;
    }
    _set(ScanStep.protocol, StepStatus.done, info.protocolName ?? info.protocolCode ?? '');

    final table = ref.read(appAssetsProvider).table;
    _set(ScanStep.ecu, StepStatus.running);
    _set(ScanStep.supported, StepStatus.running);
    final sup = await client.readSupportedPids();
    _set(ScanStep.ecu, sup.ecus.isEmpty ? StepStatus.failed : StepStatus.done, sup.ecus.join(', '));
    _set(ScanStep.supported, StepStatus.done, '${sup.all.where((p) => p % 0x20 != 0).length} PIDs');
    if (_cancel) return _cancelled();

    final rec = Recorder(
      dataMode: client.dataMode,
      sourceKind: conn.sourceKind,
      table: table,
      newId: const Uuid().v4,
      adapterFirmware: info.firmware,
      protocolCode: info.protocolCode,
      protocolName: info.protocolName,
      demoScenario: conn.scenarioKey,
      app: 'automind-mobile/$appVersion',
    )
      ..setSupported(sup)
      ..adapterCapabilities = ref.read(adapterCapabilitiesProvider).value;
    final eventSub = client.events.listen((e) => rec.addEvent(e.type, e.detail, e.at));
    rec.attachTraffic(client.elm.log);
    // Durable journal: if the app or link dies mid-scan, the session is recoverable.
    SessionJournal? journal;
    try {
      journal = await SessionJournal.start(ref.read(localStoreProvider).root, rec.journalHeader());
      rec.onEntry = journal.write;
    } on Object catch (_) {
      // A journal failure never blocks the scan.
    }
    var saved = false;

    try {
      _set(ScanStep.vin, StepStatus.running);
      final vin = await client.readVin();
      _set(ScanStep.vin, vin.vin == null ? StepStatus.skipped : StepStatus.done, vin.vin ?? (vin.warning ?? ''));
      rec.vehicle = {'vin': vin.vin};
      rec.checkpoint();
      if (_cancel) return _cancelled();

      _set(ScanStep.dtcs, StepStatus.running);
      final dtcs = <Dtc>[];
      final errs = <String>[];
      for (final s in DtcStatus.values) {
        final r = await client.readDtcs(s);
        dtcs.addAll(r.dtcs);
        if (r.error != null) errs.add('${s.service}: ${r.error}');
      }
      rec.dtcs = dtcs;
      rec.checkpoint();
      state = state.copyWith(dtcCount: dtcs.map((d) => d.code).toSet().length);
      _set(ScanStep.dtcs, StepStatus.done, [dtcs.map((d) => d.code).toSet().join(', '), ...errs].where((x) => x.isNotEmpty).join(' · '));
      if (_cancel) return _cancelled();

      _set(ScanStep.freeze, StepStatus.running);
      final ff = await client.readFreezeFrame();
      if (ff != null) rec.freezeFrames = [ff];
      rec.checkpoint();
      _set(ScanStep.freeze, ff == null ? StepStatus.skipped : StepStatus.done, ff?.dtc ?? '');
      if (_cancel) return _cancelled();

      _set(ScanStep.capture, StepStatus.running);
      bool? milOn;
      for (final pid in scanOncePids) {
        if (!sup.supports(pid)) continue;
        for (final r in await client.readPid(pid)) {
          rec.addReading(r);
          if (pid == 0x01 && r.values['mil_on'] != null) milOn = r.values['mil_on'] == 1;
        }
      }
      final pids = [for (final p in scanCapturePids) if (sup.supports(p)) p];
      final seconds = ref.read(scanCaptureDurationProvider).inSeconds;
      client.autoReconnect = true;
      final sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < seconds && !_cancel && pids.isNotEmpty) {
        for (final pid in pids) {
          if (client.isReconnecting) await client.waitReconnect();
          try {
            for (final r in await client.readPid(pid)) {
              rec.addReading(r);
            }
          } on NotSupportedException catch (_) {}
          state = state.copyWith(captureLeft: (seconds - sw.elapsed.inSeconds).clamp(0, seconds));
          if (sw.elapsed.inSeconds >= seconds || _cancel) break;
        }
      }
      client.autoReconnect = false;
      _set(ScanStep.capture, rec.sampleCount == 0 ? StepStatus.failed : StepStatus.done, '${rec.sampleCount}');

      rec.checkpoint();
      final recording = rec.build();
      await _finish(
        recording: recording,
        dataMode: client.dataMode.apiValue,
        simulator: info.isSimulator || conn.demo != null,
        scenarioKey: conn.scenarioKey,
        vin: vin.vin,
        protocolName: info.protocolName,
        milOn: milOn,
        connectionLog: conn.log?.toJson(),
      );
      saved = true;
    } finally {
      await eventSub.cancel();
      await rec.detachTraffic();
      rec.onEntry = null;
      // Saved or cancelled by the user → journal no longer needed. Anything else
      // (error, lost link) keeps it without an end line → offered for recovery.
      if (saved || _cancel) {
        await journal?.complete();
      } else {
        await journal?.close();
      }
    }
  }

  Future<void> _runReplay(ConnState conn) async {
    final r = conn.replay!;
    for (final s in [ScanStep.adapter, ScanStep.init, ScanStep.protocol, ScanStep.ecu]) {
      _set(s, StepStatus.skipped, 'REPLAY');
    }
    _set(ScanStep.supported, StepStatus.done, '${r.supportedPids['01']?.length ?? 0} PIDs');
    _set(ScanStep.vin, r.vehicle['vin'] == null ? StepStatus.skipped : StepStatus.done, '${r.vehicle['vin'] ?? ''}');
    _set(ScanStep.dtcs, StepStatus.done, r.dtcs.map((d) => d.code).toSet().join(', '));
    _set(ScanStep.freeze, r.freezeFrames.isEmpty ? StepStatus.skipped : StepStatus.done);
    _set(ScanStep.capture, StepStatus.done, '${r.samples.length}');
    await _finish(
      recording: r,
      dataMode: DataMode.replay.apiValue,
      originalMode: r.dataMode,
      simulator: r.source['kind'] == 'simulator',
      scenarioKey: r.demoScenario,
      vin: r.vehicle['vin'] as String?,
      protocolName: r.source['protocol_name'] as String?,
      serverRecordingId: conn.replayServerId,
    );
  }

  Future<void> _finish({
    required Recording recording,
    required String dataMode,
    String? originalMode,
    required bool simulator,
    String? scenarioKey,
    String? vin,
    String? protocolName,
    bool? milOn,
    Map<String, dynamic>? connectionLog,
    String? serverRecordingId,
  }) async {
    _set(ScanStep.upload, StepStatus.running);
    final store = ref.read(localStoreProvider);
    await store.saveRecording(recording);
    final vehicleId = ref.read(settingsProvider).selectedVehicleId;
    final report = ScanReport(
      id: const Uuid().v4(),
      createdAt: DateTime.now().toUtc(),
      dataMode: dataMode,
      originalMode: originalMode,
      simulator: simulator,
      scenarioKey: scenarioKey,
      recordingId: recording.recordingId,
      serverRecordingId: serverRecordingId,
      vin: vin,
      protocolName: protocolName,
      dtcs: [for (final d in recording.dtcs) d.toJson()],
      freezeFrames: [for (final f in recording.freezeFrames) f.toJson()],
      vehicleId: vehicleId != null && !vehicleId.startsWith('local-') ? vehicleId : null,
      connectionLog: connectionLog,
      milOn: milOn,
    );
    await store.saveReport(report);
    state = state.copyWith(reportId: report.id);

    final queue = ref.read(uploadQueueProvider);
    final user = ref.read(authProvider).value;
    if (user == null) {
      await queue.enqueue(report.id);
      _set(ScanStep.upload, StepStatus.skipped, 'queued');
      state = state.copyWith(queued: true);
    } else {
      try {
        await queue.uploadOne(report);
        _set(ScanStep.upload, StepStatus.done, 'health ${report.healthScore ?? '-'}');
      } on ApiException catch (e) {
        report
          ..uploadState = 'pending'
          ..lastError = '${e.code}: ${e.message}';
        await store.saveReport(report);
        await queue.enqueue(report.id);
        _set(ScanStep.upload, e.isOffline ? StepStatus.skipped : StepStatus.failed, e.isOffline ? 'queued' : e.message);
        state = state.copyWith(queued: true);
      }
    }
    // Clear-and-verify: a later scan of the same vehicle is another check.
    if (dataMode != DataMode.replay.apiValue) {
      try {
        final key = vehicleKeyFor(
          dataMode: dataMode,
          vehicleId: ref.read(settingsProvider).selectedVehicleId,
          scenarioKey: scenarioKey,
          vin: vin,
        );
        final verify = ref.read(verificationProvider.notifier);
        final open = await verify.openFor(key, dataMode);
        if (open != null) {
          await verify.addCheck(
            open.id,
            ScanSnapshot.fromRecording(recording, takenAt: DateTime.now().toUtc(), sessionId: report.serverSessionId),
          );
          state = state.copyWith(verificationId: open.id);
        }
      } on Object catch (_) {}
    }
    await ref.read(reportsProvider.notifier).refresh();
    await ref.read(pendingUploadsProvider.notifier).refresh();
  }

  void _cancelled() {
    state = state.copyWith(error: 'cancelled');
  }
}

final scanProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);

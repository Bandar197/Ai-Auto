import '../elm327/elm327.dart';
import '../transport/obd_transport.dart';
import 'states.dart';

/// One probe command and what the adapter actually answered (raw, as received).
class ProbeStep {
  const ProbeStep(this.cmd, this.response, this.ok);
  final String cmd;
  final String response;

  /// `?`, NO DATA, UNABLE TO CONNECT, errors and empty replies are never ok.
  final bool ok;

  Map<String, dynamic> toJson() => {'cmd': cmd, 'response': response, 'ok': ok};
  factory ProbeStep.fromJson(Map<String, dynamic> j) =>
      ProbeStep(j['cmd'] as String, j['response'] as String? ?? '', j['ok'] as bool? ?? false);
}

/// Capabilities the probe can establish. Wire names match recording.v2
/// (`adapter_capabilities.capabilities`).
enum Capability {
  headers('headers'),
  filters('filters'),
  canFormatting('can_formatting'),
  isoTp('iso_tp'),
  multiFrame('multi_frame'),
  flowControl('flow_control'),
  protocolSwitching('protocol_switching');

  const Capability(this.wire);
  final String wire;
}

/// How strongly a capability was established.
enum Evidence {
  /// The adapter's behaviour changed as the command should make it change.
  behavioral('behavioral'),

  /// The command was accepted ("OK") but its effect could not be observed.
  acceptedOnly('accepted_only'),

  /// Not tested (with a reason) — must not be relied upon.
  notTested('not_tested');

  const Evidence(this.wire);
  final String wire;
}

/// What the connected adapter PROVED it can do — never what its name claims.
/// `true` = passed, `false` = failed, `null` = not tested. A capability is only
/// [usable] when it passed.
class AdapterCapabilities {
  AdapterCapabilities({
    required this.connection,
    required this.capabilities,
    required this.evidence,
    required this.probe,
    this.name,
    this.firmware,
    this.voltage,
    this.protocol,
    this.notes = const {},
    DateTime? probedAt,
  }) : probedAt = probedAt ?? DateTime.now().toUtc();

  final String? name;

  /// ble | serial | wifi | simulator | unknown
  final String connection;
  final String? firmware;
  final double? voltage;
  final String? protocol;
  final Map<Capability, bool?> capabilities;
  final Map<Capability, Evidence> evidence;
  final Map<Capability, String> notes;
  final List<ProbeStep> probe;
  final DateTime probedAt;

  bool usable(Capability c) => capabilities[c] == true;

  Map<String, dynamic> toJson() => {
    'name': name,
    'connection': connection,
    'firmware': firmware,
    'voltage': voltage,
    'protocol': protocol,
    'capabilities': {for (final c in Capability.values) c.wire: capabilities[c]},
    'evidence': {for (final c in Capability.values) c.wire: (evidence[c] ?? Evidence.notTested).wire},
    'notes': {for (final e in notes.entries) e.key.wire: e.value},
    'probe': [for (final s in probe) s.toJson()],
    'probed_at': probedAt.toIso8601String(),
  };

  factory AdapterCapabilities.fromJson(Map<String, dynamic> j) {
    Capability? byWire(String w) => Capability.values.where((c) => c.wire == w).firstOrNull;
    final caps = (j['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {};
    final ev = (j['evidence'] as Map?)?.cast<String, dynamic>() ?? const {};
    final notes = (j['notes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AdapterCapabilities(
      name: j['name'] as String?,
      connection: j['connection'] as String? ?? 'unknown',
      firmware: j['firmware'] as String?,
      voltage: (j['voltage'] as num?)?.toDouble(),
      protocol: j['protocol'] as String?,
      capabilities: {
        for (final e in caps.entries)
          if (byWire(e.key) != null) byWire(e.key)!: e.value as bool?,
      },
      evidence: {
        for (final e in ev.entries)
          if (byWire(e.key) != null) byWire(e.key)!: Evidence.values.firstWhere((x) => x.wire == e.value, orElse: () => Evidence.notTested),
      },
      notes: {
        for (final e in notes.entries)
          if (byWire(e.key) != null) byWire(e.key)!: '${e.value}',
      },
      probe: [for (final s in (j['probe'] as List? ?? const [])) ProbeStep.fromJson((s as Map).cast<String, dynamic>())],
      probedAt: DateTime.tryParse(j['probed_at'] as String? ?? ''),
    );
  }
}

/// recording.v2 `connection` for a transport kind.
String connectionOf(TransportKind k) => switch (k) {
  TransportKind.ble => 'ble',
  TransportKind.usbSerial => 'serial',
  TransportKind.wifiTcp => 'wifi',
  TransportKind.demo => 'simulator',
};

/// Probes an ELM327-compatible adapter with read-only and reversible commands and
/// returns what it really supports. Run it only while the link is idle (no scan or
/// live polling): it toggles headers briefly and restores the client's expected state
/// (headers as [AdapterInfo.headersOn], receive filter cleared, defaults kept).
///
/// Safety: it sends only AT commands plus read-only OBD requests 0100 and 0902; it
/// never clears codes, never writes to an ECU, and never switches protocol (that
/// would drop the vehicle link).
class CapabilityProbe {
  CapabilityProbe(this.elm);
  final Elm327 elm;

  static const Set<String> _canProtocols = {'6', '7', '8', '9'};

  static bool _okReply(ElmResponse r, {bool expectOk = false}) {
    if (!r.ok) return false; // '?', NO DATA, CAN ERROR, timeout … are mapped to errors
    final t = r.text.trim().toUpperCase();
    if (t.isEmpty || t == '?') return false;
    return !expectOk || t.contains('OK');
  }

  /// Data tokens on the first data line of a reply (for the header behaviour test).
  static int _tokens(ElmResponse r) {
    if (!r.ok || r.lines.isEmpty) return 0;
    return r.lines.first.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).length;
  }

  Future<AdapterCapabilities> run({required AdapterInfo info, required TransportKind transport, required bool ecuConnected}) async {
    try {
      return await _run(info: info, transport: transport, ecuConnected: ecuConnected);
    } catch (_) {
      // Failed midway (link error): best-effort restore so later reads parse correctly.
      try {
        await elm.send(info.headersOn ? 'ATH1' : 'ATH0');
        await elm.send('ATAR');
      } catch (_) {}
      rethrow;
    }
  }

  Future<AdapterCapabilities> _run({required AdapterInfo info, required TransportKind transport, required bool ecuConnected}) async {
    final steps = <ProbeStep>[];
    Future<ElmResponse> step(String cmd, {bool expectOk = false}) async {
      final r = await elm.send(cmd);
      final raw = r.raw.trim();
      steps.add(ProbeStep(cmd, raw.isNotEmpty ? raw : (r.errorLine ?? r.error?.code ?? ''), _okReply(r, expectOk: expectOk)));
      return r;
    }

    final caps = <Capability, bool?>{};
    final ev = <Capability, Evidence>{};
    final notes = <Capability, String>{};

    // --- identity (read-only) ---
    final ati = await step('ATI');
    final at1 = await step('AT@1');
    final rv = await step('ATRV');
    final dp = await step('ATDP');
    final dpn = await step('ATDPN');

    final firmware = _okReply(ati) ? ati.text.trim() : info.firmware;
    final name = _okReply(at1) ? at1.text.trim() : info.description;
    double? voltage = info.voltage;
    if (_okReply(rv)) {
      final m = RegExp(r'(\d+(?:\.\d+)?)\s*V?', caseSensitive: false).firstMatch(rv.text);
      voltage = m == null ? voltage : double.tryParse(m.group(1)!);
    }
    final protocol = _okReply(dp) ? dp.text.trim() : info.protocolName;
    final rawDpn = _okReply(dpn) ? dpn.text.trim().toUpperCase() : (info.protocolCode ?? '');
    // "A6" = auto-detected protocol 6; a lone "A" is protocol A (J1939), not CAN-OBD.
    final dpnCode = rawDpn.length == 2 && rawDpn.startsWith('A') ? rawDpn.substring(1) : rawDpn;
    final isCan = _canProtocols.contains(dpnCode) || _canProtocols.contains(info.protocolCode);

    // --- headers: behavioural when a vehicle answers, else acceptance only ---
    final h0 = await step('ATH0', expectOk: true);
    ElmResponse? noHeaders;
    if (ecuConnected) noHeaders = await step('0100');
    final h1 = await step('ATH1', expectOk: true);
    ElmResponse? withHeaders;
    if (ecuConnected) withHeaders = await step('0100');
    final accepted = _okReply(h0, expectOk: true) && _okReply(h1, expectOk: true);
    if (!accepted) {
      caps[Capability.headers] = false;
      ev[Capability.headers] = Evidence.acceptedOnly;
      notes[Capability.headers] = 'ATH0/ATH1 not accepted';
    } else if (ecuConnected && noHeaders != null && withHeaders != null && noHeaders.ok && withHeaders.ok) {
      final pass = _tokens(withHeaders) > _tokens(noHeaders);
      caps[Capability.headers] = pass;
      ev[Capability.headers] = Evidence.behavioral;
      if (!pass) notes[Capability.headers] = 'ATH1 accepted but replies carry no header bytes';
    } else {
      caps[Capability.headers] = null;
      ev[Capability.headers] = Evidence.notTested;
      notes[Capability.headers] = ecuConnected ? 'vehicle did not answer 0100' : 'needs a connected vehicle to verify';
    }
    // Restore the header state the client runs with.
    await step(info.headersOn ? 'ATH1' : 'ATH0', expectOk: true);

    // --- receive filter (CAN only, behavioural) ---
    if (isCan && ecuConnected) {
      final cra = await step('ATCRA7E8', expectOk: true);
      if (!_okReply(cra, expectOk: true)) {
        caps[Capability.filters] = false;
        ev[Capability.filters] = Evidence.acceptedOnly;
        notes[Capability.filters] = 'ATCRA not accepted';
      } else {
        final r = await step('0100');
        final onlyEcm = r.ok && r.lines.isNotEmpty && (!info.headersOn || r.lines.every((l) => l.trim().toUpperCase().startsWith('7E8')));
        caps[Capability.filters] = onlyEcm;
        ev[Capability.filters] = info.headersOn ? Evidence.behavioral : Evidence.acceptedOnly;
        if (!onlyEcm) notes[Capability.filters] = 'filtered read failed or returned other ECUs';
      }
      await step('ATAR', expectOk: true); // clear the filter (automatic receive)
    } else {
      caps[Capability.filters] = null;
      ev[Capability.filters] = Evidence.notTested;
      notes[Capability.filters] = isCan ? 'needs a connected vehicle to verify' : 'CAN-only feature; protocol is not CAN';
    }

    // --- CAN formatting / flow control: default states, acceptance only ---
    if (isCan) {
      final caf = await step('ATCAF1', expectOk: true);
      caps[Capability.canFormatting] = _okReply(caf, expectOk: true);
      ev[Capability.canFormatting] = Evidence.acceptedOnly;
      final fc = await step('ATFCSM0', expectOk: true);
      caps[Capability.flowControl] = _okReply(fc, expectOk: true);
      ev[Capability.flowControl] = Evidence.acceptedOnly;
      if (caps[Capability.flowControl] == false) notes[Capability.flowControl] = 'ATFCSM not supported (common on clones)';
    } else {
      for (final c in [Capability.canFormatting, Capability.flowControl]) {
        caps[c] = null;
        ev[c] = Evidence.notTested;
        notes[c] = 'CAN-only feature; protocol is not CAN';
      }
    }

    // --- ISO-TP / multi-frame: VIN (0902) arrives as consecutive frames on CAN ---
    if (isCan && ecuConnected) {
      final vin = await step('0902');
      final multi = vin.ok && vin.lines.length > 1;
      for (final c in [Capability.isoTp, Capability.multiFrame]) {
        caps[c] = multi ? true : null;
        ev[c] = multi ? Evidence.behavioral : Evidence.notTested;
        if (!multi) notes[c] = vin.ok ? 'vehicle returned a single frame' : 'vehicle did not return VIN (0902)';
      }
    } else {
      for (final c in [Capability.isoTp, Capability.multiFrame]) {
        caps[c] = null;
        ev[c] = Evidence.notTested;
        notes[c] = isCan ? 'needs a connected vehicle to verify' : 'CAN-only feature; protocol is not CAN';
      }
    }

    caps[Capability.protocolSwitching] = null;
    ev[Capability.protocolSwitching] = Evidence.notTested;
    notes[Capability.protocolSwitching] = 'not tested — switching protocol would drop the vehicle link';

    return AdapterCapabilities(
      name: name,
      connection: connectionOf(transport),
      firmware: firmware,
      voltage: voltage,
      protocol: protocol,
      capabilities: caps,
      evidence: ev,
      notes: notes,
      probe: steps,
    );
  }
}

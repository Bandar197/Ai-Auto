import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../obd/obd.dart';

const String journalFormat = 'automind.journal.v1';

/// Durable, append-only log of a session in progress (one JSON object per line).
///
/// Lines are only ever appended and are flushed to disk in small batches, so if the
/// app is killed, the phone dies or the link drops mid-scan, everything written so far
/// survives. A journal that has no `end` line is an **interrupted** session and can
/// be turned back into a recording with [recover]. After a session is saved normally
/// the journal is closed with `end` and removed (the saved recording holds it all).
///
/// Line types: `start` (recording header), `frame` (TX/RX), `sample`, `event`,
/// `snapshot` (latest vehicle/DTC/module state), `end`.
class SessionJournal {
  SessionJournal._(this.file, this._raf);

  final File file;
  final RandomAccessFile _raf;
  final List<String> _pending = [];
  Future<void> _chain = Future.value();
  Timer? _timer;
  bool _closed = false;

  /// Journals currently being written by this process (never offered for recovery).
  static final Set<String> _openPaths = {};

  static Directory dirOf(Directory root) => Directory('${root.path}/journal');

  /// Opens a new journal and writes its `start` line immediately (flushed).
  /// [header] must hold recording_id, created_at, data_mode and source.
  static Future<SessionJournal> start(Directory root, Map<String, dynamic> header) async {
    final dir = dirOf(root);
    await dir.create(recursive: true);
    final id = header['recording_id'] as String;
    final f = File('${dir.path}/$id.jsonl');
    final raf = await f.open(mode: FileMode.append);
    final j = SessionJournal._(f, raf);
    _openPaths.add(f.path);
    j.write({'type': 'start', 'format': journalFormat, 'recording': header});
    await j.flush();
    return j;
  }

  /// Queues one entry; it reaches the disk within [_batchDelay] (or on [flush]).
  void write(Map<String, dynamic> entry) {
    if (_closed) return;
    try {
      _pending.add(jsonEncode(entry));
    } on Object catch (_) {
      return; // an unencodable value (e.g. NaN) must never break the scan
    }
    _timer ??= Timer(_batchDelay, () => unawaited(flush()));
  }

  static const Duration _batchDelay = Duration(milliseconds: 250);

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return _chain;
    final batch = '${_pending.join('\n')}\n';
    _pending.clear();
    return _chain = _chain.then((_) async {
      await _raf.writeString(batch);
      await _raf.flush();
    });
  }

  /// Session saved normally: write `end`, close and remove the journal.
  Future<void> complete() async {
    if (_closed) return;
    write({'type': 'end'});
    await flush();
    _closed = true;
    _openPaths.remove(file.path);
    await _raf.close();
    if (await file.exists()) await file.delete();
  }

  /// Stop writing but keep the file without `end` → it will be offered for recovery.
  Future<void> close() async {
    if (_closed) return;
    await flush();
    _closed = true;
    _openPaths.remove(file.path);
    await _raf.close();
  }

  /// Journals with no `end` line (interrupted sessions), oldest first.
  static Future<List<File>> interrupted(Directory root, {Set<String> exclude = const {}}) async {
    final dir = dirOf(root);
    if (!await dir.exists()) return const [];
    final out = <File>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.jsonl')) continue;
      if (exclude.contains(e.path) || _openPaths.contains(e.path)) continue;
      final text = await e.readAsString();
      if (!_hasEnd(text) && recover(text) != null) out.add(e);
    }
    out.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    return out;
  }

  static bool _hasEnd(String text) =>
      text.split('\n').reversed.where((l) => l.trim().isNotEmpty).take(1).any((l) => l.contains('"type":"end"'));

  /// Rebuilds a recording from journal text. Malformed lines (e.g. a line cut off by
  /// a crash) are skipped. Returns null when there is no valid `start` line. The result
  /// carries a `session_interrupted` event; data_mode is kept exactly as recorded.
  static Recording? recover(String text) {
    Map<String, dynamic>? header;
    Map<String, dynamic> snapshot = const {};
    final samples = <Map<String, dynamic>>[];
    final events = <Map<String, dynamic>>[];
    final frames = <Map<String, dynamic>>[];
    var ended = false;
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> e;
      try {
        e = (jsonDecode(line) as Map).cast<String, dynamic>();
      } on Object catch (_) {
        continue; // torn final line
      }
      switch (e['type']) {
        case 'start':
          if (e['format'] == journalFormat && e['recording'] is Map) header = (e['recording'] as Map).cast<String, dynamic>();
        case 'snapshot':
          if (e['r'] is Map) snapshot = (e['r'] as Map).cast<String, dynamic>();
        case 'sample':
          if (e['s'] is Map) samples.add((e['s'] as Map).cast<String, dynamic>());
        case 'event':
          if (e['e'] is Map) events.add((e['e'] as Map).cast<String, dynamic>());
        case 'frame':
          if (e['f'] is Map) frames.add((e['f'] as Map).cast<String, dynamic>());
        case 'end':
          ended = true;
      }
    }
    if (header == null || header['recording_id'] == null || header['data_mode'] == null) return null;

    int maxT(Iterable<Map<String, dynamic>> xs) =>
        xs.fold(0, (m, x) => ((x['t_ms'] as num?)?.toInt() ?? 0) > m ? (x['t_ms'] as num).toInt() : m);
    final lastT = [maxT(samples), maxT(events), maxT(frames)].reduce((a, b) => a > b ? a : b);

    // Signals: from the last snapshot, plus any key seen in later samples.
    final signals = <String, Map<String, dynamic>>{
      for (final s in (snapshot['signals'] as List? ?? const []))
        if (s is Map && s['key'] != null) s['key'] as String: s.cast<String, dynamic>(),
    };
    for (final s in samples) {
      for (final k in ((s['values'] as Map?) ?? const {}).keys) {
        signals.putIfAbsent(k as String, () => {'key': k, 'pid': s['pid'] ?? '', 'unit': null});
      }
    }

    final j = <String, dynamic>{
      ...snapshot,
      'format': recordingFormat,
      'recording_id': header['recording_id'],
      'created_at': header['created_at'],
      'data_mode': header['data_mode'],
      'source': header['source'] ?? const {},
      'duration_ms': lastT,
      'signals': signals.values.toList(),
      'samples': samples,
      'events': [
        ...events,
        if (!ended) {'t_ms': lastT, 'type': 'session_interrupted', 'detail': 'recovered from the on-device journal'},
      ],
      'tx_rx_frames': frames,
    };
    try {
      return Recording.fromJson(j);
    } on Object catch (_) {
      return null;
    }
  }
}

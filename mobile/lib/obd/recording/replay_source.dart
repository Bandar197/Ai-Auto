import 'dart:async';

import 'package:clock/clock.dart';

import '../decode/pid_table.dart';
import '../hex.dart';
import 'recording.dart';

/// Plays a [Recording] back with its original timing (speed 1x/2x/4x,
/// pause, seek). When a sample carries `raw` bytes they are decoded again
/// through the same [PidTable], so a replay goes through the same decoder as
/// live data. The data_mode of the original recording is preserved.
class ReplaySource {
  ReplaySource(this.recording, {this.table});

  final Recording recording;
  final PidTable? table;

  final StreamController<RecordingSample> _out = StreamController<RecordingSample>.broadcast();
  Stream<RecordingSample> get samples => _out.stream;

  double speed = 1;
  int _index = 0;
  int _positionMs = 0;
  bool _playing = false;
  Timer? _timer;
  final Stopwatch _clock = clock.stopwatch();
  int _clockBaseMs = 0;

  bool get isPlaying => _playing;
  bool get isFinished => _index >= recording.samples.length;
  int get positionMs => _playing ? _clockBaseMs + (_clock.elapsedMilliseconds * speed).round() : _positionMs;
  int get durationMs => recording.durationMs;

  /// The original data mode (`live` or `demo`) — shown as "REPLAY (live)".
  String get originalDataMode => recording.dataMode;

  /// Re-decodes a sample from its raw hex (falls back to stored values).
  RecordingSample decoded(RecordingSample s) {
    final t = table;
    final raw = s.raw;
    if (t == null || raw == null) return s;
    final bytes = parseHexBytes(raw);
    if (bytes == null) return s;
    final values = t.decodeResponse(bytes);
    if (values.isEmpty) return s;
    return RecordingSample(tMs: s.tMs, pid: s.pid, ecu: s.ecu, raw: s.raw, values: values);
  }

  /// All samples decoded, without timing (for analysis/tests).
  List<RecordingSample> decodeAll() => [for (final s in recording.samples) decoded(s)];

  void play({double? speed}) {
    if (speed != null) setSpeed(speed);
    if (_playing || isFinished) return;
    _playing = true;
    _clockBaseMs = _positionMs;
    _clock
      ..reset()
      ..start();
    _schedule();
  }

  void pause() {
    if (!_playing) return;
    _positionMs = positionMs;
    _playing = false;
    _clock.stop();
    _timer?.cancel();
  }

  void setSpeed(double s) {
    final wasPlaying = _playing;
    if (wasPlaying) pause();
    speed = s <= 0 ? 1 : s;
    if (wasPlaying) play();
  }

  void seek(int ms) {
    final wasPlaying = _playing;
    if (wasPlaying) pause();
    _positionMs = ms.clamp(0, durationMs);
    _index = recording.samples.indexWhere((s) => s.tMs >= _positionMs);
    if (_index < 0) _index = recording.samples.length;
    if (wasPlaying) play();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_playing) return;
    if (isFinished) {
      _playing = false;
      _positionMs = durationMs;
      return;
    }
    final next = recording.samples[_index];
    final waitMs = ((next.tMs - positionMs) / speed).round();
    _timer = Timer(Duration(milliseconds: waitMs < 0 ? 0 : waitMs), () {
      // Emit every sample that is due.
      while (!isFinished && recording.samples[_index].tMs <= positionMs + 1) {
        if (!_out.isClosed) _out.add(decoded(recording.samples[_index]));
        _index++;
      }
      _schedule();
    });
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _out.close();
  }
}

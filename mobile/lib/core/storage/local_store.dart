import 'dart:convert';
import 'dart:io';

import '../../obd/recording/recording.dart';
import 'scan_report.dart';

/// File-based storage in the app documents directory. Works fully offline
/// (the phone may be on the adapter's Wi-Fi without internet).
class LocalStore {
  LocalStore(this.root);

  final Directory root;

  /// User-chosen export folder ('' / null = `<app folder>/exports`). If it can't be
  /// written (removed drive, no permission) exports fall back to the app folder.
  String? exportDir;

  Directory get defaultExportDir => Directory('${root.path}/exports');

  Future<Directory> _exportTarget() async {
    final custom = exportDir;
    if (custom != null && custom.isNotEmpty) {
      try {
        final d = Directory(custom);
        await d.create(recursive: true);
        final probe = File('${d.path}/.automind_write_test');
        await probe.writeAsString('ok', flush: true);
        await probe.delete();
        return d;
      } on FileSystemException catch (_) {}
    }
    await defaultExportDir.create(recursive: true);
    return defaultExportDir;
  }

  Directory get _recordings => Directory('${root.path}/recordings');
  Directory get _reports => Directory('${root.path}/reports');
  File get _queue => File('${root.path}/upload_queue.json');
  File _json(String name) => File('${root.path}/$name.json');

  /// Temp file + rename: a crash mid-write never leaves a half-written file.
  static Future<File> _atomic(File f, String content) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    return tmp.rename(f.path);
  }

  Future<void> _ensure() async {
    await _recordings.create(recursive: true);
    await _reports.create(recursive: true);
  }

  // ------------------------------------------------------------ recordings
  Future<File> saveRecording(Recording r) async {
    await _ensure();
    return _atomic(File('${_recordings.path}/${r.recordingId}.json'), r.toJsonString());
  }

  Future<Recording?> loadRecording(String id) async {
    final f = File('${_recordings.path}/$id.json');
    if (!await f.exists()) return null;
    return Recording.fromJsonString(await f.readAsString());
  }

  File recordingFile(String id) => File('${_recordings.path}/$id.json');

  Future<List<Recording>> listRecordings() async {
    await _ensure();
    final out = <Recording>[];
    await for (final e in _recordings.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          out.add(Recording.fromJsonString(await e.readAsString()));
        } on Object catch (_) {}
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  // --------------------------------------------------------------- reports
  Future<void> saveReport(ScanReport r) async {
    await _ensure();
    await _atomic(File('${_reports.path}/${r.id}.json'), jsonEncode(r.toJson()));
  }

  Future<ScanReport?> loadReport(String id) async {
    final f = File('${_reports.path}/$id.json');
    if (!await f.exists()) return null;
    return ScanReport.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  /// Delete a saved scan: its report, its recording file, and any queue entry.
  Future<void> deleteReport(String id) async {
    final report = await loadReport(id);
    final f = File('${_reports.path}/$id.json');
    if (await f.exists()) await f.delete();
    final recId = report?.recordingId;
    if (recId != null) {
      final rf = recordingFile(recId);
      if (await rf.exists()) await rf.delete();
    }
    final queue = await readQueue();
    if (queue.contains(id)) await writeQueue(queue.where((x) => x != id).toList());
  }

  Future<List<ScanReport>> listReports() async {
    await _ensure();
    final out = <ScanReport>[];
    await for (final e in _reports.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          out.add(ScanReport.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>));
        } on Object catch (_) {}
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  // ----------------------------------------------------------------- queue
  Future<List<String>> readQueue() async {
    if (!await _queue.exists()) return [];
    try {
      return [for (final x in jsonDecode(await _queue.readAsString()) as List) x as String];
    } on Object catch (_) {
      return [];
    }
  }

  Future<void> writeQueue(List<String> ids) async {
    await root.create(recursive: true);
    await _queue.writeAsString(jsonEncode(ids));
  }

  // ------------------------------------------------------- misc json blobs
  Future<dynamic> readJson(String name) async {
    final f = _json(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } on Object catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String name, Object? value) async {
    await root.create(recursive: true);
    await _json(name).writeAsString(jsonEncode(value));
  }

  /// Write a binary export (e.g. an evidence ZIP) atomically: temp file, then rename,
  /// so a crash mid-write never leaves a half-written bundle under the final name.
  Future<File> writeExportBytes(String fileName, List<int> bytes) async {
    final dir = await _exportTarget();
    final tmp = File('${dir.path}/$fileName.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    return tmp.rename('${dir.path}/$fileName');
  }

  Future<File> writeExport(String fileName, String content) async {
    final dir = await _exportTarget();
    return _atomic(File('${dir.path}/$fileName'), content);
  }
}

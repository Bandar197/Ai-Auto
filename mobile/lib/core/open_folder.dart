import 'dart:io';

/// Opens [path] in the desktop file manager. Returns false where that isn't possible
/// (phones) or the command fails.
Future<bool> openFolder(String path) async {
  try {
    final ProcessResult r;
    if (Platform.isWindows) {
      r = await Process.run('explorer', [path]);
      return true; // explorer returns 1 even on success
    } else if (Platform.isMacOS) {
      r = await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      r = await Process.run('xdg-open', [path]);
    } else {
      return false;
    }
    return r.exitCode == 0;
  } on Object catch (_) {
    return false;
  }
}

bool get canOpenFolders => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

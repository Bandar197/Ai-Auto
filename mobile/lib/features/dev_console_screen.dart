import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/dev_console_policy.dart';
import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Developer diagnostics: the live TX/RX stream of the adapter link and a command box
/// limited to read-only commands ([consoleAllowed]).
class DevConsoleScreen extends ConsumerStatefulWidget {
  const DevConsoleScreen({super.key});
  @override
  ConsumerState<DevConsoleScreen> createState() => _DevConsoleScreenState();
}

class _DevConsoleScreenState extends ConsumerState<DevConsoleScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  TrafficTap? _tap;
  ObdClient? _bound;
  final List<TxRxFrame> _view = [];
  String? _message;

  void _bind(ObdClient? c) {
    if (identical(c, _bound)) return;
    _tap?.detach();
    _bound = c;
    if (c == null) return;
    _tap = TrafficTap(startedAt: DateTime.now().toUtc(), onFrame: (f) {
      if (!mounted) return;
      setState(() {
        _view.add(f);
        if (_view.length > 1000) _view.removeRange(0, _view.length - 1000);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    })
      ..attach(c.elm.log);
  }

  @override
  void dispose() {
    _tap?.detach();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = context.l10n;
    final cmd = consoleAllowed(_input.text);
    if (cmd == null) {
      setState(() => _message = l.devConsoleBlocked);
      return;
    }
    setState(() => _message = null);
    try {
      await _bound?.elm.send(cmd);
    } on PolicyViolationException catch (_) {
      setState(() => _message = l.devConsoleBlocked);
    }
  }

  Future<void> _export() async {
    final b = StringBuffer();
    for (final f in _view) {
      final data = f.data.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
      b.writeln('${f.tMs}\t${f.dir.toUpperCase()}\t$data${f.durationMs != null ? '\t${f.durationMs}ms' : ''}${f.timeout == true ? '\tTIMEOUT' : ''}');
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = await ref.read(localStoreProvider).writeExport('automind_console_$stamp.log', b.toString());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/plain')], subject: 'AutoMind console log'));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final conn = ref.watch(connectionProvider);
    _bind(conn.client);
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: AppBar(title: Text(l.devConsoleTitle), actions: [
        IconButton(tooltip: l.devConsoleClear, icon: const Icon(Icons.clear_all), onPressed: () => setState(_view.clear)),
        IconButton(tooltip: l.devConsoleExport, icon: const Icon(Icons.ios_share), onPressed: _view.isEmpty ? null : _export),
      ]),
      body: Column(children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        Padding(padding: const EdgeInsets.all(12), child: Text(l.devConsoleIntro, style: Theme.of(context).textTheme.bodySmall)),
        if (conn.client == null) Padding(padding: const EdgeInsets.all(12), child: Text(l.devConsoleNotConnected)),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
              child: ListView.builder(
                key: const Key('console-list'),
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: _view.length,
                itemBuilder: (_, i) {
                  final f = _view[i];
                  final tx = f.dir == 'tx';
                  return Text(
                    '${f.tMs.toString().padLeft(7)}  ${tx ? '>' : '<'} ${f.data.replaceAll('\r', ' | ')}'
                    '${f.durationMs != null ? '  (${f.durationMs} ms)' : ''}${f.timeout == true ? '  TIMEOUT' : ''}',
                    style: mono?.copyWith(color: tx ? Colors.lightBlueAccent : (f.timeout == true ? Colors.orangeAccent : Colors.greenAccent)),
                  );
                },
              ),
            ),
          ),
        ),
        if (_message != null) Padding(padding: const EdgeInsets.all(8), child: Text(_message!, style: const TextStyle(color: Colors.red))),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: const Key('console-input'),
                controller: _input,
                enabled: conn.client != null,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(hintText: l.devConsoleHint),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(key: const Key('console-send'), onPressed: conn.client == null ? null : _send, child: Text(l.devConsoleSend)),
          ]),
        ),
      ]),
    );
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/api/api_client.dart';
import '../core/recording/session_import.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final reports = ref.watch(reportsProvider);
    final user = ref.watch(authProvider).value;
    final interrupted = ref.watch(interruptedSessionsProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(l.historyTitle), actions: [
        IconButton(
          key: const Key('compare-sessions'),
          tooltip: l.compareTitle,
          icon: const Icon(Icons.compare_arrows),
          onPressed: () => context.push('/compare'),
        ),
        IconButton(
          key: const Key('import-session'),
          tooltip: l.importSession,
          icon: const Icon(Icons.file_open_outlined),
          onPressed: () => _import(context, ref),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pendingUploadsProvider.notifier).sync();
          await ref.read(reportsProvider.notifier).refresh();
        },
        child: reports.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(l.errorGeneric('$e'))),
          data: (list) => ListView(children: [
            if (interrupted > 0)
              Card(
                key: const Key('interrupted-banner'),
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                color: Colors.orange.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.restore_page_outlined, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.interruptedBanner(interrupted))),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('recover-sessions'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final n = await ref.read(reportsProvider.notifier).recoverInterrupted();
                        messenger.showSnackBar(SnackBar(content: Text(l.recoveredDone(n))));
                      },
                      child: Text(l.recoverCta),
                    ),
                  ]),
                ),
              ),
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l.noSessions))),
            for (final r in list)
              Dismissible(
                key: ValueKey(r.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: AlignmentDirectional.centerEnd,
                  color: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (_) async => await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(l.deleteScanTitle),
                        content: Text(l.deleteScanBody),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.delete)),
                        ],
                      ),
                    ) ??
                    false,
                onDismissed: (_) async {
                  await ref.read(reportsProvider.notifier).delete(r.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.deleteScanDone)));
                  }
                },
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: healthColor(r.healthScore).withValues(alpha: 0.2),
                    child: Text(r.healthScore?.toString() ?? '—'),
                  ),
                  title: Row(children: [
                    Flexible(child: Text(DateFormat.yMMMd(context.lang).add_Hm().format(r.createdAt.toLocal()))),
                    const SizedBox(width: 6),
                    if (r.imported) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(4)),
                        child: Text(l.importedTag, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (r.interrupted) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(4)),
                        child: Text(l.interruptedTag, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (r.dataMode != 'live')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: r.isReplay ? replayColor : demoColor, borderRadius: BorderRadius.circular(4)),
                        child: Text(modeText(l, r.dataMode).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                  ]),
                  subtitle: Text('${l.dtcCount(r.dtcs.map((d) => d['code']).toSet().length)} · ${r.uploadState == 'uploaded' ? l.synced : l.localOnly}'),
                  trailing: Icon(r.uploadState == 'uploaded' ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                  onTap: () => context.push('/report/${r.id}'),
                ),
              ),
            if (user != null) _ServerSessions(localIds: {for (final r in list) ?r.serverSessionId}),
          ]),
        ),
      ),
    );
  }
}

/// Pick a recording JSON (v1/v2) or an evidence ZIP and add it to History.
Future<void> _import(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json', 'zip']);
  if (files.isEmpty) return;
  String msg;
  try {
    final s = importSessionBytes(await files.first.readAsBytes(), fileName: files.first.name);
    final report = await ref.read(reportsProvider.notifier).importSession(s);
    msg = report == null ? l.importDuplicate : l.importDone;
  } on ImportException catch (e) {
    msg = e.error == ImportError.tampered ? l.importTampered(e.detail ?? '') : l.importInvalid;
  }
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}

class _ServerSessions extends ConsumerWidget {
  const _ServerSessions({required this.localIds});
  final Set<String> localIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ref.read(apiProvider).sessions(),
      builder: (context, snap) {
        if (snap.hasError) {
          return ListTile(leading: const Icon(Icons.cloud_off), title: Text(ApiException.from(snap.error!).message));
        }
        final remote = (snap.data ?? const []).where((s) => !localIds.contains(s['id'])).toList();
        if (remote.isEmpty) return const SizedBox.shrink();
        return Column(children: [
          const Divider(),
          for (final s in remote)
            ListTile(
              leading: CircleAvatar(child: Text('${s['health_score'] ?? '—'}')),
              title: Text('${s['started_at'] ?? ''}'),
              subtitle: Text('${modeText(l, '${s['data_mode']}')} · ${l.dtcCount((s['dtc_count'] as num? ?? 0).toInt())} · ${l.synced}'),
            ),
        ]);
      },
    );
  }
}

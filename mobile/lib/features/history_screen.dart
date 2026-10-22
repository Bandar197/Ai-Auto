import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/api/api_client.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(l.historyTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pendingUploadsProvider.notifier).sync();
          await ref.read(reportsProvider.notifier).refresh();
        },
        child: reports.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(l.errorGeneric('$e'))),
          data: (list) => ListView(children: [
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l.noSessions))),
            for (final r in list)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: healthColor(r.healthScore).withValues(alpha: 0.2),
                  child: Text(r.healthScore?.toString() ?? '—'),
                ),
                title: Row(children: [
                  Flexible(child: Text(DateFormat.yMMMd(context.lang).add_Hm().format(r.createdAt.toLocal()))),
                  const SizedBox(width: 6),
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
            if (user != null) _ServerSessions(localIds: {for (final r in list) ?r.serverSessionId}),
          ]),
        ),
      ),
    );
  }
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

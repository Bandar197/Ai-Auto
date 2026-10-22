import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _editText(BuildContext context, WidgetRef ref, String title, String value, AppSettings Function(AppSettings, String) apply,
      {bool number = false}) async {
    final c = TextEditingController(text: value);
    final l = context.l10n;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          keyboardType: number ? TextInputType.number : TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(l.save)),
        ],
      ),
    );
    if (v == null) return;
    if (number && int.tryParse(v) == null) return;
    await ref.read(settingsProvider.notifier).change((s) => apply(s, v));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final user = ref.watch(authProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(children: [
        ListTile(title: Text(l.account, style: Theme.of(context).textTheme.titleMedium)),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(user == null ? l.notLoggedIn : '${user['email'] ?? ''}'),
          trailing: user == null
              ? TextButton(onPressed: () => context.push('/login'), child: Text(l.login))
              : TextButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: Text(l.logout)),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l.language),
          trailing: SegmentedButton<String>(
            segments: [ButtonSegment(value: 'ar', label: Text(l.arabic)), ButtonSegment(value: 'en', label: Text(l.english))],
            selected: {s.locale},
            onSelectionChanged: (v) => ref.read(settingsProvider.notifier).change((x) => x.copyWith(locale: v.first)),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(l.backendUrl),
          subtitle: Text(s.backendUrl, textDirection: TextDirection.ltr),
          onTap: () => _editText(context, ref, l.backendUrl, s.backendUrl, (x, v) => x.copyWith(backendUrl: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.badge_outlined),
          title: Text(l.includeVin),
          value: s.includeVin,
          onChanged: (v) => ref.read(settingsProvider.notifier).change((x) => x.copyWith(includeVin: v)),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(l.captureDuration),
          subtitle: Text('${s.captureSeconds}'),
          onTap: () => _editText(context, ref, l.captureDuration, '${s.captureSeconds}',
              (x, v) => x.copyWith(captureSeconds: int.parse(v).clamp(10, 300)), number: true),
        ),
        const Divider(),
        ListTile(title: Text(l.adapterSettings, style: Theme.of(context).textTheme.titleMedium)),
        ListTile(
          leading: const Icon(Icons.wifi),
          title: Text('${l.wifiHost} / ${l.wifiPort}'),
          subtitle: Text('${s.wifiHost}:${s.wifiPort}', textDirection: TextDirection.ltr),
          onTap: () => _editText(context, ref, l.wifiHost, '${s.wifiHost}:${s.wifiPort}', (x, v) {
            final parts = v.split(':');
            return x.copyWith(wifiHost: parts.first, wifiPort: parts.length > 1 ? int.tryParse(parts[1]) ?? x.wifiPort : x.wifiPort);
          }),
        ),
        ListTile(
          leading: const Icon(Icons.hourglass_bottom),
          title: Text(l.commandTimeout),
          subtitle: Text('${s.commandTimeoutMs}'),
          onTap: () => _editText(context, ref, l.commandTimeout, '${s.commandTimeoutMs}',
              (x, v) => x.copyWith(commandTimeoutMs: int.parse(v).clamp(500, 10000)), number: true),
        ),
        ListTile(
          leading: const Icon(Icons.manage_search),
          title: Text(l.searchTimeout),
          subtitle: Text('${s.searchTimeoutMs}'),
          onTap: () => _editText(context, ref, l.searchTimeout, '${s.searchTimeoutMs}',
              (x, v) => x.copyWith(searchTimeoutMs: int.parse(v).clamp(2000, 30000)), number: true),
        ),
        ListTile(
          leading: const Icon(Icons.bluetooth),
          title: Text(l.bleUuidOverride),
          subtitle: Text(s.bleService.isEmpty ? l.protocolAuto : '${s.bleService} / ${s.bleNotify} / ${s.bleWrite}', textDirection: TextDirection.ltr),
          onTap: () => _editText(context, ref, l.bleUuidOverride, s.bleService.isEmpty ? '' : '${s.bleService},${s.bleNotify},${s.bleWrite}', (x, v) {
            final p = v.split(RegExp(r'[,/ ]+')).where((e) => e.isNotEmpty).toList();
            if (p.length != 3) return x.copyWith(bleService: '', bleNotify: '', bleWrite: '');
            return x.copyWith(bleService: p[0], bleNotify: p[1], bleWrite: p[2]);
          }),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('${l.appTitle} $appVersion'),
          subtitle: Text('PID table ${ref.watch(appAssetsProvider).table.version} · KB ${ref.watch(appAssetsProvider).kb.version ?? '—'}'),
        ),
      ]),
    );
  }
}

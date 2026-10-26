import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class MaintenanceScreen extends ConsumerWidget {
  const MaintenanceScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final records = ref.watch(maintenanceProvider(vehicleId));
    return Scaffold(
      appBar: AppBar(title: Text(l.maintenanceTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.addRecord),
        onPressed: () => _add(context, ref),
      ),
      body: records.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorGeneric('$e'))),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.noMaintenance))
            : ListView(children: [
                for (final r in list)
                  ListTile(
                    leading: const Icon(Icons.build_circle_outlined),
                    title: Text('${r['service_type'] ?? r['title'] ?? ''}'),
                    subtitle: Text([
                      '${r['performed_at'] ?? r['date'] ?? ''}'.split('T').first,
                      if (r['odometer_km'] != null) '${r['odometer_km']} km',
                      if (r['cost_sar'] != null) '${r['cost_sar']} SAR',
                      if ((r['notes'] ?? '').toString().isNotEmpty) '${r['notes']}',
                    ].join(' · ')),
                  ),
              ]),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final type = TextEditingController();
    final odo = TextEditingController();
    final cost = TextEditingController();
    final notes = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l.addRecord),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: type, decoration: InputDecoration(labelText: l.serviceType)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.date),
                subtitle: Text('${date.toLocal()}'.split(' ').first),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
                  if (d != null) setS(() => date = d);
                },
              ),
              TextField(controller: odo, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.odometer)),
              TextField(controller: cost, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.cost)),
              TextField(controller: notes, decoration: InputDecoration(labelText: l.notes)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
          ],
        ),
      ),
    );
    if (ok != true || type.text.trim().isEmpty) return;
    try {
      await addMaintenanceRecord(ref, vehicleId, {
        'service_type': type.text.trim(),
        'performed_at': date.toUtc().toIso8601String(),
        'odometer_km': ?int.tryParse(odo.text.trim()),
        'cost_sar': ?double.tryParse(cost.text.trim()),
        if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
      });
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}

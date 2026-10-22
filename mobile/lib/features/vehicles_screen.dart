import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class VehiclesScreen extends ConsumerWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final vehicles = ref.watch(vehiclesProvider);
    final selected = ref.watch(selectedVehicleProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.vehiclesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.addVehicle),
        onPressed: () => context.push('/vehicles/edit'),
      ),
      body: vehicles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorGeneric('$e'))),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.vehicleNone))
            : ListView(children: [
                for (final v in list)
                  ListTile(
                    leading: Icon(v['id'] == selected?['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    title: Text('${v['nickname'] ?? ''} ${v['make'] ?? ''} ${v['model'] ?? ''} ${v['model_year'] ?? ''}'.trim()),
                    subtitle: Text('${v['vin_masked'] ?? v['vin'] ?? ''} ${v['plate'] ?? ''}', textDirection: TextDirection.ltr),
                    onTap: () => ref.read(settingsProvider.notifier).change((s) => s.copyWith(selectedVehicleId: v['id'] as String)),
                    trailing: PopupMenuButton<String>(
                      onSelected: (a) async {
                        if (a == 'edit') context.push('/vehicles/edit', extra: v);
                        if (a == 'maint') context.push('/maintenance/${v['id']}');
                        if (a == 'delete') {
                          try {
                            await ref.read(vehiclesProvider.notifier).remove(v['id'] as String);
                          } on ApiException catch (e) {
                            if (context.mounted) showSnack(context, e.message);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(l.edit)),
                        PopupMenuItem(value: 'maint', child: Text(l.maintenanceTitle)),
                        PopupMenuItem(value: 'delete', child: Text(l.delete)),
                      ],
                    ),
                  ),
              ]),
      ),
    );
  }
}

class VehicleEditScreen extends ConsumerStatefulWidget {
  const VehicleEditScreen({super.key, this.vehicle});
  final Map<String, dynamic>? vehicle;
  @override
  ConsumerState<VehicleEditScreen> createState() => _VehicleEditScreenState();
}

class _VehicleEditScreenState extends ConsumerState<VehicleEditScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  bool _busy = false;

  static const _fields = ['nickname', 'make', 'model', 'model_year', 'vin', 'plate', 'engine', 'fuel_type', 'transmission', 'odometer_km'];

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle ?? const {};
    _c = {for (final f in _fields) f: TextEditingController(text: v[f]?.toString() ?? '')};
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = <String, dynamic>{};
    for (final f in _fields) {
      final t = _c[f]!.text.trim();
      if (t.isEmpty) continue;
      body[f] = (f == 'model_year' || f == 'odometer_km') ? int.tryParse(t) : (f == 'vin' ? t.toUpperCase() : t);
    }
    try {
      await ref.read(vehiclesProvider.notifier).save(body, id: widget.vehicle?['id'] as String?);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = {
      'nickname': l.nickname,
      'make': l.make,
      'model': l.model,
      'model_year': l.year,
      'vin': l.vinLabel,
      'plate': l.plate,
      'engine': l.engineLabel,
      'fuel_type': l.fuelTypeLabel,
      'transmission': l.transmission,
      'odometer_km': l.odometer,
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.vehicle == null ? l.addVehicle : l.edit)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final f in _fields)
            TextFormField(
              controller: _c[f],
              decoration: InputDecoration(labelText: labels[f]),
              keyboardType: (f == 'model_year' || f == 'odometer_km') ? TextInputType.number : TextInputType.text,
              textDirection: f == 'vin' || f == 'plate' ? TextDirection.ltr : null,
              validator: (v) {
                if (f == 'vin' && v != null && v.trim().isNotEmpty && !RegExp(r'^[A-HJ-NPR-Z0-9]{17}$', caseSensitive: false).hasMatch(v.trim())) {
                  return 'VIN: 17';
                }
                if (f == 'model_year' && v != null && v.isNotEmpty) {
                  final y = int.tryParse(v);
                  if (y == null || y < 1980 || y > DateTime.now().year + 1) return l.year;
                }
                return null;
              },
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/vehicle_catalog.dart';
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
  static const _textFields = ['nickname', 'vin', 'plate', 'engine', 'odometer_km'];
  late final Map<String, TextEditingController> _c;
  final _makeOther = TextEditingController();
  final _modelOther = TextEditingController();
  bool _busy = false;

  String? _make; // null or a key of kMakes; '__other__' means free text
  String? _model; // null, a model, or '__other__'
  int? _year;
  String? _fuel; // key of kFuelTypes
  String? _transmission;

  static const _other = '__other__';

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle ?? const {};
    _c = {for (final f in _textFields) f: TextEditingController(text: v[f]?.toString() ?? '')};
    final make = v['make']?.toString();
    if (make != null && make.isNotEmpty) {
      if (kMakes.containsKey(make)) {
        _make = make;
      } else {
        _make = _other;
        _makeOther.text = make;
      }
    }
    final model = v['model']?.toString();
    if (model != null && model.isNotEmpty) {
      if (modelsFor(_resolvedMake).contains(model)) {
        _model = model;
      } else {
        _model = _other;
        _modelOther.text = model;
      }
    }
    _year = int.tryParse('${v['model_year'] ?? ''}');
    final fuel = v['fuel_type']?.toString();
    if (fuel != null && kFuelTypes.containsKey(fuel)) _fuel = fuel;
    final tr = v['transmission']?.toString();
    if (tr != null && kTransmissions.containsKey(tr)) _transmission = tr;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _makeOther.dispose();
    _modelOther.dispose();
    super.dispose();
  }

  String? get _resolvedMake => _make == _other ? _makeOther.text.trim() : _make;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = <String, dynamic>{};
    for (final f in _textFields) {
      final t = _c[f]!.text.trim();
      if (t.isEmpty) continue;
      body[f] = f == 'odometer_km' ? int.tryParse(t) : (f == 'vin' ? t.toUpperCase() : t);
    }
    final make = _resolvedMake;
    if (make != null && make.isNotEmpty) body['make'] = make;
    final models = modelsFor(make);
    final model = (models.isEmpty || _model == _other) ? _modelOther.text.trim() : _model;
    if (model != null && model.isNotEmpty) body['model'] = model;
    if (_year != null) body['model_year'] = _year;
    if (_fuel != null) body['fuel_type'] = _fuel;
    if (_transmission != null) body['transmission'] = _transmission;
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
    final lang = context.lang;
    final models = modelsFor(_resolvedMake);
    final thisYear = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(title: Text(widget.vehicle == null ? l.addVehicle : l.edit)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _text('nickname', l.nickname),
          // Make: dropdown + "Other" free text.
          DropdownButtonFormField<String>(
            initialValue: _make,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.make),
            items: [
              for (final e in kMakes.entries)
                DropdownMenuItem(value: e.key, child: Text(lang == 'ar' ? '${e.value} — ${e.key}' : e.key)),
              DropdownMenuItem(value: _other, child: Text(l.otherOption)),
            ],
            onChanged: (v) => setState(() {
              _make = v;
              _model = null; // models depend on make
            }),
          ),
          if (_make == _other)
            TextFormField(controller: _makeOther, decoration: InputDecoration(labelText: l.make), onChanged: (_) => setState(() {})),
          // Model: dropdown when the make has a model list, else free text.
          if (models.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: models.contains(_model) ? _model : (_model == _other ? _other : null),
              isExpanded: true,
              decoration: InputDecoration(labelText: l.model),
              items: [
                for (final m in models) DropdownMenuItem(value: m, child: Text(m)),
                DropdownMenuItem(value: _other, child: Text(l.otherOption)),
              ],
              onChanged: (v) => setState(() => _model = v),
            ),
          if (models.isEmpty || _model == _other)
            TextFormField(controller: _modelOther, decoration: InputDecoration(labelText: l.model)),
          // Year: dropdown.
          DropdownButtonFormField<int>(
            initialValue: _year,
            decoration: InputDecoration(labelText: l.year),
            items: [for (var y = thisYear + 1; y >= 1980; y--) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (v) => setState(() => _year = v),
          ),
          _enumDropdown(l.fuelTypeLabel, kFuelTypes, _fuel, lang, (v) => setState(() => _fuel = v)),
          _enumDropdown(l.transmission, kTransmissions, _transmission, lang, (v) => setState(() => _transmission = v)),
          _text('engine', l.engineLabel),
          _text('vin', l.vinLabel, ltr: true, validator: (v) {
            if (v != null && v.trim().isNotEmpty && !RegExp(r'^[A-HJ-NPR-Z0-9]{17}$', caseSensitive: false).hasMatch(v.trim())) {
              return 'VIN: 17';
            }
            return null;
          }),
          _text('plate', l.plate, ltr: true),
          _text('odometer_km', l.odometer, number: true),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
        ]),
      ),
    );
  }

  Widget _text(String f, String label, {bool ltr = false, bool number = false, String? Function(String?)? validator}) =>
      TextFormField(
        controller: _c[f]!,
        decoration: InputDecoration(labelText: label),
        keyboardType: number ? TextInputType.number : TextInputType.text,
        textDirection: ltr ? TextDirection.ltr : null,
        validator: validator,
      );

  Widget _enumDropdown(String label, Map<String, (String, String)> values, String? current, String lang, ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [for (final e in values.entries) DropdownMenuItem(value: e.key, child: Text(lang == 'ar' ? e.value.$2 : e.value.$1))],
        onChanged: onChanged,
      );
}

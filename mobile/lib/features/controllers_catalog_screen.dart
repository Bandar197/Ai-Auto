import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/controller_catalog.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';

/// Browsable catalogue of controller identifiers per manufacturer. Every entry is an
/// UNVERIFIED static identifier (a module-group name), not a readable ECU — the screen
/// says so clearly. Search + filter by make.
class ControllersCatalogScreen extends ConsumerStatefulWidget {
  const ControllersCatalogScreen({super.key});

  @override
  ConsumerState<ControllersCatalogScreen> createState() => _ControllersCatalogScreenState();
}

class _ControllersCatalogScreenState extends ConsumerState<ControllersCatalogScreen> {
  String? _make;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cat = ref.watch(appAssetsProvider).controllers;
    final makes = cat.makes;
    final rows = cat.filter(make: _make, query: _query);

    return Scaffold(
      appBar: AppBar(title: Text(l.controllersCatalogTitle)),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(l.controllersCatalogNote, style: Theme.of(context).textTheme.bodySmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: l.search, isDense: true),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String?>(
              value: _make,
              hint: Text(l.allMakes),
              items: [
                DropdownMenuItem(value: null, child: Text(l.allMakes)),
                for (final m in makes) DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => _make = v),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('${rows.length}', style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => _row(context, rows[i]),
          ),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, ControllerEntry e) {
    final l = context.l10n;
    return ListTile(
      dense: true,
      title: Text(e.label),
      subtitle: Text('${e.make} · ${e.category}', textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.bodySmall),
      trailing: Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.grey.withValues(alpha: 0.15),
        label: Text(l.unverifiedCatalogEntry, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}

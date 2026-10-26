import 'package:flutter/material.dart';

import '../core/knowledge.dart';
import '../ui/l10n_helpers.dart';

/// In-app guide: warning lights, what each system means, and maintenance tips.
/// Content is curated and bilingual (see core/knowledge.dart) — general and honest,
/// never promising a fix or advising to disable a safety system.
class KnowledgeScreen extends StatelessWidget {
  const KnowledgeScreen({super.key});

  static const _icons = <String, IconData>{
    'engine': Icons.directions_car_outlined,
    'airbag': Icons.airline_seat_recline_normal_outlined,
    'abs': Icons.disc_full_outlined,
    'oil': Icons.oil_barrel_outlined,
    'battery': Icons.battery_charging_full_outlined,
    'temp': Icons.thermostat_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    return Scaffold(
      appBar: AppBar(title: Text(l.knowledgeTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24, top: 4),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l.knowledgeSubtitle, style: Theme.of(context).textTheme.bodyMedium),
          ),
          for (final section in kKnowledge) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(section.title(lang),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Card(
              child: Column(
                children: [
                  for (final item in section.items)
                    ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: Icon(_icons[item.icon] ?? Icons.lightbulb_outline,
                          color: Theme.of(context).colorScheme.primary),
                      title: Text(item.title(lang), style: const TextStyle(fontWeight: FontWeight.w600)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(item.body(lang), style: Theme.of(context).textTheme.bodyMedium)],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

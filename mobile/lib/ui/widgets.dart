import 'package:flutter/material.dart';

import '../obd/obd.dart';
import 'l10n_helpers.dart';

const Color demoColor = Color(0xFFE65100);
const Color replayColor = Color(0xFF6A1B9A);

/// Prominent DEMO / REPLAY banner. Live data shows no banner.
class ModeBanner extends StatelessWidget {
  const ModeBanner({super.key, required this.mode, this.originalMode, this.simulator = false});

  final String mode;
  final String? originalMode;
  final bool simulator;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (mode == 'live') return const SizedBox.shrink();
    final isReplay = mode == 'replay';
    final text = isReplay
        ? l.replayBanner(modeText(l, originalMode ?? 'live'))
        : '${l.demoBanner}${simulator ? ' · ${l.simulatorLabel}' : ''}';
    return Semantics(
      label: text,
      child: Container(
        key: Key(isReplay ? 'replay-banner' : 'demo-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isReplay ? replayColor : demoColor,
        child: Row(children: [
          Icon(isReplay ? Icons.replay : Icons.science_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

/// Diagonal watermark over demo/replay reports.
class Watermark extends StatelessWidget {
  const Watermark({super.key, required this.text, required this.child});
  final String? text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (text == null) return child;
    return Stack(children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Transform.rotate(
              angle: -0.5,
              child: Text(
                text!,
                key: const Key('watermark'),
                style: TextStyle(fontSize: 96, fontWeight: FontWeight.w900, color: demoColor.withValues(alpha: 0.10)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

Color adapterColor(AdapterState s) => switch (s) {
      AdapterState.connected => Colors.green,
      AdapterState.connecting => Colors.amber,
      AdapterState.error => Colors.red,
      AdapterState.disconnected => Colors.grey,
    };

Color ecuColor(EcuState s) => switch (s) {
      EcuState.connected => Colors.green,
      EcuState.searching => Colors.amber,
      EcuState.noResponse || EcuState.busError => Colors.red,
      EcuState.unknown => Colors.grey,
    };

class StatusChips extends StatelessWidget {
  const StatusChips({super.key, required this.status, this.simulator = false});
  final LinkStatus status;
  final bool simulator;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(spacing: 8, runSpacing: 4, children: [
      Chip(
        avatar: Icon(Icons.settings_input_antenna, color: adapterColor(status.adapter), size: 18),
        label: Text('${l.adapterLabel}: ${adapterStateText(l, status.adapter)}${simulator ? ' (${l.simulatorLabel})' : ''}'),
      ),
      Chip(
        avatar: Icon(Icons.directions_car, color: ecuColor(status.ecu), size: 18),
        label: Text('${l.ecuLabel}: ${ecuStateText(l, status.ecu)}'),
      ),
    ]);
  }
}

Color healthColor(int? score) {
  if (score == null) return Colors.grey;
  if (score >= 85) return Colors.green;
  if (score >= 70) return Colors.lightGreen;
  if (score >= 50) return Colors.orange;
  return Colors.red;
}

class HealthGauge extends StatelessWidget {
  const HealthGauge({super.key, required this.score, this.size = 96});
  final int? score;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: score == null ? 0 : score! / 100,
            strokeWidth: 9,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            color: healthColor(score),
          ),
        ),
        Text(score?.toString() ?? '—', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.icon, this.trailing});
  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            ?trailing,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }
}

Color severityColor(String? s) => switch (s) {
      'critical' => Colors.red.shade800,
      'high' => Colors.red,
      'medium' => Colors.orange,
      'low' => Colors.amber.shade700,
      _ => Colors.blueGrey,
    };

void showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

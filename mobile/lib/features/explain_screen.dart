import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api/api_client.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Explains one fault code: an AI explanation (grounded in the knowledge base),
/// likely causes, what to check, safety note, and Google/YouTube search + videos.
/// Falls back to the offline KB + client-built search links if the server call fails.
class ExplainScreen extends ConsumerStatefulWidget {
  const ExplainScreen({super.key, required this.code, this.make, this.model, this.year});

  final String code;
  final String? make;
  final String? model;
  final int? year;

  @override
  ConsumerState<ExplainScreen> createState() => _ExplainScreenState();
}

class _ExplainScreenState extends ConsumerState<ExplainScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _fromServer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final lang = context.lang;
    setState(() => _loading = true);
    try {
      final r = await ref
          .read(apiProvider)
          .explainDtc(widget.code, make: widget.make, model: widget.model, year: widget.year, lang: lang);
      if (!mounted) return;
      setState(() {
        _data = r;
        _fromServer = true;
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _data = _offline(lang);
        _fromServer = false;
        _loading = false;
      });
    }
  }

  /// Offline fallback built from the bundled KB + client-side search links.
  Map<String, dynamic> _offline(String lang) {
    final assets = ref.read(appAssetsProvider);
    final kb = assets.kb.lookupFor(widget.code, make: effectiveMake(ref.read(selectedVehicleProvider), null, assets));
    final title = kb?.description(lang) ?? widget.code;
    return {
      'code': widget.code,
      'title_ar': kb?.descriptionAr ?? widget.code,
      'title_en': kb?.descriptionEn ?? widget.code,
      'explanation': title,
      'causes': kb?.causes(lang) ?? const [],
      'checks': const [],
      'safety': (kb?.drivable == false) ? (lang == 'ar' ? 'يُنصح بعدم القيادة حتى الفحص.' : 'Avoid driving until checked.') : null,
      'drivable': kb?.drivable,
      'source': 'kb',
      'model': null,
      'search': {'google': _google(lang), 'youtube': _youtube(lang)},
      'videos': const [],
    };
  }

  String _vehicleText() => [widget.make, widget.model, widget.year?.toString()].where((x) => x != null && x.isNotEmpty).join(' ');

  String _google(String lang) {
    final q = '${widget.code} ${_vehicleText()} ${lang == 'ar' ? 'شرح العطل' : 'fault'}'.trim();
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}';
  }

  String _youtube(String lang) {
    final q = '${widget.code} ${_vehicleText()} ${lang == 'ar' ? 'شرح وإصلاح' : 'repair'}'.trim();
    return 'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}';
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, context.l10n.linkOpenFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final d = _data;
    final search = (d?['search'] as Map?) ?? {};
    final videos = (d?['videos'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text('${l.explainTitle}  ${widget.code}')),
      body: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (d != null) ...[
                SectionCard(
                  title: (lang == 'ar' ? d['title_ar'] : d['title_en'])?.toString() ?? widget.code,
                  icon: Icons.help_outline,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((d['safety'] as String?)?.isNotEmpty == true)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${d['safety']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                      ),
                    Text('${d['explanation'] ?? ''}'),
                    const SizedBox(height: 4),
                    Text(
                      _fromServer
                          ? (d['source'] == 'llm' ? l.explainByAi : l.explainFromKb)
                          : l.explainOffline,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ]),
                ),
                if ((d['causes'] as List?)?.isNotEmpty == true)
                  SectionCard(
                    title: l.probableCauses,
                    icon: Icons.list_alt,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final cstr in d['causes'] as List) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $cstr'))],
                    ),
                  ),
                if ((d['checks'] as List?)?.isNotEmpty == true)
                  SectionCard(
                    title: l.whatToCheck,
                    icon: Icons.checklist,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final cstr in d['checks'] as List) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $cstr'))],
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Google'),
                      onPressed: () => _open('${search['google'] ?? _google(lang)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.ondemand_video, color: Colors.red),
                      label: const Text('YouTube'),
                      onPressed: () => _open('${search['youtube'] ?? _youtube(lang)}'),
                    ),
                  ),
                ]),
              ),
              if (videos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(l.explainVideos, style: Theme.of(context).textTheme.titleMedium),
                ),
              for (final v in videos) _videoTile(v as Map),
            ]),
    );
  }

  Widget _videoTile(Map v) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open('${v['url']}'),
          child: Row(children: [
            if ((v['thumbnail'] as String?)?.isNotEmpty == true)
              Image.network('${v['thumbnail']}', width: 120, height: 68, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(width: 120, height: 68, child: Icon(Icons.ondemand_video))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${v['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ((v['channel'] as String?)?.isNotEmpty == true)
                    Text('${v['channel']}', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
            const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.play_circle_fill, color: Colors.red)),
          ]),
        ),
      );
}

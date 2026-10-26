import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/api/automind_api.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.register = false});
  final bool register;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _totp = TextEditingController();
  bool _terms = false;
  bool _privacy = false;
  bool _busy = false;
  bool _needTotp = false;
  String? _error;

  Future<void> _submit() async {
    final l = context.l10n;
    if (!_form.currentState!.validate()) return;
    if (widget.register && !(_terms && _privacy)) {
      setState(() => _error = l.consentRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      if (widget.register) {
        await auth.register(_email.text.trim(), _password.text, _name.text.trim().isEmpty ? null : _name.text.trim());
      } else {
        await auth.login(_email.text.trim(), _password.text, totp: _needTotp ? _totp.text.trim() : null);
      }
      await ref.read(settingsProvider.notifier).change((s) => s.copyWith(onboardingDone: true));
      ref.invalidate(vehiclesProvider);
      await ref.read(pendingUploadsProvider.notifier).sync();
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      setState(() {
        _needTotp = _needTotp || e.code == 'mfa_required';
        _error = e.isOffline ? l.errorGeneric(ref.read(settingsProvider).backendUrl) : e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(widget.register ? l.register : l.login)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.register)
            TextFormField(controller: _name, decoration: InputDecoration(labelText: l.fullName)),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l.email),
            validator: (v) => v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : l.invalidEmail,
          ),
          TextFormField(
            controller: _password,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l.password, helperText: widget.register ? l.passwordPolicy : null),
            validator: (v) {
              if (v == null || v.isEmpty) return l.passwordPolicy;
              if (widget.register && (v.length < 10 || v == _email.text.trim())) return l.passwordPolicy;
              return null;
            },
          ),
          if (_needTotp)
            TextFormField(controller: _totp, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.mfaCode)),
          if (widget.register) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
              title: Text(l.acceptTerms(AutomindApi.termsVersion)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _privacy,
              onChanged: (v) => setState(() => _privacy = v ?? false),
              title: Text(l.acceptPrivacy(AutomindApi.privacyVersion)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.register ? l.register : l.login),
          ),
          TextButton(
            onPressed: () => context.go(widget.register ? '/login' : '/register'),
            child: Text(widget.register ? l.haveAccount : l.noAccount),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(settingsProvider.notifier).change((s) => s.copyWith(onboardingDone: true));
              if (context.mounted) context.go('/');
            },
            child: Text(l.continueOffline),
          ),
          const SizedBox(height: 8),
          Text(ref.watch(settingsProvider).backendUrl, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

/// Small helper used by other screens.
void requireLoginSnack(BuildContext context, String text) => showSnack(context, text);

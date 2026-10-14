import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'privacy_screen.dart';

/// Bring-your-own-key: enter, verify, replace, remove the Gemini API key and pick a model.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save(AppController app) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await app.saveKey(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = err;
    });
    if (err == null) {
      _ctrl.clear();
      showToast(context, 'Key verified and saved securely', good: true);
    }
  }

  Future<void> _recheck(AppController app) async {
    setState(() => _checking = true);
    final err = await app.recheckKey();
    if (!mounted) return;
    setState(() => _checking = false);
    showToast(context, err ?? 'Key works. ${app.models.length} models available.', good: err == null);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim();
    if (t == null || t.isEmpty) {
      if (mounted) showToast(context, 'Clipboard is empty');
      return;
    }
    setState(() => _ctrl.text = t);
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showToast(context, 'Could not open the browser');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final verifiedAt = app.keyVerifiedAt;
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const BackBar(title: 'AI & your key'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bring your own key.', style: T.display(48)),
                const SizedBox(height: 10),
                Text(
                  "Almanac has no servers and no accounts. When you use an AI feature, this phone talks directly to Google's Gemini API using your key.",
                  style: T.serif(16, height: 1.6),
                ),
                const SizedBox(height: 20),
                if (app.hasKey)
                  PaperCard(
                    color: app.keyVerified ? C.teal.withValues(alpha: 0.1) : C.coral.withValues(alpha: 0.12),
                    border: false,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(app.keyVerified ? Icons.verified_rounded : Icons.error_outline_rounded, color: app.keyVerified ? C.teal : C.crimson),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(app.keyVerified ? 'Gemini connected' : 'Key needs attention', style: T.ui(15, weight: FontWeight.w800)),
                            Text(app.maskedKey, style: T.ui(13, color: C.muted).copyWith(fontFamily: 'monospace')),
                            if (verifiedAt != null) Text('Verified ${fmtDate(isoDate(verifiedAt))} at ${fmtTime(verifiedAt)}', style: T.ui(12, color: C.muted)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        Pill(label: 'Re-check', icon: Icons.refresh_rounded, height: 40, busy: _checking, onTap: () => _recheck(app)),
                        Pill(
                          label: 'Remove key',
                          icon: Icons.delete_outline_rounded,
                          height: 40,
                          bg: C.card,
                          fg: C.crimson,
                          onTap: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Remove your Gemini key?'),
                                content: const Text('AI features switch off and the key is erased from secure storage. Your health data is untouched.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
                                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            await app.removeKey();
                            if (context.mounted) showToast(context, 'Key removed');
                          },
                        ),
                      ]),
                    ]),
                  )
                else
                  PaperCard(
                    child: Row(children: [
                      const Icon(Icons.key_off_rounded, color: C.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text('No key yet. Everything works on-device; AI write-ups and answers switch on once you add one.', style: T.ui(14, height: 1.45, weight: FontWeight.w500))),
                    ]),
                  ),
                const SizedBox(height: 22),
                Kicker(app.hasKey ? 'Replace your key' : 'Paste your key'),
                const SizedBox(height: 8),
                TextField(
                  controller: _ctrl,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  style: T.ui(15, weight: FontWeight.w500).copyWith(fontFamily: 'monospace'),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _save(app),
                  decoration: InputDecoration(
                    hintText: 'AIza…',
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: _obscure ? 'Show key' : 'Hide key',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
                      const SizedBox(width: 4),
                    ]),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  ErrorNote(message: _error!),
                ],
                const SizedBox(height: 12),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (_, v, __) => Pill(
                    label: 'Save & verify',
                    icon: Icons.lock_outline_rounded,
                    bg: C.crimson,
                    expand: true,
                    height: 52,
                    busy: _saving,
                    onTap: v.text.trim().isEmpty ? null : () => _save(app),
                  ),
                ),
                const SizedBox(height: 12),
                Press(
                  onTap: () => _open('https://aistudio.google.com/apikey'),
                  child: Text('Get a free key in Google AI Studio →', style: T.ui(14, color: C.crimson, weight: FontWeight.w800)),
                ),
                if (app.models.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const Kicker('Model'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.rule)),
                    child: Column(children: [
                      for (final m in app.models.take(10))
                        Press(
                          onTap: () => app.setModel(m),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            child: Row(children: [
                              Icon(m == app.model ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: m == app.model ? C.crimson : C.muted, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text(m, style: T.ui(14, weight: m == app.model ? FontWeight.w800 : FontWeight.w600))),
                              if (m.contains('flash')) Text('fast', style: T.ui(12, color: C.muted)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 22),
                PaperCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Use AI insights', style: T.ui(15, weight: FontWeight.w800)),
                        Text('Off = everything stays on-device, even with a key saved.', style: T.ui(13, color: C.muted, weight: FontWeight.w500)),
                      ]),
                    ),
                    Switch(value: app.aiEnabled, onChanged: app.setAiEnabled),
                  ]),
                ),
                const SizedBox(height: 22),
                const _Note(
                  icon: Icons.lock_rounded,
                  title: 'Where your key lives',
                  body: 'Encrypted with the Android Keystore through secure storage. It is never written to logs, exports or backups, and only ever sent to generativelanguage.googleapis.com.',
                ),
                const SizedBox(height: 12),
                _Note(
                  icon: Icons.gavel_rounded,
                  title: "Google's terms apply",
                  body: 'Requests are processed by Google under the Gemini API terms. On the free tier Google may use prompts and responses to improve its products; keys on a billing-enabled project are not used that way.',
                  action: 'Read the Gemini API terms',
                  onAction: () => _open('https://ai.google.dev/gemini-api/terms'),
                ),
                const SizedBox(height: 12),
                _Note(
                  icon: Icons.visibility_outlined,
                  title: 'See exactly what gets sent',
                  body: 'Choose which categories Gemini may see and preview the exact payload.',
                  action: 'Open privacy & sharing',
                  onAction: () => Navigator.of(context).push(slideRoute(const PrivacyScreen())),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.body, this.action, this.onAction});
  final IconData icon;
  final String title, body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0x0F172767), borderRadius: BorderRadius.circular(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: C.navy),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.ui(14, weight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(body, style: T.ui(14, weight: FontWeight.w500, height: 1.45)),
            if (action != null) ...[
              const SizedBox(height: 6),
              Press(onTap: onAction, child: Text('$action →', style: T.ui(14, color: C.crimson, weight: FontWeight.w800))),
            ],
          ]),
        ),
      ]),
    );
  }
}

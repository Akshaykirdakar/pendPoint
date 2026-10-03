import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/staff.dart';
import '../../state/app_state.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import 'common.dart';

/// 🔑 "Change my password" — super admin / store admin. Asks for the current
/// password first (Firebase requires a recent sign-in to change it).
Future<void> showChangeMyPassword(BuildContext context) async {
  final app = context.read<AppState>();
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _PasswordDialog(
      title: tr('🔑 माझा पासवर्ड बदला · Change my password'),
      fields: [
        (current, tr('सध्याचा पासवर्ड · Current password'), 'pw-current'),
        (next, tr('नवीन पासवर्ड · New password'), 'pw-new'),
        (confirm, tr('नवीन पासवर्ड पुन्हा · New password again'), 'pw-confirm'),
      ],
      save: () => app.changeMyPassword(
          current: current.text, next: next.text, confirm: confirm.text),
    ),
  );
  if (done == true && context.mounted) {
    showToast(context, tr('✅ पासवर्ड बदलला · Password changed'));
  }
}

/// 🔑 Sets [user]'s password (super admin: any store user; store admin:
/// their staff). They are signed out of their other devices.
Future<void> showSetPassword(BuildContext context, Staff user) async {
  final app = context.read<AppState>();
  final next = TextEditingController();
  final confirm = TextEditingController();
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _PasswordDialog(
      title: L('🔑 ${user.name} चा पासवर्ड', '🔑 Password for ${user.name}'),
      note: tr(
          'नवीन पासवर्ड त्यांना कळवा. ते इतर फोनवरून बाहेर पडतील. · Tell them the new password. They will be signed out on other phones.'),
      fields: [
        (next, tr('नवीन पासवर्ड · New password'), 'pw-new'),
        (confirm, tr('नवीन पासवर्ड पुन्हा · New password again'), 'pw-confirm'),
      ],
      save: () =>
          app.setPasswordFor(user, next: next.text, confirm: confirm.text),
    ),
  );
  if (done == true && context.mounted) {
    showToast(context, tr('✅ पासवर्ड बदलला · Password changed'));
  }
}

class _PasswordDialog extends StatefulWidget {
  final String title;
  final String? note;
  final List<(TextEditingController, String, String)> fields;
  final Future<String?> Function() save;
  const _PasswordDialog(
      {required this.title,
      required this.fields,
      required this.save,
      this.note});
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  bool _busy = false;
  bool _show = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.save();
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.note != null)
                  Text(widget.note!,
                      style: TextStyle(fontSize: 12.5, color: context.c.ink2)),
                for (final (controller, label, key) in widget.fields)
                  TextField(
                      key: ValueKey(key),
                      controller: controller,
                      obscureText: !_show,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(labelText: label)),
                CheckboxListTile(
                  key: const ValueKey('pw-show'),
                  contentPadding: EdgeInsets.zero,
                  value: _show,
                  title: Text(tr('पासवर्ड दाखवा · Show passwords')),
                  onChanged: (v) => setState(() => _show = v ?? false),
                ),
                if (_error != null)
                  Text(_error!,
                      key: const ValueKey('pw-error'),
                      style: TextStyle(
                          color: context.c.critical,
                          fontWeight: FontWeight.w700)),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(L('रद्द', 'Cancel'))),
          FilledButton(
              key: const ValueKey('pw-save'),
              onPressed: _busy ? null : _save,
              child: Text(L('बदला', 'Change'))),
        ],
      );
}

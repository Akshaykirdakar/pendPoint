import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/staff.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});
  bool _isAdmin(AppState app) => app.staff.any((s) =>
      s.id == FirebaseAuth.instance.currentUser?.uid && s.isAdmin && s.active);
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final admin = _isAdmin(app);
    return PendScaffold(
        titleMr: 'कर्मचारी',
        titleEn: 'Staff management',
        actions: admin
            ? [BarAction('＋ Add staff', onTap: () => _edit(context, null))]
            : [],
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              admin
                  ? 'Manage protected staff profiles.'
                  : 'Staff profiles are managed by an administrator.',
              style: TextStyle(color: context.c.ink2)),
          const SizedBox(height: 12),
          CardList([
            for (final s in app.staff)
              Material(
                  color: context.c.surface,
                  child: ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                          '${s.email ?? s.id}\n${s.isAdmin ? 'Admin' : 'Staff'} · ${s.active ? 'Active' : 'Inactive'} · ${s.canOverride ? 'Override ${s.maxDiscountPct.round()}%' : 'No override'}'),
                      isThreeLine: true,
                      trailing: admin
                          ? IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(context, s))
                          : null))
          ]),
        ]));
  }

  Future<void> _edit(BuildContext context, Staff? old) async {
    final app = context.read<AppState>();
    final name = TextEditingController(text: old?.name ?? '');
    final uid = TextEditingController(text: old?.id ?? '');
    final email = TextEditingController(text: old?.email ?? '');
    final max = TextEditingController(text: '${old?.maxDiscountPct ?? 5}');
    var role = old?.role ?? 'staff';
    var active = old?.active ?? true;
    var override = old?.canOverride ?? true;
    await showDialog(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (dialog, setDialog) => AlertDialog(
                    title: Text(old == null ? 'Add staff' : 'Edit staff'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Name *')),
                      TextField(
                          controller: email,
                          decoration: const InputDecoration(
                              labelText: 'Email / identifier')),
                      if (old == null)
                        TextField(
                            controller: uid,
                            decoration: const InputDecoration(
                                labelText: 'Authenticated UID *',
                                helperText:
                                    'Provision Firebase Auth securely before adding.')),
                      DropdownButtonFormField<String>(
                          initialValue: role,
                          items: const [
                            DropdownMenuItem(
                                value: 'staff', child: Text('Staff')),
                            DropdownMenuItem(
                                value: 'admin', child: Text('Admin'))
                          ],
                          onChanged: (v) =>
                              setDialog(() => role = v ?? 'staff')),
                      SwitchListTile(
                          title: const Text('Active'),
                          value: active,
                          onChanged: (v) => setDialog(() => active = v)),
                      SwitchListTile(
                          title: const Text('Can override price'),
                          value: override,
                          onChanged: (v) => setDialog(() => override = v)),
                      TextField(
                          controller: max,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Maximum discount %')),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () async {
                            final pct = double.tryParse(max.text);
                            if (name.text.trim().isEmpty ||
                                (old == null && uid.text.trim().isEmpty) ||
                                pct == null ||
                                pct < 0 ||
                                pct > 100) {
                              showToast(context,
                                  'Enter name, authenticated UID, and a 0–100 discount');
                              return;
                            }
                            try {
                              await app.saveStaff(Staff(
                                  id: old?.id ?? uid.text.trim(),
                                  name: name.text.trim(),
                                  email: email.text.trim().isEmpty
                                      ? null
                                      : email.text.trim(),
                                  role: role,
                                  active: active,
                                  canOverride: override,
                                  maxDiscountPct: pct));
                              if (dialog.mounted) Navigator.pop(dialog);
                              if (context.mounted) {
                                showToast(context, 'Staff saved');
                              }
                            } catch (e) {
                              if (context.mounted) {
                                showToast(context, 'Save failed: $e');
                              }
                            }
                          },
                          child: const Text('Save'))
                    ])));
  }
}

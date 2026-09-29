import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../../utils/lang.dart';

/// Branch Master create/edit — mirrors [ProductEditScreen]'s conventions
/// (optional id = new vs edit, `_label`/`_f` field helpers, busy-gated save).
class BranchEditScreen extends StatefulWidget {
  final String? branchId;
  const BranchEditScreen({this.branchId, super.key});
  @override
  State<BranchEditScreen> createState() => _BranchEditScreenState();
}

class _BranchEditScreenState extends State<BranchEditScreen> {
  final en = TextEditingController(), mr = TextEditingController();
  final address = TextEditingController();
  bool active = true, busy = false;

  @override
  void initState() {
    super.initState();
    final a = context.read<AppState>();
    final b = widget.branchId == null ? null : a.branchOf(widget.branchId!);
    if (b != null) {
      en.text = b.name;
      mr.text = b.nameMr;
      address.text = b.address;
      active = b.active;
    }
  }

  @override
  void dispose() {
    en.dispose();
    mr.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.branchId != null;
    return PendScaffold(
      titleMr: edit ? 'शाखा संपादन' : 'नवीन शाखा',
      titleEn: edit ? 'Edit branch' : 'New branch',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _f(tr('इंग्रजी नाव · Name (English)'), en),
        _f(tr('मराठी नाव · Marathi name'), mr),
        _f(tr('पत्ता · Address'), address),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('सक्रिय · Active')),
          value: active,
          onChanged: busy ? null : (v) => setState(() => active = v),
        ),
        const SizedBox(height: 8),
        BigButton.brand(busy ? 'Saving...' : tr('जतन करा · Save'),
            onTap: busy ? null : _save),
      ]),
    );
  }

  Future<void> _save() async {
    if (en.text.trim().isEmpty && mr.text.trim().isEmpty) {
      showToast(context, tr('नाव टाका · Enter a name'));
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<AppState>().saveBranch(
            id: widget.branchId,
            name: en.text.trim().isEmpty ? mr.text.trim() : en.text.trim(),
            nameMr: mr.text.trim().isEmpty ? en.text.trim() : mr.text.trim(),
            address: address.text.trim(),
            active: active,
          );
      if (mounted) {
        showToast(context, tr('शाखा जतन · Branch saved'));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, tr('जतन करता आले नाही · Unable to save branch'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _f(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.c.ink2)),
          const SizedBox(height: 5),
          TextField(controller: c, enabled: !busy),
        ]),
      );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/draft_bill.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'sales_entry_screen.dart';

/// 📝 Draft Bills — bills started but not finished. A draft has no effect
/// on stock, payments, credit or reports until it is finalized.
class DraftBillsScreen extends StatefulWidget {
  const DraftBillsScreen({super.key});
  @override
  State<DraftBillsScreen> createState() => _DraftBillsScreenState();
}

class _DraftBillsScreenState extends State<DraftBillsScreen> {
  @override
  void initState() {
    super.initState();
    // Another phone may have saved or finished drafts meanwhile.
    unawaited(context.read<AppState>().refreshDrafts());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final drafts = app.draftsNewestFirst;
    return PendScaffold(
      titleMr: 'ड्राफ्ट बिले',
      titleEn: 'Draft Bills',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            tr('हे बिल अजून पूर्ण झालेले नाही. साठा, पेमेंट, उधार व अहवाल यावर परिणाम नाही · Not finished yet — no effect on stock, payments, credit or reports.'),
            style: TextStyle(color: c.ink2, fontSize: 12.5)),
        const SizedBox(height: 12),
        if (drafts.isEmpty)
          Container(
              decoration: cardDecoration(context),
              child:
                  EmptyState('📝', tr('ड्राफ्ट बिले नाहीत · No draft bills')))
        else
          for (final d in drafts) ...[
            DraftCard(d),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 6),
        BigButton.primary(tr('＋ नवीन बिल · New Bill'),
            key: const ValueKey('drafts-new-bill'),
            onTap: () => openNewBill(context, replace: true)),
      ]),
    );
  }
}

/// 🧾 नवीन विक्री बिल · New Sale Bill — the big primary button (Home, Sell,
/// after a sale). Always a completely fresh bill via [openNewBill]; drafts
/// are opened from 📝 Draft Bills, never from here.
class NewSaleBillButton extends StatelessWidget {
  final bool replace;
  const NewSaleBillButton({this.replace = false, super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openNewBill(context, replace: replace),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const Text('🧾', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(appLang == AppLang.en ? 'New Sale Bill' : 'नवीन विक्री बिल',
                        style: baloo(
                            size: 21, weight: FontWeight.w800, color: c.accentInk)),
                    if (appLang == AppLang.both)
                      Text('New Sale Bill',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.accentInk)),
                  ]),
            ),
            Icon(Icons.add_circle_rounded, color: c.accentInk, size: 30),
          ]),
        ),
      ),
    );
  }
}

/// "📝 ड्राफ्ट" — never looks like a finished bill.
class DraftPill extends StatelessWidget {
  const DraftPill({super.key});
  @override
  Widget build(BuildContext context) =>
      _Pill('📝 ${L('ड्राफ्ट', 'Draft')}', context.c.warning,
          key: const ValueKey('draft-pill'));
}

/// "✅ पूर्ण" — a finished (finalized) bill.
class FinalPill extends StatelessWidget {
  const FinalPill({super.key});
  @override
  Widget build(BuildContext context) =>
      _Pill('✅ ${L('पूर्ण', 'Final')}', context.c.good);
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                color: context.c.ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w800)),
      );
}

/// One draft: number, party, items, amount, last change — Continue/Delete.
class DraftCard extends StatelessWidget {
  final DraftBill draft;
  const DraftCard(this.draft, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final d = draft;
    final party = d.customerId == null ? null : app.partyOf(d.customerId!);
    final partyName = party?.name ?? d.customerName;
    TextStyle label = TextStyle(fontSize: 12.5, color: c.ink2);
    TextStyle value =
        TextStyle(fontSize: 13, color: c.ink, fontWeight: FontWeight.w700);
    Widget fact(String l, String v) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$l: ', style: label),
            TextSpan(text: v, style: value),
          ])),
        );

    return Container(
      key: ValueKey('draft-card-${d.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: c.warning.withValues(alpha: 0.55), width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const DraftPill(),
                  Text('#${d.label}',
                      style: baloo(
                          size: 16, weight: FontWeight.w800, color: c.ink)),
                ]),
          ),
          const SizedBox(width: 8),
          Text(money(d.total),
              style: baloo(size: 17, weight: FontWeight.w800, color: c.ink)),
        ]),
        fact(
            L('पार्टी', 'Party'),
            partyName.isEmpty
                ? L('पार्टी निवडली नाही', 'No party')
                : partyName),
        fact(L('उत्पादने', 'Items'), '${d.lines.length}'),
        fact(L('शेवटचा बदल', 'Last updated'), _when(d.updatedAt)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            flex: 3,
            child: _action(context, tr('▶ पुढे सुरू करा · Continue'), c.brand,
                () => continueDraft(context, d.id),
                key: ValueKey('draft-continue-${d.id}')),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _action(context, tr('🗑 हटवा · Delete'), c.critical,
                () => _confirmDelete(context, app, d),
                key: ValueKey('draft-delete-${d.id}')),
          ),
        ]),
      ]),
    );
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final today =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return today ? '${L('आज', 'Today')} ${timeShort(t)}' : dateTimeShort(t);
  }

  static Widget _action(
          BuildContext context, String text, Color color, VoidCallback onTap,
          {Key? key}) =>
      Material(
        key: key,
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
      );

  Future<void> _confirmDelete(
      BuildContext context, AppState app, DraftBill d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            L('ड्राफ्ट #${d.label} हटवायचा?', 'Delete draft #${d.label}?')),
        content: Text(tr(
            'फक्त हा ड्राफ्ट हटेल. साठा, उधार, पेमेंट व अहवाल बदलणार नाहीत · Only this draft is removed. Stock, credit, payments and reports do not change.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L('नाही', 'No'))),
          FilledButton(
              key: const ValueKey('draft-delete-confirm'),
              style: FilledButton.styleFrom(backgroundColor: ctx.c.critical),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('🗑 हटवा · Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    final error = await app.deleteDraft(d.id);
    if (context.mounted) {
      showToast(context, error ?? tr('ड्राफ्ट हटवला · Draft deleted'));
    }
  }
}

/// "+ नवीन बिल" from anywhere: always a completely empty bill. A bill in
/// progress is first kept as a draft — never carried into the new one.
Future<void> openNewBill(BuildContext context, {bool replace = false}) async {
  if (!await keepCurrentBill(context) || !context.mounted) return;
  context.read<AppState>().startNewBill();
  final route =
      MaterialPageRoute<void>(builder: (_) => const SalesEntryScreen());
  final nav = Navigator.of(context);
  replace ? unawaited(nav.pushReplacement(route)) : unawaited(nav.push(route));
}

/// "▶ पुढे सुरू करा": reopens draft [id] exactly as saved.
Future<void> continueDraft(BuildContext context, String id) async {
  final app = context.read<AppState>();
  if (app.currentDraftId != id &&
      (!await keepCurrentBill(context) || !context.mounted)) {
    return;
  }
  final error = app.openDraft(id);
  if (error != null) {
    showToast(context, error);
    return;
  }
  unawaited(Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SalesEntryScreen())));
}

/// Saves the bill on screen as a draft if it has unsaved changes. False
/// when that failed and the shopkeeper chose not to drop it.
Future<bool> keepCurrentBill(BuildContext context) async {
  final app = context.read<AppState>();
  if (!app.hasUnsavedBill) return true;
  final r = await app.saveDraft();
  if (!context.mounted) return false;
  if (r.ok) {
    showToast(
        context,
        L('✅ मागील बिल ड्राफ्ट #${r.draft!.label} म्हणून सेव्ह झाले',
            '✅ Previous bill saved as Draft #${r.draft!.label}'));
    return true;
  }
  final drop = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title:
          Text(tr('मागील बिल सेव्ह झाले नाही · Previous bill was not saved')),
      content: Text(r.error ?? ''),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('↩ परत जा · Go back'))),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.c.critical),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('🗑 टाका · Discard'))),
      ],
    ),
  );
  return drop == true;
}

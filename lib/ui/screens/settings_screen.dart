import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../../models/app_settings.dart';
import '../../services/dev_seed_service.dart';
import '../../services/thermal_printer_service.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/appearance_settings.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../../utils/lang.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _shopCtrl;
  bool _shopSaving = false;
  bool _shopChanged = false;

  @override
  void initState() {
    super.initState();
    _shopCtrl =
        TextEditingController(text: context.read<AppState>().settings.shop);
    _shopCtrl.addListener(() => setState(() => _shopChanged =
        _shopCtrl.text.trim() != context.read<AppState>().settings.shop));
  }

  @override
  void dispose() {
    _shopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final isAdmin = app.staff.any((s) =>
        s.id == FirebaseAuth.instance.currentUser?.uid &&
        s.isAdmin &&
        s.active);

    return PendScaffold(
      titleMr: 'सेटिंग्ज',
      titleEn: 'Settings',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: Text(tr('दुकानाचे नाव · Shop name'),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: c.ink2))),
        TextField(
            controller: _shopCtrl,
            onSubmitted: (v) {
              _save(context, app, (s) => s.shop = v);
              showToast(context, tr('जतन झाले · Saved'));
            }),
        BigButton.brand(_shopSaving ? 'Saving...' : 'Save shop name',
            onTap: (!isAdmin || !_shopChanged || _shopSaving)
                ? null
                : () => _saveShop(app)),
        SectionHeader(tr('भाषा · Language')),
        _seg(context, [
          (
            'मराठी',
            app.settings.lang == AppLang.mr,
            () => _save(context, app, (s) => s.lang = AppLang.mr)
          ),
          (
            'दोन्ही Both',
            app.settings.lang == AppLang.both,
            () => _save(context, app, (s) => s.lang = AppLang.both)
          ),
          (
            'English',
            app.settings.lang == AppLang.en,
            () => _save(context, app, (s) => s.lang = AppLang.en)
          ),
        ]),
        SectionHeader(tr('देखावा · Appearance')),
        _seg(context, [
          (
            L('ऑटो', 'Auto'),
            app.settings.theme == AppThemeMode.system,
            () => _save(context, app, (s) => s.theme = AppThemeMode.system)
          ),
          (
            '☀️ ${L('उजेड', 'Light')}',
            app.settings.theme == AppThemeMode.light,
            () => _save(context, app, (s) => s.theme = AppThemeMode.light)
          ),
          (
            '🌙 ${L('गडद', 'Dark')}',
            app.settings.theme == AppThemeMode.dark,
            () => _save(context, app, (s) => s.theme = AppThemeMode.dark)
          ),
        ]),
        AppearanceSettings(app: app),
        SectionHeader(tr('प्रिंटर · Bluetooth printer')),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                  app.settings.printerAddress == null
                      ? Icons.print_disabled_outlined
                      : Icons.print_outlined,
                  color:
                      app.settings.printerAddress == null ? c.muted : c.good),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  app.settings.printerAddress == null
                      ? tr('जोडलेला प्रिंटर नाही · No printer paired')
                      : tr('${app.settings.printerName ?? 'Printer'} जोडले · Paired'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            BigButton.ghost(tr('🔍 जोडलेली उपकरणे · Choose paired device'),
                onTap: () => _showPrinterPicker(context, app)),
            if (app.settings.printerAddress != null) ...[
              const SizedBox(height: 8),
              BigButton.ghost(tr('✕ प्रिंटर काढा · Forget printer'), onTap: () {
                app.updateSettings((s) {
                  s.printerName = null;
                  s.printerAddress = null;
                });
                ThermalPrinterService.instance.disconnect();
                showToast(context, tr('प्रिंटर काढले · Printer removed'));
              }),
            ],
            const SizedBox(height: 8),
            Text(
                'बिल प्रतिमा म्हणून छापले जाते जेणेकरून मराठी बरोबर येईल. फक्त ब्लूटूथ (SPP) थर्मल प्रिंटर समर्थित.\nBills print as an image for correct Devanagari. Bluetooth (SPP) thermal printers only.',
                style: TextStyle(fontSize: 11.5, color: c.muted)),
          ]),
        ),
        SectionHeader(tr('🔔 इन्व्हेंटरी सूचना · Inventory Alerts')),
        // InkCard (not a decorated Container) so the switch rows' ripples
        // paint on the card's own Material.
        InkCard(
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            SwitchListTile(
              title: Text(tr('एक्सपायरी सूचना · Expiry alerts')),
              value: app.settings.expiryAlertsOn,
              onChanged: (v) => _save(context, app, (s) => s.expiryAlertsOn = v),
            ),
            _thresholdRow(context, app, tr('नजीक एक्सपायरी · Near Expiry (days)'),
                app.settings.nearExpiryDays, (v) => (s) => s.nearExpiryDays = v),
            _thresholdRow(context, app, tr('एक्सपायरी लवकर · Expiry Soon (days)'),
                app.settings.expirySoonDays, (v) => (s) => s.expirySoonDays = v),
            _thresholdRow(context, app, tr('गंभीर एक्सपायरी · Critical Expiry (days)'),
                app.settings.criticalExpiryDays, (v) => (s) => s.criticalExpiryDays = v),
            SwitchListTile(
              title: Text(tr('कमी साठा सूचना · Low stock alerts')),
              value: app.settings.lowStockAlertsOn,
              onChanged: (v) => _save(context, app, (s) => s.lowStockAlertsOn = v),
            ),
            SwitchListTile(
              title: Text(tr('संपलेला साठा सूचना · Out of stock alerts')),
              value: app.settings.outOfStockAlertsOn,
              onChanged: (v) => _save(context, app, (s) => s.outOfStockAlertsOn = v),
            ),
            SwitchListTile(
              title: Text(tr('बॅच सूचना · Batch alerts')),
              value: app.settings.batchAlertsOn,
              onChanged: (v) => _save(context, app, (s) => s.batchAlertsOn = v),
            ),
          ]),
        ),
        SectionHeader(tr('बॅकअप · Backup')),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'In production this is a scheduled Firestore export to Cloud Storage, plus an on-demand CSV/JSON the owner can keep.',
                style: TextStyle(fontSize: 12.5, color: c.ink2)),
            const SizedBox(height: 10),
            BigButton.ghost(tr('📋 बॅकअप बद्दल · About backup'),
                onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: c.surface,
                        title: Text(tr('बॅकअप · Backup'),
                            style: baloo(
                                size: 17,
                                weight: FontWeight.w700,
                                color: c.ink)),
                        content: Text(
                            'Firestore is durable & replicated, but that is not a restorable backup. Enable a daily managed export (Firestore → Cloud Storage) and offer a local CSV/JSON export the owner controls.',
                            style: TextStyle(color: c.ink2)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(L('ठीक', 'OK')))
                        ],
                      ),
                    )),
          ]),
        ),
        SectionHeader(tr('खाते · Account')),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(FirebaseAuth.instance.currentUser?.email ?? 'Signed-in user',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 10),
            BigButton.danger(tr('बाहेर पडा · Sign Out'),
                onTap: () => _signOut(context)),
          ]),
        ),
        SectionHeader(tr('प्रोटोटाइप · Prototype')),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: BigButton.danger(tr('♻️ नमुना डेटा रीसेट करा · Reset sample data'),
              onTap: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: c.surface,
                      title: Text(L('नमुना दुकान पुन्हा सेट करायचे?', 'Reset to sample shop?')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(L('रद्द', 'Cancel'))),
                        FilledButton(
                            onPressed: () async {
                              await app.resetSampleData();
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (context.mounted) {
                                showToast(
                                    context, tr('रीसेट झाले · Sample data reset'));
                              }
                            },
                            child: Text(L('रीसेट', 'Reset'))),
                      ],
                    ),
                  )),
        ),
        if (kDebugMode && isAdmin) ...[
          const SizedBox(height: 10),
          Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BigButton.brand(
                  _seeding ? tr('तयार करत आहे... · Seeding...') : '🌱 Seed Demo Data (Dev only)',
                  onTap: _seeding ? null : () => _seedDemoData(context, app)),
              const SizedBox(height: 6),
              Text(
                  'Debug-build only — writes real Branch/Brand/Supplier/Product/Batch/'
                  'Bill records through the same authenticated app code path (not the '
                  'Admin SDK), so it also proves whether the signed-in user\'s Firestore '
                  'rules actually allow these writes. Safe to run more than once.',
                  style: TextStyle(fontSize: 11, color: c.muted)),
            ]),
          ),
        ],
      ]),
    );
  }

  bool _seeding = false;

  Future<void> _seedDemoData(BuildContext context, AppState app) async {
    setState(() => _seeding = true);
    try {
      final result = await DevSeedService.seed(app);
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.c.surface,
          title: Text(result.alreadySeeded
              ? L('नमुना डेटा आधीच आहे', 'Already seeded')
              : L('नमुना डेटा जोडला', 'Demo data seeded')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in result.created.entries)
                  if (e.value > 0) Text('${e.key}: +${e.value}'),
                if (result.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final n in result.notes) Text(n, style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'Seeding failed: $e');
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _saveShop(AppState app) async {
    setState(() => _shopSaving = true);
    try {
      await app.updateSettings((s) => s.shop = _shopCtrl.text.trim());
      if (mounted) {
        setState(() => _shopChanged = false);
        showToast(context, L('जतन झाले', 'Saved successfully'));
      }
    } catch (e) {
      if (mounted) showToast(context, '${L('जतन झाले नाही', 'Save failed')}: $e');
    } finally {
      if (mounted) setState(() => _shopSaving = false);
    }
  }

  /// A labeled ±-stepper for one integer threshold in Settings (Near
  /// Expiry/Expiry Soon/Critical Expiry days — spec §27N), saved immediately
  /// via [_save] on each tap, same as every other toggle on this screen.
  Widget _thresholdRow(BuildContext context, AppState app, String label, int value,
      void Function(AppSettings) Function(int) mutateWith) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: c.ink))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value <= 1
              ? null
              : () => _save(context, app, mutateWith(value - 1)),
        ),
        SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: baloo(size: 14, weight: FontWeight.w700, color: c.ink))),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _save(context, app, mutateWith(value + 1)),
        ),
      ]),
    );
  }

  Future<void> _save(BuildContext context, AppState app,
      void Function(AppSettings) mutate) async {
    try {
      await app.updateSettings(mutate);
      if (context.mounted) showToast(context, tr('जतन झाले · Saved'));
    } catch (_) {
      if (context.mounted) {
        showToast(
            context, tr('सेटिंग्ज जतन करता आल्या नाहीत · Unable to save settings'));
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(tr('बाहेर पडा · Sign Out')),
              content: Text(
                  tr('तुम्हाला साइन आउट करायचे आहे का?\nAre you sure you want to sign out?')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sign Out'))
              ],
            ));
    if (yes == true) await FirebaseAuth.instance.signOut();
  }

  Future<void> _showPrinterPicker(BuildContext context, AppState app) async {
    final service = ThermalPrinterService.instance;
    final permitted = await service.ensurePermission();
    if (!permitted) {
      if (context.mounted) {
        showToast(
            context, tr('ब्लूटूथ परवानगी आवश्यक · Bluetooth permission needed'));
      }
      return;
    }
    final devices = await service.discoverDevices();
    if (!context.mounted) return;
    if (devices.isEmpty) {
      showToast(context,
          tr('जोडलेले उपकरण नाही — फोनच्या ब्लूटूथ सेटिंग्जमध्ये प्रथम पेअर करा · No paired device — pair it in phone Bluetooth settings first'));
      return;
    }
    final c = context.c;
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: c.line,
                          borderRadius: BorderRadius.circular(9)))),
              Text(tr('प्रिंटर निवडा · Choose printer'),
                  style:
                      baloo(size: 18, weight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 12),
              for (final d in devices)
                InkWell(
                  onTap: () => _connectPrinter(context, ctx, app, d),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(Icons.print_outlined, color: c.ink2),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(d.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, color: c.ink))),
                      Text(d.address,
                          style: TextStyle(fontSize: 11.5, color: c.muted)),
                    ]),
                  ),
                ),
            ]),
      ),
    );
  }

  Future<void> _connectPrinter(
      BuildContext screenContext,
      BuildContext sheetContext,
      AppState app,
      BluetoothPrinterDevice device) async {
    final ok = await ThermalPrinterService.instance.connect(device);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    if (!ok) {
      if (screenContext.mounted) {
        showToast(
            screenContext, tr('प्रिंटरशी जोडता आले नाही · Could not connect'));
      }
      return;
    }
    await app.updateSettings((s) {
      s.printerName = device.name;
      s.printerAddress = device.address;
    });
    if (screenContext.mounted) {
      showToast(screenContext, tr('प्रिंटर जोडले · Printer paired'));
    }
  }

  Widget _seg(BuildContext context, List<(String, bool, VoidCallback)> items) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line)),
      child: Row(children: [
        for (final it in items)
          Expanded(
            child: GestureDetector(
              onTap: it.$3,
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: it.$2 ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: it.$2
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6)
                          ]
                        : null),
                child: Text(it.$1,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: it.$2 ? c.brand : c.ink2)),
              ),
            ),
          ),
      ]),
    );
  }
}

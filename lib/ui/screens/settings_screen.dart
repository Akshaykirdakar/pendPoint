import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../services/thermal_printer_service.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final shopCtrl = TextEditingController(text: app.settings.shop);

    return PendScaffold(
      titleMr: 'सेटिंग्ज',
      titleEn: 'Settings',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: Text('दुकानाचे नाव · Shop name',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: c.ink2))),
        TextField(
            controller: shopCtrl,
            onSubmitted: (v) {
              app.updateSettings((s) => s.shop = v);
              showToast(context, 'जतन झाले · Saved');
            }),
        SectionHeader('भाषा · Language'),
        _seg(context, [
          (
            'मराठी',
            app.settings.lang == AppLang.mr,
            () => app.updateSettings((s) => s.lang = AppLang.mr)
          ),
          (
            'दोन्ही Both',
            app.settings.lang == AppLang.both,
            () => app.updateSettings((s) => s.lang = AppLang.both)
          ),
          (
            'English',
            app.settings.lang == AppLang.en,
            () => app.updateSettings((s) => s.lang = AppLang.en)
          ),
        ]),
        SectionHeader('देखावा · Appearance'),
        _seg(context, [
          (
            'ऑटो',
            app.settings.theme == AppThemeMode.system,
            () => app.updateSettings((s) => s.theme = AppThemeMode.system)
          ),
          (
            '☀️ Light',
            app.settings.theme == AppThemeMode.light,
            () => app.updateSettings((s) => s.theme = AppThemeMode.light)
          ),
          (
            '🌙 Dark',
            app.settings.theme == AppThemeMode.dark,
            () => app.updateSettings((s) => s.theme = AppThemeMode.dark)
          ),
        ]),
        SectionHeader('प्रिंटर · Bluetooth printer'),
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
                  color: app.settings.printerAddress == null
                      ? c.muted
                      : c.good),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  app.settings.printerAddress == null
                      ? 'जोडलेला प्रिंटर नाही · No printer paired'
                      : '${app.settings.printerName ?? 'Printer'} जोडले · Paired',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            BigButton.ghost('🔍 जोडलेली उपकरणे · Choose paired device',
                onTap: () => _showPrinterPicker(context, app)),
            if (app.settings.printerAddress != null) ...[
              const SizedBox(height: 8),
              BigButton.ghost('✕ प्रिंटर काढा · Forget printer', onTap: () {
                app.updateSettings((s) {
                  s.printerName = null;
                  s.printerAddress = null;
                });
                ThermalPrinterService.instance.disconnect();
                showToast(context, 'प्रिंटर काढले · Printer removed');
              }),
            ],
            const SizedBox(height: 8),
            Text(
                'बिल प्रतिमा म्हणून छापले जाते जेणेकरून मराठी बरोबर येईल. फक्त ब्लूटूथ (SPP) थर्मल प्रिंटर समर्थित.\nBills print as an image for correct Devanagari. Bluetooth (SPP) thermal printers only.',
                style: TextStyle(fontSize: 11.5, color: c.muted)),
          ]),
        ),
        SectionHeader('बॅकअप · Backup'),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'In production this is a scheduled Firestore export to Cloud Storage, plus an on-demand CSV/JSON the owner can keep.',
                style: TextStyle(fontSize: 12.5, color: c.ink2)),
            const SizedBox(height: 10),
            BigButton.ghost('📋 बॅकअप बद्दल · About backup',
                onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: c.surface,
                        title: Text('बॅकअप · Backup',
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
                              child: const Text('ठीक'))
                        ],
                      ),
                    )),
          ]),
        ),
        SectionHeader('प्रोटोटाइप · Prototype'),
        Container(
          decoration: cardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: BigButton.danger('♻️ नमुना डेटा रीसेट करा · Reset sample data',
              onTap: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: c.surface,
                      title: const Text('Reset to sample shop?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('रद्द')),
                        FilledButton(
                            onPressed: () async {
                              await app.resetSampleData();
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (context.mounted) {
                                showToast(
                                    context, 'रीसेट झाले · Sample data reset');
                              }
                            },
                            child: const Text('रीसेट')),
                      ],
                    ),
                  )),
        ),
      ]),
    );
  }

  Future<void> _showPrinterPicker(BuildContext context, AppState app) async {
    final service = ThermalPrinterService.instance;
    final permitted = await service.ensurePermission();
    if (!permitted) {
      if (context.mounted) {
        showToast(
            context, 'ब्लूटूथ परवानगी आवश्यक · Bluetooth permission needed');
      }
      return;
    }
    final devices = await service.bondedDevices();
    if (!context.mounted) return;
    if (devices.isEmpty) {
      showToast(context,
          'जोडलेले उपकरण नाही — फोनच्या ब्लूटूथ सेटिंग्जमध्ये प्रथम पेअर करा · No paired device — pair it in phone Bluetooth settings first');
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
                          color: c.line, borderRadius: BorderRadius.circular(9)))),
              Text('प्रिंटर निवडा · Choose printer',
                  style: baloo(size: 18, weight: FontWeight.w700, color: c.ink)),
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
                          child: Text(d.name ?? 'Unknown device',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, color: c.ink))),
                      Text(d.address ?? '',
                          style: TextStyle(fontSize: 11.5, color: c.muted)),
                    ]),
                  ),
                ),
            ]),
      ),
    );
  }

  Future<void> _connectPrinter(BuildContext screenContext, BuildContext sheetContext,
      AppState app, BluetoothDevice device) async {
    final ok = await ThermalPrinterService.instance.connect(device);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    if (!ok) {
      if (screenContext.mounted) {
        showToast(screenContext, 'प्रिंटरशी जोडता आले नाही · Could not connect');
      }
      return;
    }
    await app.updateSettings((s) {
      s.printerName = device.name;
      s.printerAddress = device.address;
    });
    if (screenContext.mounted) {
      showToast(screenContext, 'प्रिंटर जोडले · Printer paired');
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

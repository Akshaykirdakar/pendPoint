import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/store.dart';
import '../../state/app_state.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// ⚙️ One store's own settings, edited by the super admin from the Stores
/// tab without opening the store (or by that store's admin). Saved to
/// stores/{id}/meta/settings — no other store is touched; that store's
/// devices pick the change up live. The Bluetooth printer is paired on each
/// device from the store's own Settings screen.
class StoreSettingsScreen extends StatefulWidget {
  final Store store;
  const StoreSettingsScreen({required this.store, super.key});
  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  AppSettings? _before;
  AppSettings? _s;
  Object? _loadError;
  final _shop = TextEditingController();
  final _num = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().platform.storeSettings(widget.store.id).then((s) {
      if (!mounted) return;
      setState(() {
        _before = s;
        _s = s.copy();
        _shop.text = s.shop;
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _loadError = e);
    });
  }

  @override
  void dispose() {
    _shop.dispose();
    for (final c in _num.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _number(String key, String mr, String en, int value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: ValueKey('ss-$key'),
          controller:
              _num.putIfAbsent(key, () => TextEditingController(text: '$value')),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: L(mr, en)),
        ),
      );

  Widget _toggle(String key, String mr, String en, bool value,
          void Function(bool) set) =>
      SwitchListTile(
        key: ValueKey('ss-$key'),
        contentPadding: EdgeInsets.zero,
        title: Text(L(mr, en)),
        value: value,
        onChanged: (v) => setState(() => set(v)),
      );

  Widget _choice<T>(String key, String label, T value, List<(T, String)> items,
          void Function(T) set) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<T>(
          key: ValueKey('ss-$key'),
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final (v, text) in items)
              DropdownMenuItem<T>(value: v, child: Text(text)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => set(v));
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _s;
    final st = widget.store;
    return PendScaffold(
      titleMr: 'दुकान सेटिंग्ज',
      titleEn: 'Store settings',
      body: _loadError != null
          ? EmptyState('⚠️', '$_loadError')
          : s == null
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    key: const ValueKey('ss-scope'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: c.brand.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(
                        L('🏪 ${st.storeName} (${st.id}) च्या सेटिंग्ज — फक्त या दुकानासाठी.',
                            '🏪 Settings of ${st.storeName} (${st.id}) — this store only.'),
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                  ),
                  SectionHeader(tr('दुकान · Shop')),
                  TextField(
                      key: const ValueKey('ss-shop'),
                      controller: _shop,
                      decoration: InputDecoration(
                          labelText: L('बिलावरील दुकानाचे नाव', 'Shop name on bills'))),
                  const SizedBox(height: 10),
                  _choice<AppLang>('lang', L('भाषा', 'Language'), s.lang, [
                    (AppLang.mr, 'मराठी'),
                    (AppLang.both, tr('दोन्ही · Both')),
                    (AppLang.en, 'English'),
                  ], (v) => s.lang = v),
                  _choice<AppThemeMode>('theme', L('देखावा', 'Appearance'), s.theme, [
                    (AppThemeMode.system, L('ऑटो', 'Auto')),
                    (AppThemeMode.light, L('उजेड', 'Light')),
                    (AppThemeMode.dark, L('गडद', 'Dark')),
                  ], (v) => s.theme = v),
                  _choice<AppColorTheme>('color', L('रंग', 'Colour theme'), s.colorTheme, [
                    for (final t in AppColorTheme.values) (t, t.name),
                  ], (v) => s.colorTheme = v),
                  _choice<AppFontSize>('font', L('अक्षरांचा आकार', 'Text size'), s.fontSize, [
                    for (final f in AppFontSize.values) (f, f.name),
                  ], (v) => s.fontSize = v),
                  SectionHeader(tr('विक्री नियम · Sales rules')),
                  _toggle('floor', 'किमान भाव लागू', 'Enforce product price floor', s.floorOn,
                      (v) => s.floorOn = v),
                  _toggle('gate', 'मोठ्या सवलतीसाठी मालक PIN', 'Owner PIN for large discounts',
                      s.gateOverride, (v) => s.gateOverride = v),
                  _number('gatePct', 'PIN लागणारी सवलत %', 'Discount % needing PIN',
                      s.gateOverridePct.round()),
                  SectionHeader(tr('🔔 साठा सूचना · Inventory alerts')),
                  _number('lowBags', 'कमी साठा (पोती)', 'Low stock default (bags)', s.lowDefaultBags),
                  _toggle('expiry', 'एक्सपायरी सूचना', 'Expiry alerts', s.expiryAlertsOn,
                      (v) => s.expiryAlertsOn = v),
                  _number('near', 'नजीक एक्सपायरी (दिवस)', 'Near expiry (days)', s.nearExpiryDays),
                  _number('soon', 'एक्सपायरी लवकर (दिवस)', 'Expiry soon (days)', s.expirySoonDays),
                  _number('critical', 'गंभीर एक्सपायरी (दिवस)', 'Critical expiry (days)',
                      s.criticalExpiryDays),
                  _toggle('low', 'कमी साठा सूचना', 'Low stock alerts', s.lowStockAlertsOn,
                      (v) => s.lowStockAlertsOn = v),
                  _toggle('out', 'संपलेला साठा सूचना', 'Out of stock alerts', s.outOfStockAlertsOn,
                      (v) => s.outOfStockAlertsOn = v),
                  _toggle('batch', 'बॅच सूचना', 'Batch alerts', s.batchAlertsOn,
                      (v) => s.batchAlertsOn = v),
                  Text(
                      tr('ब्लूटूथ प्रिंटर प्रत्येक फोनवर दुकानाच्या सेटिंग्जमधून जोडा. · The Bluetooth printer is paired on each phone from the store\'s own Settings.'),
                      style: TextStyle(fontSize: 11.5, color: c.muted)),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!,
                          key: const ValueKey('ss-error'),
                          style: TextStyle(color: c.critical, fontWeight: FontWeight.w800)),
                    ),
                  const SizedBox(height: 14),
                  BigButton.primary(tr('जतन करा · Save'),
                      key: const ValueKey('ss-save'), onTap: _busy ? null : _save),
                ]),
    );
  }

  Future<void> _save() async {
    final s = _s!;
    int n(String k, int fallback) {
      final v = int.tryParse(_num[k]?.text.trim() ?? '');
      return v == null || v < 0 ? fallback : v;
    }

    final next = s.copy()
      ..shop = _shop.text.trim()
      ..gateOverridePct = n('gatePct', s.gateOverridePct.round()).toDouble()
      ..lowDefaultBags = n('lowBags', s.lowDefaultBags)
      ..nearExpiryDays = n('near', s.nearExpiryDays)
      ..expirySoonDays = n('soon', s.expirySoonDays)
      ..criticalExpiryDays = n('critical', s.criticalExpiryDays);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context
        .read<AppState>()
        .platform
        .saveStoreSettings(widget.store.id, _before!, next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _before = next.copy();
    });
    if (error == null) showToast(context, tr('✅ जतन झाले · Saved'));
  }
}

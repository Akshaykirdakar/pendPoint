import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/platform.dart';
import '../../state/app_state.dart';
import '../../utils/lang.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// ⚙️ Super Admin → General Settings (global, not per store). Saved to
/// global_settings/general (everyone reads) and global_settings/admin
/// (super admin only). API secrets are never entered here.
class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});
  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  GlobalSettings? _s;
  final _t = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  TextEditingController _c(String key, String value) =>
      _t.putIfAbsent(key, () => TextEditingController(text: value));

  @override
  void initState() {
    super.initState();
    context.read<AppState>().platform.settings(refresh: true).then((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  @override
  void dispose() {
    for (final c in _t.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _text(String key, String mr, String en, String value,
          {int lines = 1, TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: ValueKey('gs-$key'),
          controller: _c(key, value),
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          keyboardType: type,
          decoration: InputDecoration(labelText: L(mr, en)),
        ),
      );

  Widget _switch(String key, String mr, String en, bool value,
          void Function(bool) set) =>
      SwitchListTile(
        key: ValueKey('gs-$key'),
        contentPadding: EdgeInsets.zero,
        title: Text(L(mr, en)),
        value: value,
        onChanged: (v) => setState(() => set(v)),
      );

  List<int> _days(String key, List<int> fallback) {
    final parts = _t[key]?.text.split(RegExp(r'[,\s]+')) ?? const [];
    final out = [for (final p in parts) if (int.tryParse(p) != null) int.parse(p)];
    return out.isEmpty ? fallback : out;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return PendScaffold(
      titleMr: 'सामान्य सेटिंग्ज',
      titleEn: 'General settings',
      body: s == null
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionHeader(tr('ॲप्लिकेशन · Application')),
              _text('appName', 'ॲपचे नाव', 'Application name', s.appName),
              _text('logoUrl', 'लोगो लिंक', 'Logo URL', s.logoUrl),
              _text('appVersion', 'आवृत्ती', 'Version', s.appVersion),
              _text('companyName', 'कंपनी / व्यवसाय', 'Company / business name',
                  s.companyName),
              _text('address', 'पत्ता', 'Address', s.address, lines: 2),
              _text('website', 'वेबसाइट', 'Website', s.website),
              _text('supportPhone', 'मदत फोन', 'Support phone', s.supportPhone,
                  type: TextInputType.phone),
              _text('supportEmail', 'मदत ईमेल', 'Support email',
                  s.supportEmail,
                  type: TextInputType.emailAddress),
              _text('supportWhatsApp', 'मदत WhatsApp', 'Support WhatsApp',
                  s.supportWhatsApp,
                  type: TextInputType.phone),
              DropdownButtonFormField<String>(
                key: const ValueKey('gs-language'),
                isExpanded: true,
                initialValue: s.defaultLanguage,
                decoration: InputDecoration(
                    labelText: L('मूळ भाषा', 'Default language')),
                items: [
                  DropdownMenuItem(value: 'both', child: Text(tr('दोन्ही · Both'))),
                  DropdownMenuItem(value: 'mr', child: Text(L('मराठी', 'Marathi'))),
                  DropdownMenuItem(value: 'en', child: Text(L('इंग्रजी', 'English'))),
                ],
                onChanged: (v) => setState(() => s.defaultLanguage = v ?? 'both'),
              ),
              SectionHeader(tr('सूचना · Notifications')),
              _switch('inApp', 'ॲपमधील सूचना', 'In-app notifications',
                  s.inAppEnabled, (v) => s.inAppEnabled = v),
              _switch('whatsApp', 'WhatsApp सूचना', 'WhatsApp notifications',
                  s.whatsAppEnabled, (v) => s.whatsAppEnabled = v),
              _switch('sms', 'SMS सूचना', 'SMS notifications', s.smsEnabled,
                  (v) => s.smsEnabled = v),
              _switch('paymentReminders', 'पेमेंट आठवण', 'Payment reminders',
                  s.paymentReminders, (v) => s.paymentReminders = v),
              _switch('renewalReminders', 'नूतनीकरण आठवण', 'Renewal reminders',
                  s.renewalReminders, (v) => s.renewalReminders = v),
              _switch('expiryReminders', 'मुदत संपण्याची आठवण',
                  'Plan expiry reminders', s.expiryReminders,
                  (v) => s.expiryReminders = v),
              _switch('promotions', 'ऑफर संदेश', 'Promotional announcements',
                  s.promotions, (v) => s.promotions = v),
              _switch('maintenance', 'देखभाल सूचना', 'Maintenance announcements',
                  s.maintenanceNotices, (v) => s.maintenanceNotices = v),
              SectionHeader(tr('WhatsApp / SMS प्रोव्हायडर · Providers')),
              Text(
                  tr('WhatsApp / SMS पाठवण्यासाठी प्रोव्हायडर (उदा. WhatsApp Cloud API, DLT SMS) सर्व्हरवर जोडावा लागेल. API की इथे टाकू नका. · Sending WhatsApp / SMS needs a provider connected on the server. Never enter API keys here.'),
                  key: const ValueKey('gs-provider-note'),
                  style: TextStyle(fontSize: 12.5, color: context.c.critical)),
              const SizedBox(height: 8),
              _text('whatsAppProvider', 'WhatsApp प्रोव्हायडर', 'WhatsApp provider',
                  s.whatsAppProvider),
              _text('whatsAppSender', 'WhatsApp पाठवणारा नंबर', 'WhatsApp sender number',
                  s.whatsAppSender),
              _text('smsProvider', 'SMS प्रोव्हायडर', 'SMS provider', s.smsProvider),
              _text('smsSender', 'SMS पाठवणारा ID', 'SMS sender ID', s.smsSender),
              SectionHeader(tr('प्लॅन · Plans')),
              _text('trialDays', 'ट्रायल दिवस', 'Default trial (days)',
                  '${s.trialDays}',
                  type: TextInputType.number),
              _text('planDays', 'प्लॅन दिवस', 'Default plan (days)', '${s.planDays}',
                  type: TextInputType.number),
              _text('graceDays', 'जास्तीचे दिवस', 'Renewal grace period (days)',
                  '${s.graceDays}',
                  type: TextInputType.number),
              _text('before', 'मुदतीआधी आठवण (दिवस)', 'Remind before expiry (days)',
                  s.remindBeforeDays.join(', ')),
              _text('after', 'मुदतीनंतर आठवण (दिवस)', 'Remind after expiry (days)',
                  s.remindAfterDays.join(', ')),
              SectionHeader(tr('संदेश नमुने · Message templates')),
              Text(
                  '{storeName} {storeCode} {amount} {dueDate} {expiryDate} {days} {appName} {supportPhone}',
                  style: TextStyle(fontSize: 11.5, color: context.c.muted)),
              const SizedBox(height: 8),
              for (final e in const [
                (NoticeType.paymentReminder, 'पेमेंट आठवण', 'Payment reminder'),
                (NoticeType.renewalReminder, 'नूतनीकरण आठवण', 'Renewal reminder'),
                (NoticeType.planExpiry, 'मुदत संपत आहे', 'Expiry warning'),
                (NoticeType.planExpired, 'मुदत संपली', 'Plan expired'),
                (NoticeType.paymentConfirmation, 'पेमेंट मिळाले', 'Payment confirmation'),
                (NoticeType.offer, 'ऑफर', 'Promotional message'),
                (NoticeType.announcement, 'घोषणा', 'Announcement'),
                (NoticeType.maintenance, 'देखभाल', 'Maintenance'),
              ])
                _text('tpl-${e.$1}', e.$2, e.$3, s.template(e.$1), lines: 2),
              if (_error != null)
                Text(_error!,
                    key: const ValueKey('gs-error'),
                    style: TextStyle(
                        color: context.c.critical, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              BigButton.primary(tr('जतन करा · Save'),
                  key: const ValueKey('gs-save'), onTap: _busy ? null : _save),
            ]),
    );
  }

  Future<void> _save() async {
    final s = _s!;
    String t(String k) => _t[k]?.text.trim() ?? '';
    int n(String k, int d) => int.tryParse(t(k)) ?? d;
    final next = GlobalSettings(
      appName: t('appName'),
      logoUrl: t('logoUrl'),
      appVersion: t('appVersion'),
      supportPhone: t('supportPhone'),
      supportEmail: t('supportEmail'),
      supportWhatsApp: t('supportWhatsApp'),
      companyName: t('companyName'),
      address: t('address'),
      website: t('website'),
      defaultLanguage: s.defaultLanguage,
      inAppEnabled: s.inAppEnabled,
      whatsAppEnabled: s.whatsAppEnabled,
      smsEnabled: s.smsEnabled,
      paymentReminders: s.paymentReminders,
      renewalReminders: s.renewalReminders,
      expiryReminders: s.expiryReminders,
      promotions: s.promotions,
      maintenanceNotices: s.maintenanceNotices,
      trialDays: n('trialDays', s.trialDays),
      planDays: n('planDays', s.planDays),
      graceDays: n('graceDays', s.graceDays),
      remindBeforeDays: _days('before', s.remindBeforeDays),
      remindAfterDays: _days('after', s.remindAfterDays),
      templates: {
        for (final k in defaultTemplates.keys)
          k: t('tpl-$k').isEmpty ? s.template(k) : t('tpl-$k'),
      },
      whatsAppProvider: t('whatsAppProvider'),
      whatsAppSender: t('whatsAppSender'),
      smsProvider: t('smsProvider'),
      smsSender: t('smsSender'),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final error = await app.platform.saveSettings(next);
    if (error == null) await app.applyPlatformLanguage();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _s = next;
    });
    if (error == null) showToast(context, tr('✅ जतन झाले · Saved'));
  }
}

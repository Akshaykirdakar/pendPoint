import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/party.dart';
import '../../services/whatsapp_service.dart';
import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import '../../utils/lang.dart';

/// Create / edit one party (Party Master). Pops with the saved [Party].
///
/// A party's roles can be added (a customer who also starts supplying
/// becomes "Both") but never removed here, since sales/purchase history
/// refers to them. Purchase parties are supplier records, which Firestore
/// rules let only the owner/admin write — so for other logins the purchase
/// role is shown but locked.
class PartyEditScreen extends StatefulWidget {
  final String? partyId;
  final PartyType initialType;

  /// What was typed in a search box before tapping "New" — pre-fills the
  /// mobile field when it looks like a number, otherwise the name.
  final String initialText;

  const PartyEditScreen({
    this.partyId,
    this.initialType = PartyType.sales,
    this.initialText = '',
    super.key,
  });

  @override
  State<PartyEditScreen> createState() => _PartyEditScreenState();
}

class _PartyEditScreenState extends State<PartyEditScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  bool _sales = true;
  bool _purchase = false;
  bool _hadSales = false;
  bool _hadPurchase = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final party = widget.partyId == null ? null : app.partyOf(widget.partyId!);
    if (party != null) {
      _code.text = party.code;
      _name.text = party.name;
      _mobile.text = party.mobile;
      _address.text = party.address;
      _hadSales = _sales = party.type.isSales;
      _hadPurchase = _purchase = party.type.isPurchase;
    } else {
      _code.text = app.nextPartyCode();
      _sales = widget.initialType.isSales;
      _purchase = widget.initialType.isPurchase && app.hasOwnerRights;
      final t = widget.initialText.trim();
      if (t.isNotEmpty) {
        final digits = digitsOnly(t);
        if (digits.length >= 6 &&
            digits.length == t.replaceAll(' ', '').length) {
          _mobile.text = t;
        } else {
          _name.text = t;
        }
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _mobile.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final owner = app.hasOwnerRights;
    // Supplier records are owner-only in Firestore rules.
    final readOnly = _hadPurchase && !owner;
    final mobileOk = _mobile.text.trim().isEmpty ||
        WhatsAppService.phoneForWhatsApp(_mobile.text) != null;

    return PendScaffold(
      titleMr: widget.partyId == null ? 'नवीन पार्टी' : 'पार्टी बदला',
      titleEn: widget.partyId == null ? 'New party' : 'Edit party',
      bottomBar: BigButton.brand(
          _busy
              ? tr('जतन होत आहे... · Saving...')
              : tr('💾 पार्टी जतन करा · Save party'),
          onTap: _busy || readOnly ? null : () => _save(app)),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                tr('ही खरेदी पार्टी आहे — फक्त मालक बदल करू शकतात · This is a purchase party; only the owner can edit it.'),
                style: TextStyle(color: c.serious, fontSize: 12.5)),
          ),
        Row(children: [
          SizedBox(
            width: 110,
            child: TextField(
              key: const ValueKey('party-code'),
              controller: _code,
              enabled: !readOnly,
              decoration: InputDecoration(labelText: tr('कोड · Code')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('party-name'),
              controller: _name,
              enabled: !readOnly,
              autofocus: widget.partyId == null && _name.text.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('नाव · Name *')),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('party-mobile'),
          controller: _mobile,
          enabled: !readOnly,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr('मोबाइल · Mobile'),
            helperText: mobileOk
                ? L('WhatsApp वर बिल पाठवण्यासाठी', 'Used to send bills on WhatsApp')
                : tr('10 अंकी मोबाइल लागेल · WhatsApp needs a 10-digit mobile'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          enabled: !readOnly,
          maxLines: 2,
          decoration: InputDecoration(labelText: tr('पत्ता · Address')),
        ),
        SectionHeader(tr('प्रकार · Party type')),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilterChip(
            label: Text(tr('विक्री · Sales')),
            selected: _sales,
            onSelected: readOnly || _hadSales
                ? null
                : (v) => setState(() => _sales = v),
          ),
          FilterChip(
            label: Text(tr('खरेदी · Purchase')),
            selected: _purchase,
            onSelected: readOnly || _hadPurchase || !owner
                ? null
                : (v) => setState(() => _purchase = v),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            _sales && _purchase
                ? tr('दोन्ही · Both — buys from you and supplies to you')
                : _purchase
                    ? tr('खरेदी पार्टी · Supplier you buy from')
                    : tr('विक्री पार्टी · Customer you sell to (khata)'),
            style: TextStyle(fontSize: 12, color: c.ink2)),
        if (!owner)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                tr('खरेदी पार्टी फक्त मालक जोडू शकतात · Only the owner can add purchase parties.'),
                style: TextStyle(fontSize: 11.5, color: c.muted)),
          ),
      ]),
    );
  }

  Future<void> _save(AppState app) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, tr('नाव टाका · Enter a name'));
      return;
    }
    if (!_sales && !_purchase) {
      showToast(context, tr('प्रकार निवडा · Pick sales and/or purchase'));
      return;
    }
    final code = _code.text.trim();
    if (app.partyCodeTaken(code, exceptId: widget.partyId)) {
      showToast(context, tr('हा कोड आधीच वापरला · Code $code is already used'));
      return;
    }
    setState(() => _busy = true);
    try {
      final party = await app.saveParty(
        id: widget.partyId,
        name: name,
        code: code,
        mobile: _mobile.text.trim(),
        address: _address.text.trim(),
        type: _sales && _purchase
            ? PartyType.both
            : (_purchase ? PartyType.purchase : PartyType.sales),
      );
      if (mounted) Navigator.pop(context, party);
    } catch (e) {
      if (mounted) showToast(context, tr('जतन झाले नाही · Could not save: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

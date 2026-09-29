import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/brand.dart';
import '../../state/app_state.dart';
import '../../state/purchase_draft.dart';
import '../../utils/lang.dart';
import '../../utils/marathi_transliteration.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// Brand master: English + Marathi name, an optional photo/logo, Active /
/// Inactive, and Delete. Delete is offered only when every product of the
/// brand has no stock and no past bills/purchases (see
/// [AppState.whyBrandNotDeletable]); otherwise the screen explains why and
/// offers "Make Inactive" — which keeps all history.
class BrandEditScreen extends StatefulWidget {
  final String? brandId; // null = new brand
  const BrandEditScreen({this.brandId, super.key});

  /// Test hook replacing the camera/gallery picker (needs a real device).
  @visibleForTesting
  static Future<({Uint8List bytes, String name})?> Function(ImageSource)?
      debugPickPhoto;

  @override
  State<BrandEditScreen> createState() => _BrandEditScreenState();
}

class _BrandEditScreenState extends State<BrandEditScreen> {
  final _en = TextEditingController();
  final _mr = TextEditingController();
  bool _active = true;
  Uint8List? _photo; // newly picked
  String _photoExt = 'jpg';
  bool _photoRemoved = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.brandId == null
        ? null
        : context.read<AppState>().brandOf(widget.brandId!);
    if (b != null) {
      _en.text = b.name;
      _mr.text = b.nameMr;
      _active = b.active;
    }
  }

  @override
  void dispose() {
    _en.dispose();
    _mr.dispose();
    super.dispose();
  }

  BillPhotoChange get _photoChange => _photo != null
      ? BillPhotoChange.replace(_photo!, _photoExt)
      : _photoRemoved
          ? const BillPhotoChange.remove()
          : const BillPhotoChange.keep();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    final brand = widget.brandId == null ? null : app.brandOf(widget.brandId!);
    final editing = brand != null;
    final products = editing
        ? app.products.where((p) => p.brandId == brand.id).toList()
        : [];
    final withStock = products.where((p) => app.stockOf(p.id).bags > 0).length;
    final whyNoDelete = editing ? app.whyBrandNotDeletable(brand.id) : null;

    Widget label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 5, top: 4),
        child: Text(s,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: c.ink2)));

    return PendScaffold(
      titleMr: editing ? 'ब्रँड संपादन' : 'नवीन ब्रँड',
      titleEn: editing ? 'Edit brand' : 'New brand',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _photoCard(context, brand),
        const SizedBox(height: 14),
        label(L('ब्रँडचे नाव (इंग्रजी) *', 'Brand name (English) *')),
        TextField(
          key: const ValueKey('brand-name'),
          controller: _en,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}), // live letter badge
        ),
        const SizedBox(height: 10),
        Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              label(L('मराठी नाव', 'Marathi name')),
              TextButton(
                  key: const ValueKey('brand-generate-mr'),
                  onPressed: _busy
                      ? null
                      : () => setState(() =>
                          _mr.text = transliterateMarathi(_en.text.trim())),
                  child: Text(L('मराठी नाव बनवा', 'Generate Marathi'))),
            ]),
        TextField(
            key: const ValueKey('brand-name-mr'),
            controller: _mr,
            enabled: !_busy),
        const SizedBox(height: 14),
        InkCard(
          child: SwitchListTile(
            key: const ValueKey('brand-active'),
            title: Text(
                _active ? L('सक्रिय', 'Active') : L('निष्क्रिय', 'Inactive')),
            subtitle: Text(L(
                'निष्क्रिय ब्रँड नवीन विक्री / खरेदीत दिसत नाही; जुनी बिले, साठा व अहवाल तसेच राहतात.',
                'An inactive brand is not offered for new sales / purchases; old bills, stock and reports stay as they are.')),
            value: _active,
            onChanged: _busy ? null : (v) => setState(() => _active = v),
          ),
        ),
        if (editing) ...[
          const SizedBox(height: 8),
          Text(
              L('${products.length} उत्पादने · $withStock साठ्यासह',
                  '${products.length} products · $withStock with stock'),
              style: TextStyle(color: c.ink2)),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('⛔ $_error',
                key: const ValueKey('brand-error'),
                style:
                    TextStyle(color: c.critical, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        BigButton.brand(
            _busy
                ? L('जतन करत आहे…', 'Saving…')
                : L('ब्रँड जतन करा', 'Save Brand'),
            key: const ValueKey('brand-save'),
            onTap: _busy ? null : () => _save(app, brand)),
        if (editing) ...[
          const SizedBox(height: 22),
          if (whyNoDelete == null)
            BigButton.danger('🗑 ${L('ब्रँड हटवा', 'Delete brand')}',
                key: const ValueKey('brand-delete'),
                onTap: _busy ? null : () => _delete(app, brand))
          else ...[
            Text(tr(whyNoDelete),
                key: const ValueKey('brand-delete-blocked'),
                style: TextStyle(color: c.ink2, fontSize: 12.5)),
            if (brand.active && app.hasOwnerRights) ...[
              const SizedBox(height: 8),
              BigButton.ghost('⏸ ${L('ब्रँड निष्क्रिय करा', 'Make Inactive')}',
                  key: const ValueKey('brand-make-inactive'),
                  onTap: _busy ? null : () => _makeInactive(app, brand)),
            ],
          ],
        ],
      ]),
    );
  }

  Widget _photoCard(BuildContext context, Brand? brand) {
    final c = context.c;
    final showSaved =
        _photo == null && !_photoRemoved && brand?.photoUrl != null;
    final has = _photo != null || showSaved;
    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        SizedBox(
          key: const ValueKey('brand-photo-preview'),
          width: 72,
          height: 72,
          child: _photo != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.memory(_photo!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined, size: 32)))
              : BrandLogo(
                  Brand(
                      id: brand?.id ?? '',
                      name: _en.text.isEmpty ? '?' : _en.text,
                      nameMr: _mr.text,
                      active: _active,
                      photoUrl: showSaved ? brand!.photoUrl : null),
                  size: 72),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L('ब्रँड फोटो (ऐच्छिक)', 'Brand photo (optional)'),
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
            Wrap(spacing: 4, children: [
              TextButton.icon(
                  key: const ValueKey('brand-photo-camera'),
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: Text(L('कॅमेरा', 'Camera'))),
              TextButton.icon(
                  key: const ValueKey('brand-photo-gallery'),
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label:
                      Text(has ? L('बदला', 'Replace') : L('गॅलरी', 'Gallery'))),
              if (has)
                TextButton.icon(
                    key: const ValueKey('brand-photo-remove'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _photo = null;
                              _photoRemoved = true;
                            }),
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: c.critical),
                    label: Text(L('काढा', 'Remove'),
                        style: TextStyle(color: c.critical))),
            ]),
          ]),
        ),
      ]),
    );
  }

  Future<void> _pick(ImageSource source) async {
    try {
      Uint8List? bytes;
      var name = 'brand.jpg';
      final hook = BrandEditScreen.debugPickPhoto;
      if (hook != null) {
        final r = await hook(source);
        bytes = r?.bytes;
        name = r?.name ?? name;
      } else {
        final x = await ImagePicker()
            .pickImage(source: source, maxWidth: 800, imageQuality: 82);
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name;
      }
      if (bytes == null || bytes.isEmpty || !mounted) return;
      setState(() {
        _photo = bytes;
        _photoExt = name.contains('.') ? name.split('.').last : 'jpg';
        _photoRemoved = false;
      });
    } catch (_) {
      if (mounted) {
        showToast(context, L('फोटो घेता आला नाही', 'Could not get the photo'));
      }
    }
  }

  Future<void> _save(AppState app, Brand? brand) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = brand == null
        ? await app.createBrand(
            name: _en.text,
            nameMr: _mr.text,
            active: _active,
            photo: _photoChange)
        : await app.updateBrand(brand.id,
            name: _en.text,
            nameMr: _mr.text,
            active: _active,
            photo: _photoChange);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      setState(() => _error = tr(res.error!));
      return;
    }
    showToast(context, L('ब्रँड जतन झाला', 'Brand saved'));
    Navigator.of(context).pop(res.value);
  }

  Future<void> _makeInactive(AppState app, Brand brand) async {
    setState(() => _busy = true);
    final res = await app.updateBrand(brand.id,
        name: brand.name, nameMr: brand.nameMr, active: false);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) _active = false;
      _error = res.ok ? null : tr(res.error!);
    });
    if (res.ok) {
      showToast(context, L('ब्रँड निष्क्रिय केला', 'Brand made inactive'));
    }
  }

  Future<void> _delete(AppState app, Brand brand) async {
    final products = app.products.where((p) => p.brandId == brand.id).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.c.surface,
        title: Text(L('"${brand.name}" हटवायचा?', 'Delete "${brand.name}"?')),
        content: Text(products.isEmpty
            ? L('हा ब्रँड कायमचा हटवला जाईल.',
                'This brand will be deleted permanently.')
            : L('हा ब्रँड आणि त्याची ${products.length} उत्पादने (साठा नाही, बिले नाहीत) कायमची हटवली जातील:\n${products.map((p) => '• ${p.name}').join('\n')}',
                'This brand and its ${products.length} products (no stock, never billed) will be deleted permanently:\n${products.map((p) => '• ${p.name}').join('\n')}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L('रद्द', 'Cancel'))),
          FilledButton(
              key: const ValueKey('brand-delete-confirm'),
              style: FilledButton.styleFrom(backgroundColor: ctx.c.critical),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L('हटवा', 'Delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final error = await app.deleteBrand(brand.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = tr(error));
      return;
    }
    showToast(context, L('ब्रँड हटवला', 'Brand deleted'));
    Navigator.of(context).pop();
  }
}

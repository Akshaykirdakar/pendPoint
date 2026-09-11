import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'product_detail_screen.dart';

/// Scans a product's QR code and opens its product detail page.
///
/// Detection is manual-capture: the camera keeps a code on screen once seen,
/// the cashier confirms it, and only then does the app navigate — so a code
/// glimpsed in passing (someone else's bag, a code on a shelf edge) never
/// silently opens the wrong product.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _navigating = false;
  String? _message;
  Product? _pending; // detected, awaiting the cashier's confirm tap

  bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture, AppState app) async {
    if (_pending != null || _navigating) return; // already awaiting a tap
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (code == null || code.isEmpty) return;

    final product = app.products.where((item) => item.qr == code).firstOrNull;
    if (product == null) {
      setState(() {
        _message = 'This QR code is not in the product catalogue.';
        _pending = null;
      });
      return;
    }

    // Freeze the frame on the found code; wait for the cashier to confirm.
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _message = null;
      _pending = product;
    });
  }

  Future<void> _confirm() async {
    final product = _pending;
    if (product == null || _navigating) return;
    _navigating = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: product.id)),
    );
  }

  Future<void> _rescan() async {
    setState(() {
      _pending = null;
      _message = null;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.c;
    return PendScaffold(
      titleMr: 'QR स्कॅन',
      titleEn: 'Scan product',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_cameraSupported)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 260,
              child: Stack(children: [
                MobileScanner(onDetect: (capture) => _onDetect(capture, app)),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 175,
                      height: 175,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.accent, width: 3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(children: [
                    IconButton.filledTonal(
                      tooltip: 'Toggle torch',
                      onPressed: _controller.toggleTorch,
                      icon: const Icon(Icons.flashlight_on_outlined),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Switch camera',
                      onPressed: _controller.switchCamera,
                      icon: const Icon(Icons.cameraswitch_outlined),
                    ),
                  ]),
                ),
              ]),
            ),
          )
        else
          const _UnsupportedCamera(),
        const SizedBox(height: 14),
        if (_pending != null)
          _PendingConfirmCard(
              product: _pending!, onConfirm: _confirm, onRescan: _rescan)
        else ...[
          Text(
            'कॅमेरा QR कडे धरा, मग कन्फर्म करा · Point the camera at a product QR, then confirm.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.ink2, fontSize: 13),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: TextStyle(color: c.critical, fontSize: 12)),
          ],
        ],
        const SizedBox(height: 14),
        Text(
          'Manual fallback',
          style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.35,
          mainAxisSpacing: 11,
          crossAxisSpacing: 11,
          children: [
            for (final product in app.products)
              InkWell(
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(productId: product.id),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      QrImageView(
                        data: product.qr,
                        size: 60,
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        product.nameMr,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: baloo(
                          size: 12,
                          weight: FontWeight.w700,
                          color: const Color(0xFF111111),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

/// Shown once a QR is detected: freezes the frame and asks the cashier to
/// confirm before opening the product (manual-capture, not auto-navigate).
class _PendingConfirmCard extends StatelessWidget {
  final Product product;
  final VoidCallback onConfirm;
  final VoidCallback onRescan;
  const _PendingConfirmCard(
      {required this.product, required this.onConfirm, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.good.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.good.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${product.nameMr} सापडले · Found',
              style: baloo(size: 15, weight: FontWeight.w700, color: c.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 3),
        Text('${money(product.fullBagPrice)} · ${money(product.perKgPrice)}/kg',
            style: TextStyle(color: c.ink2, fontSize: 12.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: BigButton.ghost('↺ पुन्हा · Rescan', onTap: onRescan)),
          const SizedBox(width: 10),
          Expanded(
              child: BigButton.brand('उघडा · Open', onTap: onConfirm)),
        ]),
      ]),
    );
  }
}

class _UnsupportedCamera extends StatelessWidget {
  const _UnsupportedCamera();

  @override
  Widget build(BuildContext context) => Container(
        height: 220,
        decoration: BoxDecoration(
          color: context.c.surface2,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: const EmptyState(
          '📷',
          'Camera scanning is available on Android, iOS, macOS, and web.',
        ),
      );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../state/app_state.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';
import 'product_detail_screen.dart';

/// Scans a product's QR code and opens its product detail page.
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
  bool _openingProduct = false;
  String? _message;

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
    if (_openingProduct) return;
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (code == null || code.isEmpty) return;

    final product = app.products.where((item) => item.qr == code).firstOrNull;
    if (product == null) {
      setState(
          () => _message = 'This QR code is not in the product catalogue.');
      return;
    }

    _openingProduct = true;
    await _controller.stop();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: product.id)),
    );
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
        Text(
          'कॅमेरा QR कडे धरा · Point the camera at a product QR.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.ink2, fontSize: 13),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: TextStyle(color: c.critical, fontSize: 12)),
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

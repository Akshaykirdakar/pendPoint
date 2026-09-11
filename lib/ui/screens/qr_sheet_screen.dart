import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../state/app_state.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../widgets/common.dart';
import '../widgets/pend_scaffold.dart';

/// Printable QR grid — paste one code under each product on the shelf.
/// TODO (print): render this grid to a PDF (printing package) or image for
///  export.
class QrSheetScreen extends StatelessWidget {
  const QrSheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PendScaffold(
      titleMr: 'QR शीट',
      titleEn: 'QR sheet',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'छापण्यायोग्य QR कॅटलॉग · Scanning a code opens that product at the counter.',
            style: TextStyle(color: context.c.ink2, fontSize: 13)),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.82,
          mainAxisSpacing: 11,
          crossAxisSpacing: 11,
          children: [
            for (final p in app.products)
              Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.c.line)),
                padding: const EdgeInsets.all(10),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      QrImageView(
                          data: p.qr, size: 96, padding: EdgeInsets.zero),
                      const SizedBox(height: 8),
                      Text(p.nameMr,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: baloo(
                              size: 12,
                              weight: FontWeight.w700,
                              color: const Color(0xFF111111))),
                      Text(
                          '${money(p.fullBagPrice)} · ${money(p.perKgPrice)}/kg',
                          style: const TextStyle(
                              fontSize: 10.5, color: Color(0xFF444444))),
                    ]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        BigButton.brand('🖨️ शीट छापा · Export sheet',
            onTap: () => showToast(
                context, 'QR शीट PDF म्हणून तयार · QR sheet exported')),
      ]),
    );
  }
}

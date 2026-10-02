// Localization + small-phone audit: renders every screen (and the main
// dialogs / pickers) in Marathi-only and English-only mode on a 360×640
// phone, and fails if any app-generated text is in the other language or
// if anything overflows. Customer, supplier, product, brand, branch, staff,
// shop names and codes are data, so they are ignored wherever they appear.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pend_point/models/app_settings.dart';
import 'package:pend_point/models/bill.dart';
import 'package:pend_point/models/enums.dart';
import 'package:pend_point/state/app_state.dart';
import 'package:pend_point/state/purchase_draft.dart';
import 'package:pend_point/state/report_query.dart';
import 'package:pend_point/ui/root_shell.dart';
import 'package:pend_point/ui/screens/alerts_screen.dart';
import 'package:pend_point/ui/screens/bag_stock_screen.dart';
import 'package:pend_point/ui/screens/batch_report_screen.dart';
import 'package:pend_point/ui/screens/bill_screen.dart';
import 'package:pend_point/ui/screens/branch_edit_screen.dart';
import 'package:pend_point/ui/screens/branches_screen.dart';
import 'package:pend_point/ui/screens/cart_screen.dart';
import 'package:pend_point/ui/screens/catalogue_screen.dart';
import 'package:pend_point/ui/screens/checkout_screen.dart';
import 'package:pend_point/ui/screens/customer_screen.dart';
import 'package:pend_point/ui/screens/draft_bills_screen.dart';
import 'package:pend_point/ui/screens/history_screen.dart';
import 'package:pend_point/ui/screens/party_edit_screen.dart';
import 'package:pend_point/ui/screens/party_master_screen.dart';
import 'package:pend_point/ui/screens/payment_method_transactions_screen.dart';
import 'package:pend_point/ui/screens/payment_mix_screen.dart';
import 'package:pend_point/ui/screens/payment_reminder_screen.dart';
import 'package:pend_point/ui/screens/product_detail_screen.dart';
import 'package:pend_point/ui/screens/product_edit_screen.dart';
import 'package:pend_point/ui/screens/product_history_screen.dart';
import 'package:pend_point/ui/screens/purchase_detail_screen.dart';
import 'package:pend_point/ui/screens/purchase_entry_screen.dart';
import 'package:pend_point/ui/screens/purchases_screen.dart';
import 'package:pend_point/ui/screens/qr_sheet_screen.dart';
import 'package:pend_point/ui/screens/quantity_analytics_screen.dart';
import 'package:pend_point/ui/screens/reports_screen.dart';
import 'package:pend_point/ui/screens/returns_screen.dart';
import 'package:pend_point/ui/screens/revenue_analytics_screen.dart';
import 'package:pend_point/ui/screens/sales_entry_screen.dart';
import 'package:pend_point/ui/screens/stock_in_screen.dart';
import 'package:pend_point/ui/screens/stock_transfer_screen.dart';
import 'package:pend_point/ui/screens/supplier_edit_screen.dart';
import 'package:pend_point/ui/screens/suppliers_screen.dart';
import 'package:pend_point/ui/widgets/common.dart' show noteLabel;
import 'package:pend_point/utils/lang.dart';
import 'package:pend_point/utils/theme.dart';

import 'test_support.dart';

/// Words that are the same in both languages in this shop (units, brands
/// of payment/messaging apps, codes).
const _neutral = ['kg', 'KG', 'UPI', 'QR', 'PIN', 'WhatsApp', 'SMS', 'PDF', 'Excel', 'GSTIN', 'Point', 'ID'];

final _dev = RegExp(r'[ऀ-ॿ]');
final _latinWord = RegExp(r'[A-Za-z]{2,}');

List<String> _names(AppState app) {
  final out = <String>{
    app.settings.shop,
    'पेंड Point', // app name
    for (final p in app.products) ...[p.name, p.nameMr, p.qr, if (p.category != null) p.category!],
    for (final b in app.brands) ...[b.name, b.nameMr],
    for (final c in app.customers) ...[c.name, c.mobile, c.address],
    for (final s in app.suppliers) ...[s.name, s.address, s.email, s.gstin],
    for (final b in app.branches) ...[b.name, b.nameMr, b.address],
    for (final s in app.staff) ...[s.name, s.email ?? ''],
    for (final b in app.batches) b.batchNo,
    for (final p in app.purchases) p.supplierBillNo,
    // Notes a person typed are data; notes the app writes are translated
    // for display by noteLabel(), so only untranslated ones are exempt.
    for (final l in app.logs)
      if (l.note != null && noteLabel(l.note!) == l.note) l.note!,
    for (final c in app.customers)
      for (final e in c.ledger)
        if (e.note != null && noteLabel(e.note!) == e.note) e.note!,
  }..removeWhere((s) => s.trim().isEmpty);
  return out.toList()..sort((a, b) => b.length.compareTo(a.length));
}

String _strip(String t, List<String> names) {
  var s = t;
  for (final n in names) {
    s = s.replaceAll(n, ' ');
  }
  s = s.replaceAll(RegExp(r'\d\s?kg\b'), ' ');
  for (final n in _neutral) {
    s = s.replaceAll(RegExp('\\b$n\\b'), ' ');
  }
  // weekday / month abbreviations produced by date formatting
  s = s.replaceAll(
      RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Mo|Tu|We|Th|Fr|Sa|Su|AM|PM)\b'),
      ' ');
  return s;
}

/// Shop data every audited screen needs: a purchase, a saved credit bill.
class _Ctx {
  final AppState app;
  final String pid;
  final String billId;
  final String purchaseId;
  final ReportFilter filter;
  final ReportResult report;
  _Ctx(this.app, this.pid, this.billId, this.purchaseId, this.filter, this.report);
}

Future<_Ctx> _setUp(WidgetTester tester, AppLang lang) async {
  final app = (await tester.runAsync(bootedApp))!;
  await tester.runAsync(() => app.updateSettings((s) => s.lang = lang));
  final pid = app.products.first.id;
  await tester.runAsync(() => app.savePurchase(
      supplierId: app.suppliers.first.id,
      supplierBillNo: 'INV-9',
      lines: [
        PurchaseLineInput(
            productId: pid, bags: 5, rate: 1000, batchNo: 'AUD-1', expiry: inDays(60))
      ],
      otherCharges: 50));
  app.addToCart(pid, SaleType.bag, 2);
  app.setCartCustomer('c1');
  app.payments
    ..clear()
    ..add(Payment(PayMode.credit, app.cartTotal));
  final bill = (await tester.runAsync(app.finalizeSale))!.bill!;
  final filter = ReportFilter.preset(DateRangePresetKind.last30);
  return _Ctx(app, pid, bill.id, app.purchases.first.id, filter,
      buildReport(bills: app.finalBills, products: app.products, filter: filter));
}

/// What each audit case shows: a screen, optionally followed by a tap that
/// opens a dialog / sheet / picker on it.
typedef _Case = ({Widget Function(_Ctx) screen, Finder Function(AppLang)? open, void Function(_Ctx)? prep});

final Map<String, _Case> _cases = {
  'shell': (screen: (_) => const RootShell(), open: null, prep: null),
  'tab sell': (screen: (_) => const RootShell(), open: (l) => find.text(l == AppLang.en ? 'Sell' : 'विक्री'), prep: null),
  'tab stock': (screen: (_) => const RootShell(), open: (l) => find.text(l == AppLang.en ? 'Stock' : 'साठा'), prep: null),
  'tab khata': (screen: (_) => const RootShell(), open: (l) => find.text(l == AppLang.en ? 'Credit' : 'खाते').last, prep: null),
  'tab more': (screen: (_) => const RootShell(), open: (l) => find.text(l == AppLang.en ? 'More' : 'अधिक').last, prep: null),
  'alerts': (screen: (_) => const AlertsScreen(), open: null, prep: null),
  'bag stock': (screen: (_) => const BagStockScreen(), open: null, prep: null),
  'batch report': (screen: (_) => const BatchReportScreen(), open: null, prep: null),
  'bill saved': (screen: (c) => BillScreen(billId: c.billId, justSaved: true), open: null, prep: null),
  'bill void dialog': (screen: (c) => BillScreen(billId: c.billId), open: (_) => find.byKey(const ValueKey('bill-void')), prep: null),
  'branch edit': (screen: (c) => BranchEditScreen(branchId: c.app.branches.first.id), open: null, prep: null),
  'branches': (screen: (_) => const BranchesScreen(), open: null, prep: null),
  'catalogue': (screen: (_) => const CatalogueScreen(), open: null, prep: null),
  'customer': (screen: (_) => const CustomerScreen(customerId: 'c1'), open: null, prep: null),
  'history': (screen: (_) => const HistoryScreen(), open: null, prep: null),
  'party new': (screen: (_) => const PartyEditScreen(), open: null, prep: null),
  'party edit': (screen: (_) => const PartyEditScreen(partyId: 'c1'), open: null, prep: null),
  'party master': (screen: (_) => const PartyMasterScreen(), open: null, prep: null),
  'payment txns': (screen: (c) => PaymentMethodTransactionsScreen(filter: c.filter, mode: PayMode.credit), open: null, prep: null),
  'payment mix': (screen: (c) => PaymentMixScreen(result: c.report), open: null, prep: null),
  'product detail': (screen: (c) => ProductDetailScreen(productId: c.pid), open: null, prep: null),
  'product edit': (screen: (c) => ProductEditScreen(productId: c.pid), open: null, prep: null),
  'product history': (screen: (c) => ProductHistoryScreen(productId: c.pid, filter: c.filter), open: null, prep: null),
  'purchase detail': (screen: (c) => PurchaseDetailScreen(purchaseId: c.purchaseId), open: null, prep: null),
  'purchase void dialog': (screen: (c) => PurchaseDetailScreen(purchaseId: c.purchaseId), open: (_) => find.byKey(const ValueKey('purchase-void')), prep: null),
  'purchase entry': (screen: (c) => PurchaseEntryScreen(productId: c.pid), open: null, prep: null),
  'purchase save errors': (screen: (_) => const PurchaseEntryScreen(), open: (_) => find.byKey(const ValueKey('purchase-save')), prep: null),
  'purchase party picker': (screen: (_) => const PurchaseEntryScreen(), open: (_) => find.byKey(const ValueKey('purchase-party')), prep: null),
  'purchases': (screen: (_) => const PurchasesScreen(), open: null, prep: null),
  'qr sheet': (screen: (_) => const QrSheetScreen(), open: null, prep: null),
  'qty analytics': (screen: (c) => QuantityAnalyticsScreen(filter: c.filter, kind: SaleTypeFilter.bags), open: null, prep: null),
  'reports': (screen: (_) => const ReportsScreen(), open: null, prep: null),
  'bills list': (screen: (_) => const ReturnsScreen(), open: null, prep: null),
  'partial return sheet': (screen: (_) => const ReturnsScreen(), open: (l) => find.textContaining(l == AppLang.en ? 'Return' : 'परतावा'), prep: null),
  'revenue analytics': (screen: (c) => RevenueAnalyticsScreen(filter: c.filter), open: null, prep: null),
  'stock in': (screen: (c) => StockInScreen(productId: c.pid), open: null, prep: null),
  'stock transfer': (screen: (_) => const StockTransferScreen(), open: null, prep: null),
  'supplier edit': (screen: (c) => SupplierEditScreen(supplierId: c.app.suppliers.first.id), open: null, prep: null),
  'suppliers': (screen: (_) => const SuppliersScreen(), open: null, prep: null),
  'cart': (screen: (_) => const CartScreen(), open: null, prep: (c) => c.app.addToCart(c.pid, SaleType.bag, 1)),
  'checkout': (screen: (_) => const CheckoutScreen(), open: null, prep: (c) => c.app.addToCart(c.pid, SaleType.bag, 1)),
  'checkout party picker': (screen: (_) => const CheckoutScreen(), open: (_) => find.byKey(const ValueKey('checkout-party')), prep: (c) => c.app.addToCart(c.pid, SaleType.bag, 1)),
  'sales entry': (screen: (_) => const SalesEntryScreen(), open: null, prep: (c) => c.app.addToCart(c.pid, SaleType.bag, 1)),
  'rate sheet': (screen: (_) => const CartScreen(), open: (_) => find.byIcon(Icons.currency_rupee), prep: (c) => c.app.addToCart(c.pid, SaleType.bag, 1)),
  'product picker': (screen: (_) => const SalesEntryScreen(), open: (_) => find.byKey(const ValueKey('sales-next-product')), prep: null),
  'brand picker': (screen: (_) => const SalesEntryScreen(), open: (_) => find.byKey(const ValueKey('sales-brand-filter')), prep: null),
  'sales party picker': (screen: (_) => const SalesEntryScreen(), open: (_) => find.byKey(const ValueKey('sales-party')), prep: null),
  'sales entry (split)': (screen: (_) => const SalesEntryScreen(), open: null, prep: (c) { c.app.addToCart(c.pid, SaleType.bag, 1); c.app.setCartCustomer('c1'); c.app.addSplitPayment(); }),
  'sales entry (credit, no customer)': (screen: (_) => const SalesEntryScreen(), open: (_) => find.byKey(const ValueKey('sale-pay-credit')), prep: (c) => c.app.addToCart(c.pid, SaleType.bag, 1)),
  'draft saved dialog': (screen: (_) => const SalesEntryScreen(), open: (_) => find.byKey(const ValueKey('sales-save-draft')), prep: (c) => c.app.addToCart(c.pid, SaleType.bag, 1)),
  'sales entry (previous due added)': (screen: (_) => const SalesEntryScreen(), open: null, prep: (c) { c.app.setCartCustomer('c1'); c.app.addToCart(c.pid, SaleType.bag, 1); c.app.setDueCollect(500); }),
  'bill saved (previous due)': (screen: (c) => BillScreen(billId: c.app.bills.first.id, justSaved: true), open: null, prep: null),
  'payment reminder': (screen: (_) => const PaymentReminderScreen(), open: (_) => find.byKey(const ValueKey('remind-select-all')), prep: null),
  'customer (reminder buttons)': (screen: (_) => const CustomerScreen(customerId: 'c1'), open: null, prep: null),
  'draft bills': (screen: (_) => const DraftBillsScreen(), open: null, prep: _draft),
  'draft delete dialog': (screen: (_) => const DraftBillsScreen(), open: (_) => find.byKey(const ValueKey('draft-delete-DRAFT1001')), prep: _draft),
  'sales entry (draft)': (screen: (_) => const SalesEntryScreen(), open: null, prep: _draft),
  'bills list (drafts)': (screen: (_) => const ReturnsScreen(), open: null, prep: _draft),
  'checkout (draft)': (screen: (_) => const CheckoutScreen(), open: null, prep: _draft),
};

/// A saved draft (party, product) left open on screen.
void _draft(_Ctx c) {
  c.app.setCartCustomer('c1');
  c.app.addToCart(c.pid, SaleType.bag, 1);
  unawaited(c.app.saveDraft());
}

List<String> _findings(WidgetTester tester, AppLang lang, List<String> names) {
  final out = <String>{};
  final texts = <String>[];
  for (final e in find.byType(Text, skipOffstage: false).evaluate()) {
    final w = e.widget as Text;
    texts.add(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  for (final e in find.byType(Tooltip, skipOffstage: false).evaluate()) {
    texts.add((e.widget as Tooltip).message ?? '');
  }
  for (final t in texts) {
    final s = _strip(t, names);
    final bad = lang == AppLang.mr ? _latinWord.hasMatch(s) : _dev.hasMatch(s);
    if (bad) out.add(t);
  }
  return out.toList()..sort();
}

void main() {
  tearDown(() => appLang = AppLang.both);
  for (final lang in [AppLang.mr, AppLang.en]) {
    for (final e in _cases.entries) {
      testWidgets('[${lang.name}] ${e.key}: one language, fits 360px', (tester) async {
        tester.view.physicalSize = const Size(720, 1280);
        tester.view.devicePixelRatio = 2.0; // 360 × 640 dp
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ctx = await _setUp(tester, lang);
        e.value.prep?.call(ctx);
        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: ctx.app,
          child: MaterialApp(
              theme: buildTheme(Brightness.light), home: e.value.screen(ctx)),
        ));
        await tester.pumpAndSettle();
        final open = e.value.open?.call(lang);
        if (open != null) {
          expect(open, findsWidgets, reason: 'control that opens the ${e.key}');
          await tester.ensureVisible(open.first);
          await tester.tap(open.first, warnIfMissed: false);
          await tester.pumpAndSettle();
        }
        final wrong = _findings(tester, lang, _names(ctx.app));
        for (final w in wrong) {
          // ignore: avoid_print
          print('AUDIT ${lang.name} | ${e.key} | $w');
        }
        expect(wrong, isEmpty,
            reason: 'text in the wrong language on ${e.key}');
      });
    }
  }
}

import '../models/app_settings.dart';
import '../models/batch.dart';
import '../models/bill.dart';
import '../models/branch.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/product.dart';
import '../models/staff.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';
import '../models/supplier.dart';
import 'repository.dart';

DateTime _daysAgo(int n) {
  final d = DateTime.now().subtract(Duration(days: n));
  return DateTime(d.year, d.month, d.day, 10 + (n * 3) % 8, (n * 13) % 60);
}

DateTime _daysAhead(int n) => DateTime.now().add(Duration(days: n));

/// A realistic sample shop so the app runs and demos immediately without a
/// backend. Mirrors the interactive prototype.
Snapshot buildSeed() {
  final brands = [
    const Brand(id: 'b1', name: 'Godrej', nameMr: 'गोदरेज'),
    const Brand(id: 'b2', name: 'Kargil', nameMr: 'कारगिल'),
    const Brand(id: 'b3', name: 'Local / सुटे', nameMr: 'स्थानिक'),
  ];

  final branches = [
    const Branch(
        id: 'br1', name: 'Pune', nameMr: 'पुणे', address: 'FC Road, Pune'),
  ];

  final suppliers = [
    Supplier(
        id: 'sup1',
        name: 'ABC Traders',
        mobile: '98765 43210',
        address: 'APMC Market, Pune',
        active: true,
        createdAt: _daysAgo(400)),
    Supplier(
        id: 'sup2',
        name: 'XYZ Traders',
        mobile: '90123 45678',
        address: 'Market Yard, Pune',
        active: true,
        createdAt: _daysAgo(380)),
    Supplier(
        id: 'sup3',
        name: 'Godrej Distributor',
        mobile: '99887 76655',
        gstin: '27AAAAA0000A1Z5',
        active: true,
        createdAt: _daysAgo(500)),
    Supplier(
        id: 'sup4',
        name: 'Local mill',
        mobile: '88990 01122',
        active: true,
        createdAt: _daysAgo(300)),
  ];

  final products = [
    const Product(
        id: 'p1',
        brandId: 'b1',
        name: 'Milk Booster',
        nameMr: 'दूध बूस्टर पेंड',
        swatch: '🟩',
        bagWeightKg: 50,
        fullBagPrice: 1450,
        perKgPrice: 31,
        costPrice: 1300,
        minPriceFloor: 1350,
        lowStockThresholdBags: 5,
        qr: 'PEND-P1', branchIds: ['br1']),
    const Product(
        id: 'p2',
        brandId: 'b1',
        name: 'Premium Feed',
        nameMr: 'प्रीमियम खुराक',
        swatch: '🟢',
        bagWeightKg: 50,
        fullBagPrice: 1320,
        perKgPrice: 28,
        costPrice: 1180,
        minPriceFloor: 1240,
        lowStockThresholdBags: 5,
        qr: 'PEND-P2', branchIds: ['br1']),
    const Product(
        id: 'p3',
        brandId: 'b2',
        name: 'Kargil Gold',
        nameMr: 'कारगिल गोल्ड',
        swatch: '🟨',
        bagWeightKg: 50,
        fullBagPrice: 1250,
        perKgPrice: 27,
        costPrice: 1120,
        minPriceFloor: 1170,
        lowStockThresholdBags: 6,
        qr: 'PEND-P3', branchIds: ['br1']),
    const Product(
        id: 'p4',
        brandId: 'b2',
        name: 'Buffalo Special',
        nameMr: 'म्हैस स्पेशल',
        swatch: '🟫',
        bagWeightKg: 45,
        fullBagPrice: 1180,
        perKgPrice: 28,
        costPrice: 1040,
        minPriceFloor: 1090,
        lowStockThresholdBags: 5,
        qr: 'PEND-P4', branchIds: ['br1']),
    const Product(
        id: 'p5',
        brandId: 'b3',
        name: 'Cotton Cake / सरकी',
        nameMr: 'सरकी पेंड',
        swatch: '⬜',
        bagWeightKg: 40,
        fullBagPrice: 960,
        perKgPrice: 26,
        costPrice: 850,
        minPriceFloor: 900,
        lowStockThresholdBags: 8,
        qr: 'PEND-P5', branchIds: ['br1']),
    const Product(
        id: 'p6',
        brandId: 'b3',
        name: 'Groundnut Cake / भुईमूग',
        nameMr: 'भुईमूग पेंड',
        swatch: '🟧',
        bagWeightKg: 40,
        fullBagPrice: 1040,
        perKgPrice: 28,
        costPrice: 930,
        minPriceFloor: 980,
        lowStockThresholdBags: 6,
        qr: 'PEND-P6', branchIds: ['br1']),
  ];

  // Stock rollups equal the sum of the batches below for each product. The
  // extra bag on p4 is the
  // deliberately-expired batch8, still physically on the shelf).
  final stock = <String, Stock>{
    'p1': Stock(productId: 'p1', bags: 48, looseKg: 12),
    'p2': Stock(productId: 'p2', bags: 4, looseKg: 22),
    'p3': Stock(productId: 'p3', bags: 21, looseKg: 0),
    'p4': Stock(productId: 'p4', bags: 3, looseKg: 8),
    'p5': Stock(productId: 'p5', bags: 0, looseKg: 17),
    'p6': Stock(productId: 'p6', bags: 14, looseKg: 5),
  };

  // Real, depletable batches backing the [stock] rollup above — see the
  // reviewed batch/expiry architecture. One batch (b8) is deliberately expired
  // to exercise the "cannot sell expired stock" rule out of the box.
  final batches = [
    Batch(
        id: 'batch1',
        branchId: 'br1',
        productId: 'p1',
        supplierId: 'sup3',
        batchNo: 'GJ-2609',
        expiry: _daysAhead(120),
        unitCost: 1300,
        bagsReceived: 40,
        bagsAvailable: 38,
        looseKgAvailable: 12,
        bagsSold: 2,
        createdAt: _daysAgo(10),
        updatedAt: _daysAgo(1)),
    Batch(
        id: 'batch2',
        branchId: 'br1',
        productId: 'p2',
        supplierId: 'sup1',
        batchNo: 'PF-2201',
        expiry: _daysAhead(60),
        unitCost: 1180,
        bagsReceived: 5,
        bagsAvailable: 4,
        looseKgAvailable: 22,
        bagsSold: 1,
        createdAt: _daysAgo(18),
        updatedAt: _daysAgo(4)),
    Batch(
        id: 'batch3',
        branchId: 'br1',
        productId: 'p3',
        supplierId: 'sup2',
        batchNo: 'KG-0110',
        expiry: _daysAhead(200),
        unitCost: 1120,
        bagsReceived: 21,
        bagsAvailable: 21,
        createdAt: _daysAgo(15),
        updatedAt: _daysAgo(15)),
    Batch(
        id: 'batch4',
        branchId: 'br1',
        productId: 'p4',
        supplierId: 'sup2',
        batchNo: 'BS-0005',
        expiry: _daysAhead(90),
        unitCost: 1040,
        bagsReceived: 2,
        bagsAvailable: 2,
        looseKgAvailable: 8,
        createdAt: _daysAgo(12),
        updatedAt: _daysAgo(12)),
    Batch(
        id: 'batch5',
        branchId: 'br1',
        productId: 'p5',
        supplierId: 'sup4',
        batchNo: 'CC-0002',
        expiry: _daysAhead(45),
        unitCost: 850,
        bagsReceived: 1,
        looseKgAvailable: 17,
        createdAt: _daysAgo(14),
        updatedAt: _daysAgo(2)),
    Batch(
        id: 'batch6',
        branchId: 'br1',
        productId: 'p6',
        supplierId: 'sup4',
        batchNo: 'LC-118',
        expiry: _daysAhead(25), // near-expiry demo, per spec §10
        unitCost: 930,
        bagsReceived: 15,
        bagsAvailable: 14,
        looseKgAvailable: 5,
        bagsSold: 1,
        createdAt: _daysAgo(8),
        updatedAt: _daysAgo(0)),
    // A separate lot for the same product.
    Batch(
        id: 'batch7',
        branchId: 'br1',
        productId: 'p1',
        supplierId: 'sup3',
        batchNo: 'GJ-2610',
        expiry: _daysAhead(10),
        unitCost: 1310,
        bagsReceived: 10,
        bagsAvailable: 10,
        createdAt: _daysAgo(3),
        updatedAt: _daysAgo(3)),
    // Already expired, still holding stock — exercises "expired batches must
    // never silently remain available for sale" (spec §9) without needing a
    // fresh Stock In first.
    Batch(
        id: 'batch8',
        branchId: 'br1',
        productId: 'p4',
        supplierId: 'sup1',
        batchNo: 'BS-0000',
        expiry: _daysAgo(3),
        unitCost: 1000,
        bagsReceived: 1,
        bagsAvailable: 1,
        createdAt: _daysAgo(60),
        updatedAt: _daysAgo(60)),
  ];

  final customers = [
    Customer(
        id: 'c1',
        name: 'रमेश पाटील',
        mobile: '98220 11223',
        outstanding: 2380,
        ledger: [
          LedgerEntry(
              type: 'credit-sale',
              amount: 1450,
              note: '1 bag Milk Booster',
              at: _daysAgo(9)),
          LedgerEntry(
              type: 'credit-sale',
              amount: 1330,
              note: 'Premium + सरकी',
              at: _daysAgo(4)),
          LedgerEntry(
              type: 'repayment', amount: 400, note: 'cash', at: _daysAgo(1)),
        ]),
    Customer(
        id: 'c2',
        name: 'सुनिल जाधव',
        mobile: '90280 44556',
        outstanding: 0,
        ledger: [
          LedgerEntry(
              type: 'credit-sale',
              amount: 1250,
              note: 'Kargil Gold',
              at: _daysAgo(20)),
          LedgerEntry(
              type: 'repayment', amount: 1250, note: 'UPI', at: _daysAgo(6)),
        ]),
    Customer(
        id: 'c3',
        name: 'Dnyaneshwar F.',
        mobile: '70301 99881',
        outstanding: 960,
        ledger: [
          LedgerEntry(
              type: 'credit-sale',
              amount: 960,
              note: 'सरकी पेंड',
              at: _daysAgo(2)),
        ]),
  ];

  final staff = [
    const Staff(
        id: 's1',
        name: 'Owner / मालक',
        role: 'admin',
        canOverride: true,
        maxDiscountPct: 100,
        pin: '1234'),
    const Staff(
        id: 's2',
        name: 'काउंटर स्टाफ',
        role: 'staff',
        canOverride: true,
        maxDiscountPct: 5,
        pin: '1111'),
  ];

  // Sample bills across the last 7 days.
  final bills = <Bill>[];
  int num = 1000;
  Product byId(String id) => products.firstWhere((p) => p.id == id);

  void mk(int dayOffset, List<(String, SaleType, double, double?)> lines,
      PayMode pay,
      {String? custId}) {
    num++;
    double subtotal = 0, disc = 0;
    final items = <BillItem>[];
    for (final l in lines) {
      final p = byId(l.$1);
      final cat = l.$2 == SaleType.bag ? p.fullBagPrice : p.perKgPrice;
      final rate = l.$4 ?? cat;
      final line = rate * l.$3;
      subtotal += line;
      disc += (cat - rate) * l.$3;
      items.add(BillItem(
          productId: l.$1,
          saleType: l.$2,
          qty: l.$3,
          catalogRate: cat,
          rate: rate,
          lineTotal: line));
    }
    bills.add(Bill(
      id: 'BILL$num',
      billNumber: num,
      customerId: custId,
      customerName: custId != null
          ? customers.firstWhere((c) => c.id == custId).name
          : '',
      items: items,
      subtotal: subtotal,
      discountTotal: disc,
      total: subtotal,
      payments: [Payment(pay, subtotal)],
      at: _daysAgo(dayOffset),
      staffId: 's1',
    ));
  }

  mk(6, [('p1', SaleType.bag, 1, null), ('p5', SaleType.kg, 6, null)],
      PayMode.cash);
  mk(5, [('p3', SaleType.bag, 2, null)], PayMode.upi);
  mk(4, [('p6', SaleType.bag, 1, null), ('p2', SaleType.kg, 4, 26)],
      PayMode.cash);
  mk(3, [('p1', SaleType.bag, 1, null)], PayMode.cash);
  mk(2, [('p4', SaleType.kg, 10, null), ('p3', SaleType.bag, 1, null)],
      PayMode.upi);
  mk(1, [('p5', SaleType.kg, 12, null)], PayMode.credit, custId: 'c3');
  mk(0, [('p1', SaleType.bag, 2, 1400), ('p6', SaleType.kg, 5, null)],
      PayMode.cash);
  mk(0, [('p2', SaleType.bag, 1, null)], PayMode.upi);

  final logs = [
    StockLog(
        id: 'L1',
        productId: 'p1',
        type: StockLogType.purchase,
        bagsDelta: 40,
        cost: 1300,
        batchNo: 'GJ-2609',
        expiry: _daysAhead(120),
        supplier: 'Godrej Distributor',
        at: _daysAgo(10)),
    StockLog(
        id: 'L2',
        productId: 'p6',
        type: StockLogType.purchase,
        bagsDelta: 15,
        cost: 930,
        batchNo: 'LC-118',
        expiry: _daysAhead(25),
        supplier: 'Local mill',
        note: 'near expiry',
        at: _daysAgo(8)),
    StockLog(
        id: 'L3',
        productId: 'p2',
        type: StockLogType.bagOpened,
        bagsDelta: -1,
        looseKgDelta: 50,
        note: 'opened for kg sale',
        at: _daysAgo(4)),
  ];

  return Snapshot(
    brands: brands,
    branches: branches,
    suppliers: suppliers,
    products: products,
    stock: stock,
    batches: batches,
    logs: logs,
    bills: bills,
    customers: customers,
    staff: staff,
    settings: AppSettings(),
    billCounter: num,
  );
}

import admin from 'firebase-admin';

const ownerEmail = process.env.PEND_OWNER_EMAIL?.trim();
const force = process.argv.includes('--force');

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS to a Firebase service-account JSON file.');
}
if (!ownerEmail) {
  throw new Error('Set PEND_OWNER_EMAIL to the existing Firebase Auth owner email.');
}

admin.initializeApp({credential: admin.credential.applicationDefault()});
const db = admin.firestore();
const existing = await db.collection('products').limit(1).get();
if (!existing.empty && !force) {
  throw new Error('Firestore already has products. Refusing to overwrite; rerun with --force only if intended.');
}

const owner = await admin.auth().getUserByEmail(ownerEmail);
await admin.auth().setCustomUserClaims(owner.uid, {
  ...owner.customClaims,
  role: 'admin',
});

const brands = [
  ['b1', {name: 'Godrej', nameMr: 'गोदरेज'}],
  ['b2', {name: 'Kargil', nameMr: 'कारगिल'}],
  ['b3', {name: 'Local / सुटे', nameMr: 'स्थानिक'}],
];

const products = [
  ['p1', 'b1', 'Milk Booster', 'दूध बूस्टर पेंड', '🟩', 50, 1450, 31, 1300, 1350, 5, 'PEND-P1', 38, 12],
  ['p2', 'b1', 'Premium Feed', 'प्रीमियम खुराक', '🟢', 50, 1320, 28, 1180, 1240, 5, 'PEND-P2', 4, 22],
  ['p3', 'b2', 'Kargil Gold', 'कारगिल गोल्ड', '🟨', 50, 1250, 27, 1170, 1170, 6, 'PEND-P3', 21, 0],
  ['p4', 'b2', 'Buffalo Special', 'म्हैस स्पेशल', '🟫', 45, 1180, 28, 1040, 1090, 5, 'PEND-P4', 2, 8],
  ['p5', 'b3', 'Cotton Cake / सरकी', 'सरकी पेंड', '⬜', 40, 960, 26, 850, 900, 8, 'PEND-P5', 0, 17],
  ['p6', 'b3', 'Groundnut Cake / भुईमूग', 'भुईमूग पेंड', '🟧', 40, 1040, 28, 930, 980, 6, 'PEND-P6', 14, 5],
];

const customers = [
  ['c1', 'रमेश पाटील', '98220 11223', 2380],
  ['c2', 'सुनील जाधव', '90280 44556', 0],
  ['c3', 'Dnyaneshwar F.', '70301 99881', 960],
];

const batch = db.batch();
for (const [id, data] of brands) batch.set(db.doc(`brands/${id}`), data, {merge: force});
for (const [id, brandId, name, nameMr, swatch, bagWeightKg, fullBagPrice, perKgPrice, costPrice, minPriceFloor, lowStockThreshold, qrCode, bagsRemaining, looseKgRemaining] of products) {
  batch.set(db.doc(`products/${id}`), {
    brandId, name, nameMr, swatch, photoUrl: null, bagWeightKg, fullBagPrice,
    perKgPrice, costPrice, minPriceFloor, lowStockThreshold, qrCode,
  }, {merge: force});
  batch.set(db.doc(`stock/${id}`), {bagsRemaining, looseKgRemaining}, {merge: force});
}
for (const [id, name, mobile, outstandingBalance] of customers) {
  batch.set(db.doc(`customers/${id}`), {name, mobile, outstandingBalance}, {merge: force});
}
batch.set(db.doc(`staff/${owner.uid}`), {
  name: owner.displayName || owner.email || 'Owner', role: 'admin',
  canOverridePrice: true, maxDiscountPct: 100,
}, {merge: force});
batch.set(db.doc('meta/counters'), {bill: 1000}, {merge: force});
batch.set(db.doc('meta/settings'), {
  shop: 'जय किसान पेंड भांडार', lang: 'both', theme: 'system',
  lowDefaultBags: 5, floorOn: true, gateOverride: true, gateOverridePct: 5,
}, {merge: force});
await batch.commit();

console.log(`Seeded ${brands.length} brands, ${products.length} products, stock, customers, owner staff record, and metadata.`);
console.log(`Admin claim assigned to ${owner.email}. Sign out and back in on the app to refresh its token.`);

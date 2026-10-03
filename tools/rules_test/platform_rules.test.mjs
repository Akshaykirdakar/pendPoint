// Platform layer (super admin) — Firestore rules, run in the emulator:
// global settings, plans, announcements, notifications (per audience and
// store, read marks), store payments and reminders, and what a store admin
// may change on their own store document. Existing isolation stays as is.
import fs from 'node:fs';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, query, where, orderBy,
} from 'firebase/firestore';

const RULES = process.env.RULES_FILE ?? new URL('../../firestore.rules', import.meta.url);
const env = await initializeTestEnvironment({
  projectId: 'demo-pend-rules',
  firestore: { rules: fs.readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8085 },
});

const A = 'STR_A', B = 'STR_B', OFF = 'STR_OFF';
const now = () => new Date().toISOString();
let pass = 0;
async function check(name, fn) {
  try { await fn(); pass++; console.log(`PASS ${name}`); }
  catch (e) { console.log(`FAIL ${name}\n  ${e?.stack ?? e}`); process.exitCode = 1; }
}
const as = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();
const note = (storeId, recipientRole, extra = {}) => ({
  storeId, recipientRole, type: 'announcement', title: 't', message: 'm',
  senderUid: 'super1', createdAt: now(), visibleFrom: now(), readBy: {}, ...extra,
});

await env.clearFirestore();
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const [id, status] of [[A, 'ACTIVE'], [B, 'ACTIVE'], [OFF, 'INACTIVE']]) {
    await setDoc(doc(db, `stores/${id}`), {
      storeCode: id, storeName: `Store ${id}`, status, createdAt: now(), createdBy: 'super1',
      planStatus: 'active', planExpiryDate: now(), ownerName: 'o',
    });
  }
  const staff = (uid, role, storeId, active = true) =>
    setDoc(doc(db, `staff/${uid}`), { name: uid, role, storeId, active });
  await staff('adminA', 'admin', A);
  await staff('staffA', 'staff', A);
  await staff('adminB', 'admin', B);
  await staff('super1', 'super_admin', null);
  await staff('offStaff', 'staff', OFF);
  await setDoc(doc(db, 'global_settings/general'), { appName: 'PendPoint' });
  await setDoc(doc(db, 'global_settings/admin'), { templates: {}, smsProvider: '' });
  await setDoc(doc(db, 'plans/basic'), { name: 'Basic', durationDays: 365, price: 3000 });
  await setDoc(doc(db, 'platformAnnouncements/x'), { title: 'x' });
  await setDoc(doc(db, 'announcements/other-app'), { title: 'other application' });
  await setDoc(doc(db, 'notifications/nSA'), note(A, 'super_admin', { type: 'store_updated' }));
  await setDoc(doc(db, 'notifications/nA_admin'), note(A, 'admin', { type: 'payment_reminder' }));
  await setDoc(doc(db, 'notifications/nA_all'), note(A, 'all'));
  await setDoc(doc(db, 'notifications/nB_all'), note(B, 'all'));
  await setDoc(doc(db, 'notifications/nB_admin'), note(B, 'admin'));
  await setDoc(doc(db, 'notifications/nOFF_all'), note(OFF, 'all'));
  await setDoc(doc(db, `stores/${A}/payments/pA`), { amount: 3000, status: 'paid', paymentDate: now() });
  await setDoc(doc(db, `stores/${B}/payments/pB`), { amount: 3000, status: 'paid', paymentDate: now() });
  await setDoc(doc(db, `stores/${A}/reminders/before-7@2026-11-01`), { type: 'renewal_reminder' });
});

// ---- global settings ----
await check('global settings: everyone active reads general; only super admin reads admin', async () => {
  await assertSucceeds(getDoc(doc(as('staffA'), 'global_settings/general')));
  await assertSucceeds(getDoc(doc(as('adminB'), 'global_settings/general')));
  await assertFails(getDoc(doc(as('adminA'), 'global_settings/admin')));
  await assertFails(getDoc(doc(as('staffA'), 'global_settings/admin')));
  await assertFails(getDoc(doc(as(null), 'global_settings/general')));
  await assertSucceeds(getDoc(doc(as('super1'), 'global_settings/admin')));
});
await check('global settings: only super admin writes', async () => {
  await assertFails(setDoc(doc(as('adminA'), 'global_settings/general'), { appName: 'hack' }));
  await assertFails(setDoc(doc(as('adminA'), 'global_settings/admin'), { smsEnabled: true }));
  await assertFails(updateDoc(doc(as('staffA'), 'global_settings/general'), { appName: 'hack' }));
  await assertSucceeds(setDoc(doc(as('super1'), 'global_settings/general'), { appName: 'PendPoint 2' }));
  await assertSucceeds(setDoc(doc(as('super1'), 'global_settings/admin'), { smsEnabled: false }));
});

// ---- plans / announcements ----
await check('plans and platform announcements: super admin only', async () => {
  await assertFails(getDoc(doc(as('adminA'), 'plans/basic')));
  await assertFails(setDoc(doc(as('adminA'), 'plans/cheap'), { name: 'free', price: 0 }));
  await assertSucceeds(setDoc(doc(as('super1'), 'plans/pro'), { name: 'Pro', durationDays: 365, price: 5000 }));
  await assertFails(getDoc(doc(as('adminA'), 'platformAnnouncements/x')));
  await assertFails(setDoc(doc(as('adminA'), 'platformAnnouncements/y'), { title: 'y' }));
  await assertSucceeds(setDoc(doc(as('super1'), 'platformAnnouncements/y'), { title: 'y' }));
});
await check("the other application's `announcements` stay closed (even to super admin)", async () => {
  await assertFails(getDoc(doc(as('super1'), 'announcements/other-app')));
  await assertFails(setDoc(doc(as('super1'), 'announcements/z'), { title: 'z' }));
});

// ---- notifications: reading ----
await check('notifications: staff read own store "all", never admin-only / super admin / other store', async () => {
  const s = as('staffA');
  await assertSucceeds(getDoc(doc(s, 'notifications/nA_all')));
  await assertFails(getDoc(doc(s, 'notifications/nA_admin')));
  await assertFails(getDoc(doc(s, 'notifications/nSA')));
  await assertFails(getDoc(doc(s, 'notifications/nB_all')));
});
await check('notifications: store admin reads own store admin + all, not other store', async () => {
  const a = as('adminA');
  await assertSucceeds(getDoc(doc(a, 'notifications/nA_admin')));
  await assertSucceeds(getDoc(doc(a, 'notifications/nA_all')));
  await assertFails(getDoc(doc(a, 'notifications/nB_admin')));
  await assertFails(getDoc(doc(a, 'notifications/nB_all')));
  await assertFails(getDoc(doc(a, 'notifications/nSA')), 'super admin feed');
});
await check('notifications: inactive store users read nothing', async () => {
  await assertFails(getDoc(doc(as('offStaff'), 'notifications/nOFF_all')));
});
await check('notifications: the app\'s feed queries — allowed exactly as built', async () => {
  const col = (db) => collection(db, 'notifications');
  await assertSucceeds(getDocs(query(col(as('staffA')), where('storeId', '==', A),
    where('recipientRole', '==', 'all'), orderBy('createdAt', 'desc'))));
  await assertSucceeds(getDocs(query(col(as('adminA')), where('storeId', '==', A),
    where('recipientRole', 'in', ['all', 'admin']), orderBy('createdAt', 'desc'))));
  await assertSucceeds(getDocs(query(col(as('super1')), where('recipientRole', '==', 'super_admin'),
    orderBy('createdAt', 'desc'))));
  await assertSucceeds(getDocs(query(col(as('super1')), where('recipientRole', 'in', ['admin', 'all']),
    orderBy('createdAt', 'desc'))));
});
await check('notifications: queries outside one\'s scope are refused', async () => {
  const col = (db) => collection(db, 'notifications');
  await assertFails(getDocs(query(col(as('staffA')), where('storeId', '==', A),
    where('recipientRole', 'in', ['all', 'admin']))));
  await assertFails(getDocs(query(col(as('adminA')), where('storeId', '==', B),
    where('recipientRole', '==', 'all'))));
  await assertFails(getDocs(query(col(as('staffA')), where('recipientRole', '==', 'all'))));
  await assertFails(getDocs(query(col(as('adminA')), where('recipientRole', '==', 'super_admin'))));
  await assertFails(getDocs(col(as('adminA'))));
});

// ---- notifications: read marks ----
await check('notifications: a user marks only their own read flag', async () => {
  await assertSucceeds(updateDoc(doc(as('staffA'), 'notifications/nA_all'), { 'readBy.staffA': now() }));
  await assertFails(updateDoc(doc(as('staffA'), 'notifications/nA_all'), { 'readBy.adminA': now() }));
  await assertFails(updateDoc(doc(as('staffA'), 'notifications/nA_all'), { title: 'changed' }));
  await assertFails(updateDoc(doc(as('staffA'), 'notifications/nB_all'), { 'readBy.staffA': now() }));
  await assertFails(updateDoc(doc(as('staffA'), 'notifications/nA_admin'), { 'readBy.staffA': now() }));
  await assertSucceeds(updateDoc(doc(as('super1'), 'notifications/nSA'), { 'readBy.super1': now() }));
});

// ---- notifications: creating ----
await check('notifications: store admin only reports own-store changes to the super admin', async () => {
  const a = as('adminA');
  await assertSucceeds(setDoc(doc(a, 'notifications/c1'),
    note(A, 'super_admin', { type: 'store_updated', senderUid: 'adminA' })));
  await assertSucceeds(setDoc(doc(a, 'notifications/c2'),
    note(A, 'super_admin', { type: 'staff_disabled', senderUid: 'adminA' })));
  await assertFails(setDoc(doc(a, 'notifications/c3'),
    note(B, 'super_admin', { type: 'store_updated', senderUid: 'adminA' })), 'other store');
  await assertFails(setDoc(doc(a, 'notifications/c4'),
    note(A, 'all', { type: 'announcement', senderUid: 'adminA' })), 'cannot broadcast');
  await assertFails(setDoc(doc(a, 'notifications/c5'),
    note(A, 'super_admin', { type: 'payment_received', senderUid: 'adminA' })), 'fake payment');
  await assertFails(setDoc(doc(a, 'notifications/c6'),
    note(A, 'super_admin', { type: 'store_updated', senderUid: 'super1' })), 'impersonate sender');
  await assertFails(setDoc(doc(a, 'notifications/c7'),
    note(A, 'super_admin', { type: 'store_updated', senderUid: 'adminA', readBy: { super1: now() } })), 'pre-read');
  await assertFails(setDoc(doc(as('staffA'), 'notifications/c8'),
    note(A, 'super_admin', { type: 'store_updated', senderUid: 'staffA' })), 'staff');
  await assertSucceeds(setDoc(doc(as('super1'), 'notifications/c9'), note(B, 'admin')));
});
await check('notifications: only super admin deletes', async () => {
  await assertFails(deleteDoc(doc(as('adminA'), 'notifications/nA_admin')));
  await assertSucceeds(deleteDoc(doc(as('super1'), 'notifications/c9')));
});

// ---- store document: what a store admin may change ----
await check('store doc: store admin edits own name/contact only', async () => {
  const a = as('adminA');
  await assertSucceeds(updateDoc(doc(a, `stores/${A}`), { storeName: 'Akshay Traders', ownerPhone: '9822', updatedAt: now() }));
  await assertFails(updateDoc(doc(a, `stores/${A}`), { status: 'INACTIVE' }));
  await assertFails(updateDoc(doc(a, `stores/${A}`), { planExpiryDate: '2099-01-01' }));
  await assertFails(updateDoc(doc(a, `stores/${A}`), { paymentStatus: 'paid' }));
  await assertFails(updateDoc(doc(a, `stores/${A}`), { storeName: '' }));
  await assertFails(updateDoc(doc(a, `stores/${B}`), { storeName: 'hijack' }));
  await assertFails(updateDoc(doc(as('staffA'), `stores/${A}`), { storeName: 'staff edit' }));
  await assertSucceeds(updateDoc(doc(as('super1'), `stores/${A}`), { planStatus: 'suspended', status: 'ACTIVE' }));
});

// ---- payments / reminders ----
await check('payments: store admin reads own, never another store; staff none; only super admin writes', async () => {
  await assertSucceeds(getDoc(doc(as('adminA'), `stores/${A}/payments/pA`)));
  await assertSucceeds(getDocs(collection(as('adminA'), `stores/${A}/payments`)));
  await assertFails(getDoc(doc(as('adminA'), `stores/${B}/payments/pB`)));
  await assertFails(getDocs(collection(as('adminA'), `stores/${B}/payments`)));
  await assertFails(getDoc(doc(as('staffA'), `stores/${A}/payments/pA`)));
  await assertFails(setDoc(doc(as('adminA'), `stores/${A}/payments/fake`), { amount: 1, status: 'paid' }));
  await assertSucceeds(setDoc(doc(as('super1'), `stores/${B}/payments/p2`), { amount: 5, status: 'pending' }));
  await assertFails(deleteDoc(doc(as('super1'), `stores/${B}/payments/p2`)));
});
await check('reminders: super admin creates once; never changed; store users cannot see', async () => {
  await assertSucceeds(setDoc(doc(as('super1'), `stores/${A}/reminders/day0@2026-11-01`), { type: 'plan_expiry' }));
  await assertFails(setDoc(doc(as('super1'), `stores/${A}/reminders/before-7@2026-11-01`), { type: 'again' }));
  await assertFails(getDoc(doc(as('adminA'), `stores/${A}/reminders/before-7@2026-11-01`)));
  await assertFails(setDoc(doc(as('adminA'), `stores/${A}/reminders/x`), { type: 'x' }));
});

// ---- audit: global entries ----
await check('audit: super admin may log GLOBAL events; store admin cannot read them', async () => {
  await assertSucceeds(setDoc(doc(as('super1'), 'auditLogs/g1'),
    { storeId: 'GLOBAL', userId: 'super1', action: 'SETTINGS_UPDATED', timestamp: now() }));
  await assertFails(getDoc(doc(as('adminA'), 'auditLogs/g1')));
  await assertFails(setDoc(doc(as('adminA'), 'auditLogs/g2'),
    { storeId: 'GLOBAL', userId: 'adminA', action: 'X', timestamp: now() }));
});

await env.cleanup();
console.log(`\n${pass} platform checks passed${process.exitCode ? ' — SOME FAILED' : ''}`);

// Who may set whose password (functions/access.js).
const test = require('node:test');
const assert = require('node:assert');
const { whyNot } = require('./access');

const sa = { role: 'super_admin', storeId: null, active: true };
const adminA = { role: 'admin', storeId: 'STR-A', active: true };
const staffA = { role: 'staff', storeId: 'STR-A', active: true };
const staffB = { role: 'staff', storeId: 'STR-B', active: true };
const adminB = { role: 'admin', storeId: 'STR-B', active: true };
const active = { status: 'ACTIVE' };
const pw = 'secret12';

const check = (o) => whyNot({ callerUid: 'me', targetUid: 'them', password: pw, callerStore: active, ...o })?.code ?? 'ok';

test('super admin: any store user, never a super admin', () => {
  assert.equal(check({ caller: sa, target: staffA }), 'ok');
  assert.equal(check({ caller: sa, target: adminB }), 'ok');
  assert.equal(check({ caller: sa, target: sa }), 'permission-denied');
});

test('store admin: only staff of their own active store', () => {
  assert.equal(check({ caller: adminA, target: staffA }), 'ok');
  assert.equal(check({ caller: adminA, target: staffB }), 'permission-denied');
  assert.equal(check({ caller: adminA, target: { ...adminA } }), 'permission-denied');
  assert.equal(check({ caller: adminA, target: sa }), 'permission-denied');
  assert.equal(check({ caller: adminA, target: staffA, callerStore: { status: 'INACTIVE' } }), 'permission-denied');
  assert.equal(check({ caller: adminA, target: staffA, callerStore: null }), 'permission-denied');
});

test('staff, disabled or unknown callers: nobody', () => {
  assert.equal(check({ caller: staffA, target: staffA }), 'permission-denied');
  assert.equal(check({ caller: { ...adminA, active: false }, target: staffA }), 'permission-denied');
  assert.equal(check({ caller: null, target: staffA }), 'permission-denied');
  assert.equal(check({ callerUid: null, caller: sa, target: staffA }), 'unauthenticated');
});

test('not one\'s own; target must exist; password 6–128', () => {
  assert.equal(check({ caller: sa, target: sa, targetUid: 'me' }), 'failed-precondition');
  assert.equal(check({ caller: sa, target: null }), 'not-found');
  assert.equal(check({ caller: sa, target: staffA, password: '12345' }), 'invalid-argument');
  assert.equal(check({ caller: sa, target: staffA, password: 'x'.repeat(129) }), 'invalid-argument');
  assert.equal(check({ caller: sa, target: staffA, password: 123456 }), 'invalid-argument');
  assert.equal(check({ caller: sa, target: staffA, targetUid: '' }), 'invalid-argument');
});

// पेंड Point — Cloud Functions.
//
// setUserPassword: a super admin sets a store user's password, or a store
// admin sets a password for staff of their own store. The Firebase client
// SDK can only change the signed-in user's own password, so this runs with
// admin rights on the server, after checking the caller's protected
// staff/{uid} record (never anything the caller sends about themselves).
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { whyNot } = require('./access');

// The Admin SDK is loaded on the first call, not at start-up (faster cold
// start and deploy-time discovery).
let admin;
function adminSdk() {
  if (!admin) {
    const { initializeApp } = require('firebase-admin/app');
    initializeApp();
    admin = {
      getAuth: require('firebase-admin/auth').getAuth,
      getFirestore: require('firebase-admin/firestore').getFirestore,
    };
  }
  return admin;
}

exports.setUserPassword = onCall({ maxInstances: 5 }, async (request) => {
  const { getAuth, getFirestore } = adminSdk();
  const db = getFirestore();
  const callerUid = request.auth?.uid;
  const { uid: targetUid, password } = request.data ?? {};

  const doc = async (path) => {
    const snap = await db.doc(path).get();
    return snap.exists ? snap.data() : null;
  };
  const caller = callerUid ? await doc(`staff/${callerUid}`) : null;
  const callerStore = caller?.storeId ? await doc(`stores/${caller.storeId}`) : null;
  const target = typeof targetUid === 'string' && targetUid && targetUid.length <= 128
    ? await doc(`staff/${targetUid}`)
    : null;

  const no = whyNot({ callerUid, caller, callerStore, targetUid, target, password });
  if (no) throw new HttpsError(no.code, no.message);

  try {
    await getAuth().updateUser(targetUid, { password });
  } catch (e) {
    if (e?.code === 'auth/user-not-found') throw new HttpsError('not-found', 'No such login.');
    if (e?.code === 'auth/invalid-password') throw new HttpsError('invalid-argument', 'Password not accepted.');
    throw new HttpsError('internal', 'Could not change the password.');
  }
  // Their other sessions end; they sign in again with the new password.
  await getAuth().revokeRefreshTokens(targetUid);

  await db.collection('auditLogs').add({
    storeId: target.storeId ?? null,
    userId: callerUid,
    role: caller.role,
    action: 'PASSWORD_RESET',
    entityType: 'STAFF',
    entityId: targetUid,
    timestamp: new Date().toISOString(),
  });
  return { ok: true };
});

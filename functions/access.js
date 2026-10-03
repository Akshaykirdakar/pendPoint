// Who may set whose password — kept apart from Firebase so it can be tested
// on its own (access.test.js). Mirrors the app's AppState.canSetPasswordFor.
//
//   super_admin → any store user (admin or staff), never a super admin
//   admin       → staff of their own, active store
//   staff       → nobody
// Nobody sets their own password here (that needs the current password and
// is done in the app).

const MIN = 6;
const MAX = 128;

/**
 * Returns null when allowed, else { code, message } (an HttpsError code).
 * caller/target are staff/{uid} documents (or null), callerStore the
 * caller's stores/{storeId} document (or null).
 */
function whyNot({ callerUid, caller, callerStore, targetUid, target, password }) {
  if (!callerUid) return { code: 'unauthenticated', message: 'Sign in first.' };
  if (typeof targetUid !== 'string' || !targetUid || targetUid.length > 128) {
    return { code: 'invalid-argument', message: 'uid is required.' };
  }
  if (typeof password !== 'string' || password.length < MIN || password.length > MAX) {
    return { code: 'invalid-argument', message: `The password must be ${MIN}–${MAX} characters.` };
  }
  if (!caller || caller.active === false) {
    return { code: 'permission-denied', message: 'No active staff profile.' };
  }
  if (targetUid === callerUid) {
    return { code: 'failed-precondition', message: 'Change your own password from Settings.' };
  }
  if (!target) return { code: 'not-found', message: 'No such user.' };
  if (target.role === 'super_admin') {
    return { code: 'permission-denied', message: 'A super admin password cannot be set here.' };
  }
  if (caller.role === 'super_admin') return null;
  if (caller.role === 'admin') {
    const sid = caller.storeId;
    if (!sid || !callerStore || (callerStore.status ?? 'ACTIVE') !== 'ACTIVE') {
      return { code: 'permission-denied', message: 'Your store is not active.' };
    }
    if (target.role !== 'staff' || target.storeId !== sid) {
      return { code: 'permission-denied', message: 'Only staff of your own store.' };
    }
    return null;
  }
  return { code: 'permission-denied', message: 'Not allowed.' };
}

module.exports = { whyNot, MIN, MAX };

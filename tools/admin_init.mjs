// Shared Firebase Admin initialisation for the tools/ scripts.
//
// Credentials, in order:
//   1. FIRESTORE_EMULATOR_HOST set        → the local emulator (tests)
//   2. GOOGLE_APPLICATION_CREDENTIALS set → a service-account key file
//   3. PEND_ACCESS_TOKEN set              → a short-lived OAuth token of an
//      already signed-in project owner, e.g.
//        $env:PEND_ACCESS_TOKEN = (gcloud auth print-access-token)
//      (no key file is created; the token expires within an hour)
//
// Returns { db, auth } — a Firestore and a Firebase Auth admin client.
import admin from 'firebase-admin';
import { createRequire } from 'node:module';
import { Firestore } from '@google-cloud/firestore';

// The OAuth client must come from the same google-auth-library copy the
// Firestore client (google-gax) uses — the top-level v10 copy's headers are
// not understood by gax v9, and the token would be silently dropped.
const require = createRequire(import.meta.url);
const { OAuth2Client } = require('./node_modules/google-gax/node_modules/google-auth-library');

export const PROJECT_ID = 'senior-citizen-app-2454f';

export function initAdmin() {
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? 'demo-pend' });
    return { db: admin.firestore(), auth: admin.auth() };
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
    return { db: admin.firestore(), auth: admin.auth() };
  }
  const token = process.env.PEND_ACCESS_TOKEN?.trim();
  if (token) {
    // Firebase Auth admin: a Credential that hands out the owner's token.
    admin.initializeApp({
      projectId: PROJECT_ID,
      credential: { getAccessToken: async () => ({ access_token: token, expires_in: 3000 }) },
    });
    // Firestore: the Google Cloud client with the same token.
    const authClient = new OAuth2Client();
    authClient.setCredentials({ access_token: token, expiry_date: Date.now() + 50 * 60 * 1000 });
    const db = new Firestore({ projectId: PROJECT_ID, authClient });
    return { db, auth: tokenAuth(token) };
  }
  throw new Error('No credentials: set GOOGLE_APPLICATION_CREDENTIALS (service-account key) '
    + 'or PEND_ACCESS_TOKEN (gcloud auth print-access-token), or FIRESTORE_EMULATOR_HOST.');
}

/// Read-only Auth lookups with an owner token. (firebase-admin's Auth client
/// can't send the quota-project header that user tokens need.) Same shape
/// as the firebase-admin UserRecord fields the tools use.
function tokenAuth(token) {
  async function lookup(body) {
    const res = await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:lookup`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'x-goog-user-project': PROJECT_ID,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
    const json = await res.json();
    if (!res.ok) throw new Error(`Auth lookup failed: ${res.status} ${json?.error?.message ?? ''}`);
    const u = json.users?.[0];
    if (!u) throw new Error('auth/user-not-found');
    return {
      uid: u.localId,
      email: u.email,
      displayName: u.displayName ?? null,
      disabled: !!u.disabled,
      providerData: (u.providerUserInfo ?? []).map((p) => ({ providerId: p.providerId })),
    };
  }
  return {
    getUser: (uid) => lookup({ localId: [uid] }),
    getUserByEmail: (email) => lookup({ email: [email] }),
  };
}

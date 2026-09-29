# Firestore rules test (purchase / sales transactions)

Runs `../../firestore.rules` in the local Firestore emulator and replays the
exact writes the app makes (`FirestoreRepository.nextPurchaseNumber` and
`commitStock`) as the owner, as counter staff and signed out.

It checks:
- purchase history reads;
- the full purchase transaction (counter, batch, stock, stockLog, purchase, purchaseItems);
- that a duplicate save can't add stock twice;
- that a rejected transaction leaves no partial data;
- edit/void permissions and sales.

Requires Java 21+ on PATH (the Firebase emulator needs it).

    npm install
    npm test

Uses a `demo-` project id, so it never touches the real Firebase project.

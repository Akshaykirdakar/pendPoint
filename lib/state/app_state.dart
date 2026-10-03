import 'dart:async';
import 'dart:math' show max;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../data/stock_commit.dart';
import '../models/app_settings.dart';
import '../models/batch.dart';
import '../models/bill.dart';
import '../models/branch.dart';
import '../models/brand.dart';
import '../models/customer.dart';
import '../models/draft_bill.dart';
import '../models/enums.dart';
import '../models/party.dart';
import '../models/platform.dart';
import '../models/product.dart';
import '../models/purchase.dart';
import '../models/staff.dart';
import '../models/stock.dart';
import '../models/stock_log.dart';
import '../models/store.dart';
import '../models/supplier.dart';
import '../services/photo_check.dart';
import 'cart_line.dart';
import 'platform_service.dart';
import 'payment_split.dart';
import 'purchase_draft.dart';
import '../utils/lang.dart';

/// Where the signed-in user is after login.
enum SessionState {
  none, // signed out / not started
  checking, // reading the staff profile and store
  noProfile, // signed in, but no staff record exists for this login
  disabled, // the staff record is inactive
  noStore, // a store user with no (existing) store assigned
  storeInactive, // their store is deactivated
  superAdmin, // super-admin dashboard (no store open)
  store, // working inside a store
  error, // the profile/store could not be read
}

/// Result of trying to finalize a sale.
class SaleResult {
  final bool ok;
  final String? error;
  final Bill? bill;
  const SaleResult.success(this.bill)
      : ok = true,
        error = null;
  const SaleResult.failure(this.error)
      : ok = false,
        bill = null;
}

/// Result of saving a draft bill.
class DraftResult {
  final bool ok;
  final String? error;
  final DraftBill? draft;
  const DraftResult.success(DraftBill this.draft)
      : ok = true,
        error = null;
  const DraftResult.failure(String this.error)
      : ok = false,
        draft = null;
}

/// Result of saving a purchase bill.
class PurchaseResult {
  final bool ok;
  final String? error;
  final Purchase? purchase;
  const PurchaseResult.success(this.purchase)
      : ok = true,
        error = null;
  const PurchaseResult.failure(this.error)
      : ok = false,
        purchase = null;
}

/// Result of creating a brand / product from a picker.
class MasterResult<T> {
  final T? value;
  final String? error;
  const MasterResult.success(T this.value) : error = null;
  const MasterResult.failure(String this.error) : value = null;
  bool get ok => error == null;
}

/// Central app state + business logic. Holds the working copy in memory for a
/// snappy counter UI and writes through [repo] for persistence.
class AppState extends ChangeNotifier {
  final Repository repo;
  AppState(this.repo) {
    appLang = settings.lang;
  }

  // ---- data ----
  List<Brand> brands = [];
  List<Branch> branches = [];
  List<Supplier> suppliers = [];
  List<Product> products = [];
  Map<String, Stock> stock = {};
  List<Batch> batches = [];
  List<StockLog> logs = [];
  List<Bill> bills = [];
  List<Purchase> purchases = [];
  List<Customer> customers = [];
  List<Staff> staff = [];
  AppSettings settings = AppSettings();
  bool loading = true;
  Object? bootstrapError;

  /// The branch Stock In/POS/Reports operate against by default. Set once
  /// branches are known (bootstrap, or after creating the first branch);
  /// screens that need a specific branch (Stock In, Reports) can still pick a
  /// different one without changing this.
  String? activeBranchId;

  void setActiveBranch(String id) {
    activeBranchId = id;
    notifyListeners();
  }

  // ---- multi-store session ----
  //
  // After Firebase login the user's protected staff record decides
  // everything: active or not, role, and (for store users) the one store
  // they work in. The store comes from that record — never from input.

  SessionState session = SessionState.none;

  /// Changes whenever the signed-in user or the open store goes away
  /// (sign-out, "All stores", another store opened). Screens opened on top
  /// belong to the previous session, so the app closes them on a change.
  int sessionEpoch = 0;

  /// Who is signed in and which store the data is for (null: none).
  StoreContext? get storeContext => repo.context;
  String? get storeId => repo.context?.storeId;
  Store? get store => repo.context?.store;
  bool get isSuperAdmin => repo.context?.isSuperAdmin ?? false;

  /// Resolves the signed-in user's profile and opens their store (or the
  /// super-admin dashboard). Never loads store data for a disabled user or
  /// an inactive store.
  Future<void> startSession() async {
    clearSession(notify: false);
    // A sign-out (or a newer session) while this one is still resolving
    // bumps the sequence; this one then stops without touching anything.
    final seq = _bootstrapSeq;
    session = SessionState.checking;
    notifyListeners();
    try {
      final me = await repo.loadMyProfile();
      if (seq != _bootstrapSeq) return;
      final uid = repo.currentUserId;
      if (me == null || uid == null) {
        session = SessionState.noProfile;
      } else if (!me.active) {
        session = SessionState.disabled;
      } else if (me.isSuperAdmin) {
        repo.useContext(StoreContext(uid: uid, role: me.role));
        session = SessionState.superAdmin;
        _watchNotifications();
      } else if (me.storeId == null || me.storeId!.isEmpty) {
        session = SessionState.noStore;
      } else {
        final st = await repo.loadStore(me.storeId!);
        if (seq != _bootstrapSeq) return;
        if (st == null) {
          session = SessionState.noStore;
        } else if (!st.isActive) {
          session = SessionState.storeInactive;
        } else {
          repo.useContext(StoreContext(
              uid: uid, role: me.role, storeId: st.id, store: st));
          session = SessionState.store;
          _watchOpenStore(st.id);
          _watchNotifications();
          notifyListeners();
          await bootstrap();
          return;
        }
      }
    } catch (e) {
      if (seq != _bootstrapSeq) return;
      bootstrapError = e;
      session = SessionState.error;
    }
    loading = false;
    notifyListeners();
  }

  /// Super admin: work inside [st] (their identity stays super admin).
  Future<void> openStore(Store st) async {
    final ctx = repo.context;
    if (ctx == null || !ctx.isSuperAdmin) {
      throw const StoreContextException('Only a super admin can open a store.');
    }
    clearSession(notify: false);
    repo.useContext(ctx.openStore(st));
    session = SessionState.store;
    _watchOpenStore(st.id);
    _watchNotifications();
    notifyListeners();
    await bootstrap();
  }

  /// This user's in-app notifications (live), newest first.
  List<AppNotification> notifications = [];
  StreamSubscription<List<AppNotification>>? _noteWatch;
  int get unreadNotifications => platform.unreadCount(notifications);

  void _watchNotifications() {
    _noteWatch?.cancel();
    final epoch = sessionEpoch;
    _noteWatch = platform.watchMine().listen((l) {
      if (epoch != sessionEpoch) return;
      notifications = l;
      notifyListeners();
    }, onError: (Object e) => debugPrint('[pend] notifications: $e'));
  }

  /// Keeps the open store's details live: a rename / contact / plan change
  /// shows at once (no restart), and a store user whose store is switched
  /// off is stopped right away (the rules already refuse its data).
  StreamSubscription<Store?>? _storeWatch;
  void _watchOpenStore(String sid) {
    _storeWatch?.cancel();
    // Tied to this session (not to data loads, which may be retried).
    final epoch = sessionEpoch;
    _storeWatch = repo.platform.watchStore(sid).listen((st) {
      final ctx = repo.context;
      if (epoch != sessionEpoch || st == null || ctx == null || ctx.storeId != sid) {
        return;
      }
      repo.useContext(
          StoreContext(uid: ctx.uid, role: ctx.role, storeId: sid, store: st));
      if (!st.isActive && !ctx.isSuperAdmin) {
        clearSession(notify: false);
        session = SessionState.storeInactive;
        loading = false;
      }
      notifyListeners();
    }, onError: (Object _) {});
  }

  /// Super Admin platform: settings, notifications, plans, payments,
  /// announcements, reminders (see PlatformService).
  late final PlatformService platform = PlatformService(repo);

  /// A store admin (or a super admin inside the store) edits the store's
  /// name / contact / owner details. Plan, payment and status are changed
  /// only from the Super Admin screens.
  Future<String?> updateMyStore(Store after) async {
    final before = store;
    if (before == null) return 'दुकान उघडलेले नाही · No store open';
    final error = await platform.updateMyStore(before, after);
    if (error == null) {
      final ctx = repo.context!;
      repo.useContext(StoreContext(
          uid: ctx.uid, role: ctx.role, storeId: before.id, store: after));
      notifyListeners();
    }
    return error;
  }

  /// Super admin: leave the store and go back to the store list.
  void closeStore() {
    final ctx = repo.context;
    if (ctx == null || !ctx.isSuperAdmin) return;
    clearSession(notify: false);
    repo.useContext(StoreContext(uid: ctx.uid, role: ctx.role));
    session = SessionState.superAdmin;
    _watchNotifications();
    loading = false;
    notifyListeners();
  }

  /// Forgets everything of the current user and store: data, cart, drafts
  /// and the store context (sign-out, or before another store loads), so
  /// nothing of one store can show up in the next.
  void clearSession({bool notify = true}) {
    _bootstrapSeq++; // a load still on its way is dropped
    sessionEpoch++;
    _storeWatch?.cancel();
    _storeWatch = null;
    _noteWatch?.cancel();
    _noteWatch = null;
    notifications = [];
    // The one-time branch/batch set-up checks run again for the next store.
    _migratedBranches = false;
    _migratedBatches = false;
    _resetCart();
    repo.useContext(null);
    session = SessionState.none;
    brands = [];
    branches = [];
    suppliers = [];
    products = [];
    stock = {};
    batches = [];
    logs = [];
    bills = [];
    purchases = [];
    customers = [];
    staff = [];
    drafts = [];
    settings = AppSettings();
    appLang = settings.lang;
    activeBranchId = null;
    loading = true;
    bootstrapError = null;
    historyError = null;
    historyLoading = false;
    if (notify) notifyListeners();
  }

  /// Signs out and clears every trace of the store from memory.
  Future<void> signOut() async {
    clearSession();
    await repo.signOut();
  }

  /// Bill / purchase / draft numbers run per store; the document id gets
  /// the store code so two stores' "BILL1001" never collide. The original
  /// store keeps its existing ids.
  String _docId(String base) {
    final sid = storeId;
    return sid == null || sid == legacyStoreId ? base : '${sid}_$base';
  }

  AuditEntry? _auditEntry(String action, String entityType, String entityId,
      {String? note}) {
    final ctx = repo.context;
    final sid = ctx?.storeId;
    if (ctx == null || sid == null) return null;
    return AuditEntry(
        storeId: sid,
        userId: repo.currentUserId ?? ctx.uid,
        role: ctx.role,
        action: action,
        entityType: entityType,
        entityId: entityId,
        at: DateTime.now(),
        note: note);
  }

  // ---- super admin: stores and their users ----

  void _requireSuperAdmin() {
    if (!isSuperAdmin) {
      throw const StoreContextException(
          'Only a super admin can manage stores and their users.');
    }
  }

  void _auditStore(String storeId, String action, String entityType,
      String entityId, {String? note}) {
    final ctx = repo.context;
    if (ctx == null) return;
    unawaited(repo
        .addAudit(AuditEntry(
            storeId: storeId,
            userId: repo.currentUserId ?? ctx.uid,
            role: ctx.role,
            action: action,
            entityType: entityType,
            entityId: entityId,
            at: DateTime.now(),
            note: note))
        .catchError((_) {}));
  }

  /// The code for the next new store: `STR` + the next number after the
  /// stores so far (STORE001, STR002 → STR003). Never one already used.
  static String storeCodeAfter(Iterable<String> codes) {
    final used = codes.toSet();
    var n = used.length;
    for (final c in used) {
      final m = RegExp(r'(\d+)$').firstMatch(c);
      if (m != null) n = max(n, int.parse(m.group(1)!));
    }
    String code;
    do {
      n++;
      code = 'STR${n.toString().padLeft(3, '0')}';
    } while (used.contains(code));
    return code;
  }

  /// [storeCodeAfter] for the stores that exist now (super admin only).
  Future<String> nextStoreCode() async {
    _requireSuperAdmin();
    return storeCodeAfter((await repo.listStores()).map((s) => s.id));
  }

  /// Creates a store (its code is its permanent id) with its own default
  /// settings and counters — no data is copied from any other store.
  /// Returns an error message, or null.
  Future<String?> createStore({
    required String code,
    required String name,
    String legalName = '',
    String address = '',
    String city = '',
    String state = '',
    String pincode = '',
    String phone = '',
    String email = '',
    String gstNumber = '',
    String ownerName = '',
    String ownerEmail = '',
    String ownerPhone = '',
    String ownerWhatsApp = '',
    String notifyChannel = 'whatsApp',
  }) async {
    _requireSuperAdmin();
    final id = code.trim().toUpperCase();
    if (!Store.codePattern.hasMatch(id)) {
      return 'दुकान कोड चुकीचा · Store code: 3–20 capital letters, digits or "-"';
    }
    if (name.trim().isEmpty) return 'दुकानाचे नाव लिहा · Enter the store name';
    final now = DateTime.now();
    // A new store starts on the trial set in General Settings.
    final g = await platform.settings();
    final st = Store(
        id: id,
        storeName: name.trim(),
        legalName: legalName.trim(),
        address: address.trim(),
        city: city.trim(),
        state: state.trim(),
        pincode: pincode.trim(),
        phone: phone.trim(),
        email: email.trim(),
        gstNumber: gstNumber.trim(),
        createdAt: now,
        updatedAt: now,
        createdBy: repo.currentUserId ?? repo.context?.uid,
        ownerName: ownerName.trim(),
        ownerEmail: ownerEmail.trim(),
        ownerPhone: ownerPhone.trim(),
        ownerWhatsApp: ownerWhatsApp.trim(),
        notifyChannel: notifyChannel,
        planStatus: g.trialDays > 0 ? PlanStatus.trial : null,
        planName: g.trialDays > 0 ? 'Trial' : null,
        planStartDate: g.trialDays > 0 ? now : null,
        planExpiryDate:
            g.trialDays > 0 ? now.add(Duration(days: g.trialDays)) : null,
        nextPaymentDate:
            g.trialDays > 0 ? now.add(Duration(days: g.trialDays)) : null);
    try {
      if ((await repo.loadStore(id)) != null) {
        return 'हा दुकान कोड आधीच वापरला आहे · Store code $id is already used';
      }
      await repo.createStore(st, AppSettings()..shop = st.storeName);
    } catch (e) {
      final text = e.toString();
      if (text.contains('already')) {
        return 'हा दुकान कोड आधीच वापरला आहे · Store code $id is already used';
      }
      return _saveError(e);
    }
    _auditStore(id, 'STORE_CREATED', 'STORE', id);
    unawaited(platform.storeCreated(st));
    notifyListeners();
    return null;
  }

  /// Edits a store's details or status. The code (id) never changes.
  Future<String?> updateStore(Store st) async {
    _requireSuperAdmin();
    final before = await repo.loadStore(st.id);
    try {
      await repo.updateStore(st.copyWith(updatedAt: DateTime.now()));
    } catch (e) {
      return _saveError(e);
    }
    final action = before != null && before.isActive && !st.isActive
        ? 'STORE_DISABLED'
        : before != null && !before.isActive && st.isActive
            ? 'STORE_ENABLED'
            : 'STORE_UPDATED';
    _auditStore(st.id, action, 'STORE', st.id);
    if (before != null) await platform.storeChanged(before, st);
    notifyListeners();
    return null;
  }

  /// Creates a sign-in for a new store user (STORE_ADMIN or STAFF) and
  /// links it to [storeId]. Returns an error message, or null.
  Future<String?> createStoreUser({
    required String storeId,
    required String name,
    required String email,
    required String password,
    String phone = '',
    String role = Roles.storeAdmin,
    bool active = true,
  }) async {
    _requireSuperAdmin();
    if (role != Roles.storeAdmin && role != Roles.staff) {
      return 'भूमिका चुकीची · Role must be store admin or staff';
    }
    if (name.trim().isEmpty) return 'नाव लिहा · Enter a name';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      return 'ईमेल चुकीचा · Enter a valid email';
    }
    if (password.length < 6) {
      return 'पासवर्ड किमान ६ अक्षरे · Password must be at least 6 characters';
    }
    final String uid;
    try {
      uid = await repo.createLoginAccount(email.trim(), password);
      await repo.saveUser(Staff(
          id: uid,
          name: name.trim(),
          email: email.trim(),
          phone: phone.trim(),
          role: role,
          storeId: storeId,
          active: active));
    } catch (e) {
      final text = e.toString();
      if (text.contains('email-already-in-use')) {
        return 'हा ईमेल आधीच वापरात आहे · This email already has an account';
      }
      return _saveError(e);
    }
    _auditStore(storeId, 'STAFF_CREATED', 'STAFF', uid, note: role);
    unawaited(platform.staffChanged(
        null,
        Staff(id: uid, name: name.trim(), role: role, storeId: storeId, active: active),
        storeId));
    notifyListeners();
    return null;
  }

  /// Changes a store user's name, phone, role or active flag. Their store
  /// stays the same; nobody is promoted to super admin here.
  Future<String?> updateStoreUser(Staff user) async {
    _requireSuperAdmin();
    if (user.isSuperAdmin || user.storeId == null) {
      return 'फक्त दुकानाचे वापरकर्ते · Only store users can be edited here';
    }
    final before =
        (await repo.listUsers(storeId: user.storeId)).where((u) => u.id == user.id).firstOrNull;
    try {
      await repo.saveUser(user);
    } catch (e) {
      return _saveError(e);
    }
    _auditStore(
        user.storeId!,
        before != null && before.active && !user.active
            ? 'STAFF_DISABLED'
            : 'STAFF_UPDATED',
        'STAFF',
        user.id);
    unawaited(platform.staffChanged(before, user, user.storeId!));
    notifyListeners();
    return null;
  }

  // ---- passwords ----

  /// Super admins and store admins may change their own password.
  bool get canChangeOwnPassword => isSuperAdmin || hasOwnerRights;

  /// Whether this login may set [u]'s password: a super admin for any store
  /// user; a store admin for staff of their own store. Never one's own
  /// (that is [changeMyPassword]) and never a super admin's.
  bool canSetPasswordFor(Staff u) {
    final me = repo.currentUserId;
    if (u.id == me || u.isSuperAdmin) return false;
    if (isSuperAdmin) return true;
    if (!hasOwnerRights || storeId == null) return false;
    return u.role == Roles.staff && (u.storeId == null || u.storeId == storeId);
  }

  static String? _newPasswordProblem(String next, String confirm) {
    if (next.length < 6) {
      return 'नवीन पासवर्ड किमान ६ अक्षरे · The new password must be at least 6 characters';
    }
    if (next != confirm) {
      return 'दोन्ही पासवर्ड जुळत नाहीत · The two new passwords do not match';
    }
    return null;
  }

  static String _passwordError(Object e) {
    final t = e.toString();
    if (t.contains('wrong-password') || t.contains('invalid-credential')) {
      return 'सध्याचा पासवर्ड चुकीचा आहे · The current password is wrong';
    }
    if (t.contains('weak-password')) {
      return 'पासवर्ड खूप सोपा आहे · That password is too weak';
    }
    if (t.contains('too-many-requests')) {
      return 'खूप प्रयत्न झाले — थोड्या वेळाने करा · Too many attempts — try again later';
    }
    if (t.contains('permission-denied')) {
      return 'या वापरकर्त्याचा पासवर्ड बदलण्याची परवानगी नाही · You may not change this user\'s password';
    }
    if (t.contains('not-found')) {
      return 'हा वापरकर्ता सापडला नाही · This user was not found';
    }
    if (t.contains('unavailable') || t.contains('internal') ||
        t.contains('network')) {
      return 'पासवर्ड बदलता आला नाही — इंटरनेट तपासा · Could not change the password — check the connection';
    }
    return 'पासवर्ड बदलला नाही · Password not changed — $t';
  }

  /// Changes the signed-in super admin's / store admin's own password.
  /// Returns an error message, or null.
  Future<String?> changeMyPassword(
      {required String current,
      required String next,
      required String confirm}) async {
    if (!canChangeOwnPassword) {
      return 'फक्त मालक पासवर्ड बदलू शकतो · Only an admin can change the password here';
    }
    if (current.isEmpty) {
      return 'सध्याचा पासवर्ड टाका · Enter the current password';
    }
    final bad = _newPasswordProblem(next, confirm);
    if (bad != null) return bad;
    if (next == current) {
      return 'नवीन पासवर्ड जुन्यापेक्षा वेगळा हवा · The new password must differ from the current one';
    }
    try {
      await repo.changeOwnPassword(current, next);
    } catch (e) {
      return _passwordError(e);
    }
    final uid = repo.currentUserId;
    if (uid != null) _auditNow('PASSWORD_CHANGED', 'STAFF', uid);
    return null;
  }

  /// Sets [u]'s password (see [canSetPasswordFor]); the server checks the
  /// same, signs [u] out elsewhere and records it in the audit log.
  /// Returns an error message, or null.
  Future<String?> setPasswordFor(Staff u,
      {required String next, required String confirm}) async {
    if (!canSetPasswordFor(u)) {
      return 'या वापरकर्त्याचा पासवर्ड बदलण्याची परवानगी नाही · You may not change this user\'s password';
    }
    final bad = _newPasswordProblem(next, confirm);
    if (bad != null) return bad;
    try {
      await repo.setUserPassword(u.id, next);
    } catch (e) {
      return _passwordError(e);
    }
    return null;
  }

  /// Records [action] inside [commit] (saved all-or-nothing with it).
  void _auditIn(StockCommit commit, String action, String entityType,
      String entityId, {String? note}) {
    final e = _auditEntry(action, entityType, entityId, note: note);
    if (e != null) commit.audits.add(e);
  }

  /// Records [action] on its own (a failed audit write never blocks work).
  void _auditNow(String action, String entityType, String entityId,
      {String? note}) {
    final e = _auditEntry(action, entityType, entityId, note: note);
    if (e != null) unawaited(repo.addAudit(e).catchError((_) {}));
  }

  // History (bills, customers+ledgers, stock logs) loads separately, in the
  // background, after the core catalogue/stock — see [bootstrap]. Reports/
  // Khata/Returns/History screens watch these to show an inline loading
  // note instead of a false "no data" empty state; Home/Sell/Stock don't
  // depend on history at all and never wait on it.
  bool historyLoading = false;
  Object? historyError;

  // Bumped on every bootstrap() call; a history load only applies its result
  // if it's still the most recent one, so an overlapping/second bootstrap
  // (e.g. a Retry tap, or "Reset sample data") can't have its history
  // clobbered by a slower, now-stale load from the previous cycle.
  int _bootstrapSeq = 0;

  // ---- current cart ----
  final List<CartLine> cart = [];
  String? cartCustomerId;
  final List<Payment> payments = [];

  /// Loads the catalogue/stock/settings/staff first and shows the counter
  /// screen as soon as that's ready, then loads history (bills, customers,
  /// stock logs) in the background without blocking the UI.
  Future<void> bootstrap() async {
    bootstrapError = null;
    loading = true;
    historyError = null;
    final seq = ++_bootstrapSeq;
    notifyListeners();
    try {
      // A hung Firestore call (dropped connection, silently-blocked request,
      // stuck IndexedDB/persistence layer on web) should surface as an
      // error the UI can show, not spin the splash screen forever.
      final core = await repo.loadCore().timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw StateError(
                'Timed out loading shop data — check your connection and Firestore rules.'),
          );
      // Signed out, store closed or another store opened meanwhile: this
      // store's data must not land in the new session.
      if (seq != _bootstrapSeq) return;
      brands = core.brands;
      // Retain one backing branch for legacy batch data; branch management is
      // deliberately not exposed in the single-shop app.
      branches = core.branches.isEmpty ? [] : [core.branches.first];
      suppliers = core.suppliers;
      products = core.products;
      stock = core.stock;
      staff = core.staff;
      settings = core.settings;
      appLang = settings.lang;
      await _migrateBranchesAndProducts();
      if (seq != _bootstrapSeq) return;
      activeBranchId ??= branches.where((b) => b.active).firstOrNull?.id ??
          branches.firstOrNull?.id;
    } catch (error) {
      if (seq == _bootstrapSeq) bootstrapError = error;
    } finally {
      if (seq == _bootstrapSeq) {
        loading = false;
        notifyListeners();
      }
    }
    if (seq != _bootstrapSeq) return;
    if (bootstrapError != null) return; // core failed — don't load history
    unawaited(_loadHistory(seq));
  }

  Future<void> _loadHistory(int seq) async {
    historyLoading = true;
    historyError = null;
    notifyListeners();
    try {
      final history = await repo.loadHistory().timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw StateError('Timed out loading bill/customer history.'),
          );
      if (seq != _bootstrapSeq) return; // superseded by a newer bootstrap
      logs = history.logs;
      bills = history.bills;
      customers = history.customers;
      batches = history.batches;
      purchases = List.of(history.purchases);
      await _migrateLegacyStockToBatches();
      await refreshDrafts();
    } catch (error) {
      if (seq != _bootstrapSeq) return;
      historyError = error;
      debugPrint('[pend] history load error: $error');
    } finally {
      if (seq == _bootstrapSeq) {
        historyLoading = false;
        notifyListeners();
      }
    }
  }

  // ---- lookups ----
  Brand? brandOf(String id) => brands.where((b) => b.id == id).firstOrNull;
  Branch? branchOf(String id) => branches.where((b) => b.id == id).firstOrNull;
  Supplier? supplierOf(String id) =>
      suppliers.where((s) => s.id == id).firstOrNull;
  Product? productOf(String id) =>
      products.where((p) => p.id == id).firstOrNull;
  Stock stockOf(String id) => stock[id] ?? Stock(productId: id);

  /// The product a scanned QR code belongs to (exact code match), else null.
  Product? productForQr(String code) =>
      products.where((p) => p.qr == code).firstOrNull;
  Batch? batchOf(String id) => batches.where((b) => b.id == id).firstOrNull;

  /// Batches for one product, optionally narrowed to a branch, in the order
  /// sales consume them: FEFO — nearest expiry first, batches with no expiry
  /// after all dated ones — and, whenever expiry doesn't decide (same date,
  /// or no expiry tracked), FIFO: the batch that came in first goes out
  /// first.
  List<Batch> batchesOf(String productId, {String? branchId}) {
    final list = batches
        .where((b) =>
            b.productId == productId &&
            (branchId == null || b.branchId == branchId))
        .toList()
      ..sort(compareSaleOrder);
    return list;
  }

  /// Sale-order comparator used by [batchesOf] (FEFO, then FIFO).
  static int compareSaleOrder(Batch a, Batch b) {
    final ea = a.expiry, eb = b.expiry;
    if (ea != null && eb != null) {
      final byExpiry = DateTime(ea.year, ea.month, ea.day)
          .compareTo(DateTime(eb.year, eb.month, eb.day));
      if (byExpiry != 0) return byExpiry;
    } else if (ea != null) {
      return -1;
    } else if (eb != null) {
      return 1;
    }
    final byArrival = a.createdAt.compareTo(b.createdAt);
    if (byArrival != 0) return byArrival;
    return a.id.compareTo(b.id);
  }

  Staff get owner => staff.firstWhere((s) => s.isAdmin,
      orElse: () => staff.isNotEmpty
          ? staff.first
          : const Staff(id: 'unknown', name: 'Staff', role: 'staff'));

  /// Whether this login may do owner-only corrections (edit/void bills and
  /// purchases, create purchase parties) — the same check Firestore rules
  /// enforce. A repository with no signed-in user (the local in-memory
  /// demo) has no rules to enforce, so everything is allowed there.
  bool get hasOwnerRights {
    final uid = repo.currentUserId;
    if (uid == null) return true;
    if (isSuperAdmin) return true;
    return staff.any((s) => s.id == uid && s.isAdmin && s.active);
  }

  double effKg(String id) {
    final p = productOf(id);
    if (p == null) return 0;
    return stockOf(id).effectiveKg(p.bagWeightKg);
  }

  StockLevel levelOf(String id) {
    final p = productOf(id);
    if (p == null) return StockLevel.out;
    final e = effKg(id);
    final threshold = p.lowStockThresholdBags * p.bagWeightKg;
    if (e <= 0) return StockLevel.out;
    if (e < threshold) return StockLevel.low;
    return StockLevel.ok;
  }

  List<Product> get lowStock =>
      products.where((p) => levelOf(p.id) != StockLevel.ok).toList();

  /// Distinct product categories/types currently in the catalogue (for the
  /// Reports product-type filter). Products without one are simply absent
  /// from this list — they still show up under "All Products".
  List<String> get categories {
    final set = <String>{};
    for (final p in products) {
      final cat = p.category;
      if (cat != null && cat.isNotEmpty) set.add(cat);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Bill> get finalBills =>
      bills.where((b) => b.status == BillStatus.finalized).toList();

  // ---- cart ----
  double get cartSubtotal => cart.fold(0.0, (s, l) => s + l.lineTotal);
  double get cartDiscount =>
      cart.fold(0.0, (s, l) => s + (l.catalogRate - l.rate) * l.qty);
  double get cartTotal => cartSubtotal;

  static const outOfStockMessage =
      '⛔ साठा नाही — हे उत्पादन विकता येणार नाही · Out of stock — this product cannot be sold';
  static const shortStockMessage =
      '⛔ पुरेसा साठा नाही — लाल ओळीतील प्रमाण कमी करा · Not enough stock — reduce the quantity on the red row';

  /// Whether [productId] has anything sellable at the active branch (full
  /// bags or loose kg from non-expired, non-blocked batches).
  bool hasSellableStock(String productId) =>
      sellableQty(productId, SaleType.kg) > 1e-9;

  /// Indexes of bill lines asking for more than is sellable right now. A
  /// bill with any of these can't go to Payment. (Not checked while a
  /// finalized bill is corrected — its own stock comes back first.)
  List<int> get shortLines => editingBillId != null
      ? const []
      : [
          for (var i = 0; i < cart.length; i++)
            if (cart[i].qty > sellableQty(cart[i].productId, cart[i].saleType) + 1e-9)
              i,
        ];

  /// Adds a line to the bill. Refuses (returns [outOfStockMessage]) when
  /// the product has no sellable stock at all; null when added.
  String? addToCart(String productId, SaleType type, double qty,
      {double? rate}) {
    final p = productOf(productId);
    if (p == null) return 'उत्पादन सापडले नाही · Product not found';
    if (!hasSellableStock(productId)) return outOfStockMessage;
    final catalog = p.catalogRate(type == SaleType.bag);
    cart.add(CartLine(
      productId: productId,
      saleType: type,
      qty: qty,
      catalogRate: catalog,
      rate: rate ?? catalog,
    ));
    _linesChanged();
    return null;
  }

  void changeLineQty(int i, double delta) {
    final l = cart[i];
    final v = (l.qty + delta * l.step);
    l.qty = v < l.step ? l.step : double.parse(v.toStringAsFixed(2));
    _linesChanged();
  }

  void setLineQty(int i, double qty) {
    cart[i].qty = qty <= 0 ? cart[i].step : qty;
    _linesChanged();
  }

  void setLineRate(int i, double rate) {
    cart[i].rate = rate;
    _linesChanged();
  }

  void removeLine(int i) {
    cart.removeAt(i);
    _linesChanged();
  }

  /// Swaps the product on line [i] (sales entry grid), keeping the unit and
  /// quantity and taking the new product's catalogue selling rate. Refuses
  /// an out-of-stock product (returns [outOfStockMessage]).
  String? replaceLineProduct(int i, String productId) {
    final p = productOf(productId);
    if (p == null) return 'उत्पादन सापडले नाही · Product not found';
    if (!hasSellableStock(productId)) return outOfStockMessage;
    final old = cart[i];
    final rate = p.catalogRate(old.isBag);
    cart[i] = CartLine(
        productId: productId,
        saleType: old.saleType,
        qty: old.qty,
        catalogRate: rate,
        rate: rate);
    _linesChanged();
    return null;
  }

  /// Switches line [i] between full bags and loose kg, at that unit's
  /// catalogue selling rate.
  void setLineSaleType(int i, SaleType type) {
    final old = cart[i];
    if (old.saleType == type) return;
    final p = productOf(old.productId);
    if (p == null) return;
    final rate = p.catalogRate(type == SaleType.bag);
    cart[i] = CartLine(
        productId: old.productId,
        saleType: type,
        qty: type == SaleType.bag ? old.qty.ceilToDouble() : old.qty,
        catalogRate: rate,
        rate: rate);
    _linesChanged();
  }

  /// What can be sold right now at the active branch — bags, or total kg
  /// (bags × weight + loose) — from non-expired, non-blocked batches.
  double sellableQty(String productId, SaleType type) {
    final p = productOf(productId);
    if (p == null) return 0;
    final own = batchesOf(productId, branchId: activeBranchId);
    if (own.isEmpty) {
      final s = stockOf(productId);
      return type == SaleType.bag
          ? s.bags.toDouble()
          : s.effectiveKg(p.bagWeightKg);
    }
    var total = 0.0;
    for (final b in own.where((b) => b.isSellable(p.bagWeightKg))) {
      total +=
          type == SaleType.bag ? b.bagsAvailable : b.availableKg(p.bagWeightKg);
    }
    return total;
  }

  void setCartCustomer(String? id) {
    if (id != cartCustomerId) cartDueCollect = 0;
    cartCustomerId = id;
    _cartChanged();
  }

  // ---- previous due collected with the bill ----

  /// Part of the customer's previous due they pay along with this bill
  /// ("➕ add previous due to bill"); 0 = not added.
  double cartDueCollect = 0;

  /// The chosen customer's khata balance before this bill (0 if none).
  double get cartPreviousDue {
    final id = cartCustomerId;
    if (id == null) return 0;
    return customers.where((c) => c.id == id).firstOrNull?.outstanding ?? 0;
  }

  /// What the customer pays now: this bill + the previous due added to it.
  double get cartPayable => cartTotal + cartDueCollect;

  /// Adds [amount] of the previous due to this bill (clamped to what is
  /// actually owed); 0 removes it.
  void setDueCollect(double amount) {
    final max = cartPreviousDue;
    cartDueCollect = amount <= 0 ? 0 : (amount > max ? max : amount);
    _cartChanged();
  }

  // ---- payments ----
  void ensurePayments() {
    if (payments.isEmpty) payments.add(Payment(PayMode.cash, cartTotal));
  }

  /// The bill is paid in more than one way (e.g. cash + credit).
  bool get isSplitPayment => payments.length > 1;

  /// The one payment mode of a non-split bill — Cash until chosen.
  PayMode get saleMode =>
      payments.isEmpty ? PayMode.cash : payments.first.mode;

  /// 💵 Cash / 📱 UPI / 📝 Credit in one tap: the whole bill in that mode
  /// (replaces any split). Credit still needs a customer to finalize.
  void setSaleMode(PayMode mode) =>
      _replacePayments([Payment(mode, PaymentSplit.rupees(PaymentSplit.paise(cartTotal)))]);

  /// After a line change the payment rows follow the new total (the chosen
  /// modes stay; the first row takes up the difference) — the amounts
  /// entered never drift from the bill.
  void _linesChanged() {
    if (payments.isNotEmpty) {
      final next = PaymentSplit.fit(payments, cartTotal);
      payments
        ..clear()
        ..addAll(next);
    }
    _cartChanged();
  }

  /// Sets row [i]'s mode and/or amount. A typed amount is kept as typed
  /// (capped at the bill total) and the other rows are rebalanced so the
  /// total never goes over the bill — see [PaymentSplit].
  void setPayment(int i, {PayMode? mode, double? amount}) {
    var next = List.of(payments);
    if (mode != null && mode != next[i].mode) {
      next = PaymentSplit.setMode(next, cartTotal, i, mode);
      // A merge can remove a row; the amount (if any) applies to the row
      // that now carries that mode.
      i = next.indexWhere((p) => p.mode == mode);
    }
    if (amount != null) {
      next = PaymentSplit.setAmount(next, cartTotal, i, amount);
    }
    _replacePayments(next);
  }

  /// Adds a split row with the next unused mode (none when all are used).
  void addSplitPayment() {
    ensurePayments();
    _replacePayments(PaymentSplit.addRow(payments, cartTotal));
  }

  /// Removes row [i]; the freed amount goes back to the first row.
  void removePayment(int i) {
    _replacePayments(PaymentSplit.removeRow(payments, cartTotal, i));
  }

  /// Makes the current rows add up to the bill total (Checkout open, or an
  /// edited bill whose total changed) without dropping the chosen modes.
  void fitPayments() {
    _replacePayments(PaymentSplit.fit(payments, cartTotal));
  }

  void _replacePayments(List<Payment> next) {
    payments
      ..clear()
      ..addAll(next);
    _cartChanged();
  }

  void resetPayments() {
    payments.clear();
  }

  // ---- override gating (see reviewed spec, findings 1 & 11) ----
  /// Returns null if the rate is allowed, or a reason string if blocked/needs PIN.
  /// [pinApproved] short-circuits the discount gate after Owner PIN entry.
  String? checkRate(CartLine line, double rate, {bool pinApproved = false}) {
    final p = productOf(line.productId);
    if (p == null) return 'उत्पादन सापडले नाही · Product not found';
    final floor = p.floorRate(line.isBag);
    if (settings.floorOn && rate < floor) {
      return 'किमान भावाखाली · Below floor (min ₹${floor.round()})';
    }
    if (!pinApproved && settings.gateOverride) {
      final discPct = line.catalogRate == 0
          ? 0
          : (line.catalogRate - rate) / line.catalogRate * 100;
      if (discPct > settings.gateOverridePct) return 'NEEDS_PIN';
    }
    return null;
  }

  bool verifyOwnerPin(String pin) => pin == owner.pin;

  // ---- stock operations ----
  //
  // Every stock-affecting operation below follows the same shape:
  //   1. plan against a scratch copy ([_StockSim]) of the current quantities
  //      — nothing in [batches]/[stock]/[bills] is touched yet;
  //   2. collect the result as DELTAS in a [StockCommit];
  //   3. `await repo.commitStock(commit)` — Firestore re-reads every batch
  //      inside a transaction and rejects the whole commit if any would go
  //      negative (another device sold it first);
  //   4. only then apply the same deltas to the in-memory working copy.
  // So a failed save leaves both Firestore and the screen unchanged, and no
  // path ever overwrites stored stock with a stale local number.

  static String _insufficient(Product? p) =>
      'अपुरा साठा · Not enough sellable stock for ${p?.nameMr ?? ''}';

  /// Runs [commit] through the repository, then applies it locally.
  /// Returns an error message (nothing changed) or null on success.
  Future<String?> _commit(StockCommit commit) async {
    try {
      await repo.commitStock(commit);
    } on StockCommitException catch (e) {
      return e.message;
    } catch (e) {
      return _saveError(e);
    }
    _applyCommit(commit);
    return null;
  }

  /// User-facing text for a failed repository write (nothing was saved).
  static String _saveError(Object e) {
    final text = e.toString();
    if (text.contains('permission-denied')) {
      return 'परवानगी नाही — काहीही जतन झाले नाही · Permission denied for this login — nothing was saved';
    }
    return 'जतन झाले नाही · Could not save — $text';
  }

  /// Applies a successfully-committed [StockCommit] to the working copy.
  void _applyCommit(StockCommit c) {
    final touched = <String>{};
    for (final d in c.batches.values) {
      touched.add(d.productId);
      Batch? b;
      if (d.create != null) {
        b = d.create!;
        batches.add(b);
      } else {
        b = batchOf(d.batchId);
      }
      if (b != null) d.applyTo(b, c.at);
    }
    c.legacyStock.forEach((pid, d) {
      touched.add(pid);
      final s = stockOf(pid);
      s.bags += d.bags;
      s.looseKg = s.looseKg + d.looseKg;
      stock[pid] = s;
    });
    for (final l in c.logs) {
      _log(l);
    }
    for (final p in c.billPatches) {
      final i = bills.indexWhere((b) => b.id == p.id);
      if (i >= 0) {
        bills[i] = bills[i]
            .copyWith(status: p.status, replacedByBillId: p.replacedById);
      }
    }
    for (final b in c.newBills) {
      bills.insert(0, b);
    }
    for (final p in c.purchasePatches) {
      final i = purchases.indexWhere((x) => x.id == p.id);
      if (i >= 0) {
        purchases[i] = purchases[i]
            .copyWith(status: p.status, replacedByPurchaseId: p.replacedById);
      }
    }
    for (final p in c.newPurchases) {
      purchases.insert(0, p);
    }
    for (final l in c.ledger) {
      final cust = customers.where((x) => x.id == l.customerId).firstOrNull;
      if (cust == null) continue;
      cust.outstanding = (cust.outstanding + l.outstandingDelta)
          .clamp(0, double.infinity)
          .toDouble();
      cust.ledger.insert(0, l.entry);
    }
    // The transaction already moved the stored rollup by the same deltas.
    for (final pid in touched) {
      recomputeStockFor(pid, persist: false);
    }
  }

  bool _batchUsable(Batch b) => !b.isExpired && b.status != BatchStatus.blocked;

  /// Plans selling [lines] from [branchId] into [commit] — FEFO/FIFO order
  /// from [batchesOf], skipping expired/blocked batches and moving on to the
  /// next batch once one is exhausted. Quantities come from [sim], so a bill
  /// edit can reuse stock its own reversal just credited back. A line that
  /// spans batches becomes one [BillItem] per batch used.
  List<BillItem> _sellLines(StockCommit commit, _StockSim sim,
      List<CartLine> lines, String? branchId, String billId, String? note) {
    final items = <BillItem>[];
    for (final l in lines) {
      final p = productOf(l.productId);
      if (p == null) {
        throw const _OpError('उत्पादन सापडले नाही · Product not found');
      }
      final w = p.bagWeightKg;
      final all = batchesOf(l.productId, branchId: branchId);

      if (all.isEmpty) {
        // Legacy product with no batches at all (not yet migrated) — sell
        // from the aggregate rollup, as before batch tracking existed.
        final s = sim.legacy(l.productId);
        final available = l.isBag ? s.bags.toDouble() : s.bags * w + s.loose;
        if (available + 1e-9 < l.qty) throw _OpError(_insufficient(p));
        final d = commit.legacy(l.productId);
        if (l.isBag) {
          s.bags -= l.qty.round();
          d.bags -= l.qty.round();
        } else {
          var opened = 0;
          while (s.loose + 1e-9 < l.qty && s.bags > 0) {
            s.bags -= 1;
            s.loose += w;
            opened++;
          }
          s.loose -= l.qty;
          d.bags -= opened;
          d.looseKg += opened * w - l.qty;
        }
        commit.logs.add(StockLog(
          id: _uid('L'),
          productId: l.productId,
          type: StockLogType.sale,
          bagsDelta: l.isBag ? -l.qty.round() : 0,
          looseKgDelta: l.isBag ? 0 : -l.qty,
          billId: billId,
          note: note,
          branchId: branchId,
          at: commit.at,
        ));
        items.add(BillItem(
          productId: l.productId,
          saleType: l.saleType,
          qty: l.qty,
          catalogRate: l.catalogRate,
          rate: l.rate,
          lineTotal: l.lineTotal,
        ));
        continue;
      }

      var remaining = l.qty;
      for (final b in all) {
        if (remaining <= 1e-9) break;
        if (!_batchUsable(b)) continue;
        final q = sim.batch(b);
        final available = l.isBag ? q.bags.toDouble() : q.bags * w + q.loose;
        if (available <= 1e-9) continue;
        final take = remaining < available ? remaining : available;
        final d = commit.batch(b.id, b.productId);
        if (l.isBag) {
          final n = take.round();
          q.bags -= n;
          d.bagsAvailable -= n;
          d.bagsSold += n;
        } else {
          // Open this SAME batch's bags as needed — the kg sold must trace
          // back to the batch it actually came from (spec §7).
          while (q.loose + 1e-9 < take && q.bags > 0) {
            q.bags -= 1;
            q.loose += w;
            d.bagsAvailable -= 1;
            d.looseKgAvailable += w;
            commit.logs.add(StockLog(
              id: _uid('L'),
              productId: l.productId,
              type: StockLogType.bagOpened,
              bagsDelta: -1,
              looseKgDelta: w.toDouble(),
              note: 'auto on sale',
              branchId: b.branchId,
              batchId: b.id,
              at: commit.at,
            ));
          }
          q.loose -= take;
          d.looseKgAvailable -= take;
          d.looseKgSold += take;
        }
        commit.logs.add(StockLog(
          id: _uid('L'),
          productId: l.productId,
          type: StockLogType.sale,
          bagsDelta: l.isBag ? -take.round() : 0,
          looseKgDelta: l.isBag ? 0 : -take,
          billId: billId,
          note: note,
          branchId: b.branchId,
          batchId: b.id,
          supplierId: b.supplierId,
          at: commit.at,
        ));
        items.add(BillItem(
          productId: l.productId,
          saleType: l.saleType,
          qty: take,
          catalogRate: l.catalogRate,
          rate: l.rate,
          lineTotal: l.rate * take,
          batchId: b.id,
          batchNo: b.batchNo,
          supplierId: b.supplierId,
          expiry: b.expiry,
        ));
        remaining -= take;
      }
      if (remaining > 1e-4) throw _OpError(_insufficient(p));
    }
    return items;
  }

  /// Which batch FEFO/FIFO would sell [productId] from next — shown in the
  /// sales entry grid so the counter can see which lot goes out first.
  Batch? nextSaleBatch(String productId) {
    final p = productOf(productId);
    if (p == null) return null;
    return batchesOf(productId, branchId: activeBranchId)
        .where((b) => b.isSellable(p.bagWeightKg))
        .firstOrNull;
  }

  /// Credits everything [b] sold (minus any partial returns already
  /// credited) back to the exact batches it came from.
  void _reverseBill(StockCommit commit, _StockSim sim, Bill b, String note) {
    for (final it in b.items) {
      final r = it.qty - returnedSoFar(b, it);
      if (r <= 1e-9) continue;
      final isBag = it.saleType == SaleType.bag;
      final batch = it.batchId == null ? null : batchOf(it.batchId!);
      if (batch != null) {
        final q = sim.batch(batch);
        final d = commit.batch(batch.id, batch.productId);
        if (isBag) {
          q.bags += r.round();
          d.bagsAvailable += r.round();
          d.bagsSold -= r.round();
        } else {
          q.loose += r;
          d.looseKgAvailable += r;
          d.looseKgSold -= r;
        }
      } else {
        final q = sim.legacy(it.productId);
        final d = commit.legacy(it.productId);
        if (isBag) {
          q.bags += r.round();
          d.bags += r.round();
        } else {
          q.loose += r;
          d.looseKg += r;
        }
      }
      commit.logs.add(StockLog(
        id: _uid('L'),
        productId: it.productId,
        type: StockLogType.saleVoid,
        bagsDelta: isBag ? r.round() : 0,
        looseKgDelta: isBag ? 0 : r,
        billId: b.id,
        note: note,
        at: commit.at,
        branchId: b.branchId,
        batchId: it.batchId,
        supplierId: it.supplierId,
      ));
    }
  }

  /// Validates the current cart + payments. Returns an error or null.
  String? _checkCartAndPayments() {
    if (cart.isEmpty) return 'बिल रिकामे · Cart is empty';
    ensurePayments();
    // Exact to the paisa — never save more than the bill total.
    if (PaymentSplit.excess(payments, cartTotal) > 0) {
      return 'पेमेंट रक्कम बिलाच्या रकमेपेक्षा जास्त आहे · Payment amount cannot exceed the bill total.';
    }
    final left = PaymentSplit.remaining(payments, cartTotal);
    if (left > 0.5) {
      final amt = '₹${left.toStringAsFixed(left % 1 == 0 ? 0 : 2)}';
      return 'पेमेंट रक्कम जुळत नाही, बाकी $amt · Payment must equal total — $amt remaining';
    }
    final hasCredit =
        payments.any((p) => p.mode == PayMode.credit && p.amount > 0);
    if (hasCredit && cartCustomerId == null) {
      return 'उधारसाठी ग्राहक निवडा · Pick a customer for credit';
    }
    if (cartDueCollect > 0 && editingBillId == null) {
      if (cartCustomerId == null) {
        return 'मागील बाकीसाठी ग्राहक निवडा · Pick the customer whose due is paid';
      }
      if (!payments.any((p) => p.mode != PayMode.credit && p.amount > 0) &&
          payments.isNotEmpty &&
          cartTotal > 0) {
        return 'मागील बाकी जमा करण्यासाठी रोख / UPI निवडा · Choose Cash or UPI to collect the previous due';
      }
    }
    return null;
  }

  /// Empties the bill on screen and unlinks it from any draft — the next
  /// bill starts completely fresh. Saved drafts are not touched.
  void _resetCart() {
    _autosave?.cancel();
    _autosave = null;
    cart.clear();
    cartCustomerId = null;
    payments.clear();
    editingBillId = null;
    _link = null;
    cartDueCollect = 0;
    cartDirty = false;
    _billSeq++;
  }

  // ---- finalize sale (FEFO batch allocation + credit ledger) ----
  /// Saves the cart as a bill — or, while [editingBillId] is set, as the
  /// corrected revision of that bill (see [beginEditBill]).
  Future<SaleResult> finalizeSale() async {
    if (editingBillId != null) return _finalizeEdit();
    final invalid = _checkCartAndPayments();
    if (invalid != null) return SaleResult.failure(invalid);
    final branchId = activeBranchId;
    if (branchId == null) {
      return const SaleResult.failure(
          'शाखा निवडलेली नाही · No branch selected');
    }
    // Finalizing a draft: let a draft save that is still on its way land
    // first, so the commit checks the version this phone really holds.
    _autosave?.cancel();
    _autosave = null;
    await draftSavesSettled;
    final link = _link;
    // A draft holds no stock, so another sale may have used it meanwhile.
    String stockError(_OpError e) =>
        link == null ? e.message : '$_stockChangedSinceDraft\n${e.message}';

    // Dry run first so an unsellable cart fails before a bill number is
    // consumed (spec §19: fail the whole sale before anything is written).
    try {
      _sellLines(StockCommit(DateTime.now()), _StockSim(this), cart, branchId,
          '', null);
    } on _OpError catch (e) {
      return SaleResult.failure(stockError(e));
    }

    final int number;
    try {
      number = await repo.nextBillNumber();
    } catch (e) {
      return SaleResult.failure(_saveError(e));
    }
    final now = DateTime.now();
    final commit = StockCommit(now);
    final billId = _docId('BILL$number');
    final List<BillItem> items;
    try {
      items = _sellLines(commit, _StockSim(this), cart, branchId, billId, null);
    } on _OpError catch (e) {
      return SaleResult.failure(stockError(e));
    }
    commit.finalizedDraftId = link?.id;
    commit.finalizedDraftVersion = link?.version;
    final cust = cartCustomerId == null
        ? null
        : customers.where((c) => c.id == cartCustomerId).firstOrNull;
    final bill = Bill(
      id: billId,
      billNumber: number,
      customerId: cartCustomerId,
      customerName: cust?.name ?? '',
      items: items,
      subtotal: cartSubtotal,
      discountTotal: cartDiscount,
      total: cartTotal,
      payments: List.of(payments),
      at: now,
      staffId: repo.currentUserId ?? owner.id,
      branchId: branchId,
      previousDue: cust?.outstanding ?? 0,
      dueCollected: cust == null
          ? 0
          : (cartDueCollect > cust.outstanding
              ? cust.outstanding
              : cartDueCollect),
    );
    commit.newBills.add(bill);
    // The previous due paid with this bill: a khata payment received (not
    // a sale), saved in the same commit — first, so it never counts
    // against this bill's own credit.
    if (bill.dueCollected > 0 && cust != null) {
      commit.ledger.add(LedgerChange(
          cust.id,
          LedgerEntry(
              type: 'repayment',
              amount: bill.dueCollected,
              billId: bill.id,
              note: 'bill #$number',
              at: now),
          -bill.dueCollected));
    }
    if (bill.creditAmount > 0 && cust != null) {
      commit.ledger.add(LedgerChange(
          cust.id,
          LedgerEntry(
              type: 'credit-sale',
              amount: bill.creditAmount,
              billId: bill.id,
              note: 'bill #$number',
              at: now),
          bill.creditAmount));
    }
    _auditIn(commit, 'BILL_FINALIZED', 'BILL', bill.id,
        note: 'bill #$number ${bill.total}');
    final overridden = cart.where((l) => l.isOverridden).length;
    if (overridden > 0) {
      _auditIn(commit, 'PRICE_OVERRIDE', 'BILL', bill.id,
          note: '$overridden line(s) at a bill-only rate');
    }
    final error = await _commit(commit);
    if (error != null) {
      // Nothing was written — the draft (if any) is still there to retry.
      notifyListeners();
      return SaleResult.failure(error);
    }
    if (link != null) drafts.removeWhere((d) => d.id == link.id);
    _resetCart();
    notifyListeners();
    return SaleResult.success(bill);
  }

  static const _stockChangedSinceDraft =
      '⚠️ उपलब्ध साठा बदलला आहे. पुन्हा तपासा · Available stock has changed. Please check again.';

  // ---- draft bills ----
  //
  // A draft is saved work: lines, party and the planned payment split. It
  // never touches stock, payments, khata or reports — only finalizing it
  // (the normal sale above) does, and that same commit removes the draft.

  /// Every saved, unfinished bill (📝).
  List<DraftBill> drafts = [];
  Object? draftsError;

  List<DraftBill> get draftsNewestFirst =>
      List.of(drafts)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// The draft the bill on screen was saved as or opened from; null for a
  /// bill never saved as a draft. While set, changes save automatically.
  _DraftLink? _link;
  String? get currentDraftId => _link?.id;
  String? get currentDraftLabel => _link == null ? null : 'D${_link!.number}';

  /// The bill on screen changed since it was opened or last saved.
  bool cartDirty = false;

  /// Leaving the bill now would lose work (an edit of a finalized bill is
  /// a separate workflow and never becomes a draft).
  bool get hasUnsavedBill =>
      editingBillId == null &&
      cartDirty &&
      (cart.isNotEmpty || cartCustomerId != null || _link != null);

  /// How long after the last change a linked draft saves itself — typing a
  /// quantity is one write, not one per keystroke.
  static const autosaveDelay = Duration(seconds: 3);
  Timer? _autosave;

  // Bumped whenever the screen switches to a different bill; a save that
  // finishes after the switch must not re-link the new bill.
  int _billSeq = 0;
  int _changeSeq = 0;

  // Draft writes run one at a time, so each sees the version before it.
  // Null when no write is queued — a lone save starts at once.
  Future<void>? _draftLock;

  /// Resolves once every queued draft save has finished.
  Future<void> get draftSavesSettled => _draftLock ?? Future<void>.value();

  void _cartChanged() {
    if (editingBillId == null) {
      cartDirty = true;
      _changeSeq++;
      if (_link != null) {
        _autosave?.cancel();
        _autosave = Timer(autosaveDelay, () {
          _autosave = null;
          if (_link != null && cartDirty) unawaited(saveDraft());
        });
      }
    }
    notifyListeners();
  }

  Future<DraftResult> _locked(Future<DraftResult> Function() write) {
    final prev = _draftLock;
    final run = prev == null ? write() : prev.then((_) => write());
    late final Future<void> tail;
    tail = run.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_draftLock, tail)) _draftLock = null;
    });
    _draftLock = tail;
    return run;
  }

  _BillSnap _snap() => _BillSnap(
        lines: [
          for (final l in cart)
            DraftLine(
                productId: l.productId,
                saleType: l.saleType,
                qty: l.qty,
                catalogRate: l.catalogRate,
                rate: l.rate),
        ],
        customerId: cartCustomerId,
        payments: List.of(payments),
        dueCollect: cartDueCollect,
        billSeq: _billSeq,
        changeSeq: _changeSeq,
      );

  /// Saves the bill on screen as a draft — a new one ("D…"), or the next
  /// version of the draft it came from. Writes nothing else.
  Future<DraftResult> saveDraft() {
    _autosave?.cancel();
    _autosave = null;
    if (editingBillId != null) {
      return Future.value(const DraftResult.failure(
          'दुरुस्त होणारे बिल ड्राफ्ट होत नाही · A bill being corrected cannot be saved as a draft'));
    }
    // The snapshot is taken when the write runs, so it has the latest changes.
    return _locked(() => _writeDraft(_snap(), live: true));
  }

  Future<DraftResult> _writeDraft(_BillSnap snap,
      {_DraftLink? link, required bool live}) async {
    link = live ? _link : link;
    final now = DateTime.now();
    final uid = repo.currentUserId;
    final cust = snap.customerId == null ? null : partyOf(snap.customerId!);
    DraftBill build(_DraftLink l, int version) => DraftBill(
          id: l.id,
          number: l.number,
          customerId: snap.customerId,
          customerName: cust?.name ?? '',
          lines: snap.lines,
          payments: snap.payments,
          dueCollect: snap.dueCollect,
          createdAt: l.createdAt,
          updatedAt: now,
          createdBy: l.createdBy,
          updatedBy: uid,
          version: version,
        );
    final DraftBill draft;
    try {
      if (link == null) {
        final n = await repo.nextDraftNumber();
        link = _DraftLink(_docId('DRAFT$n'), n, 0, now, uid);
        draft = build(link, 1);
        await repo.saveDraft(draft);
        // Once per draft — later autosaves of it are not audited.
        _auditNow('DRAFT_CREATED', 'DRAFT', draft.id);
      } else {
        draft = build(link, link.version + 1);
        await repo.saveDraft(draft, expectedVersion: link.version);
      }
    } on DraftConflictException catch (e) {
      // Nothing was overwritten. The bill stays on screen, unlinked, so
      // "Save Draft" keeps it as a new draft.
      if (live && _billSeq == snap.billSeq) _link = null;
      final goneId = link?.id;
      if (e.missing) drafts.removeWhere((d) => d.id == goneId);
      notifyListeners();
      return DraftResult.failure(e.missing
          ? 'हा ड्राफ्ट दुसऱ्या फोनवर पूर्ण / हटवला गेला · This draft was finalized or deleted on another phone'
          : 'हा ड्राफ्ट दुसऱ्या फोनवर बदलला आहे — तुमचे बदल नवीन ड्राफ्ट म्हणून सेव्ह करा · This draft was changed on another phone — save yours as a new draft');
    } catch (e) {
      return DraftResult.failure(_saveError(e));
    }
    link.version = draft.version;
    final i = drafts.indexWhere((d) => d.id == draft.id);
    if (i >= 0) {
      drafts[i] = draft;
    } else {
      drafts.add(draft);
    }
    if (live && _billSeq == snap.billSeq) {
      _link = link;
      if (_changeSeq == snap.changeSeq) cartDirty = false;
    }
    notifyListeners();
    return DraftResult.success(draft);
  }

  /// Keeps the bill on screen safe before the screen switches to another:
  /// unsaved changes are saved as a draft (never carried over, never lost).
  Future<DraftResult>? _detachCurrentBill() {
    _autosave?.cancel();
    _autosave = null;
    if (!hasUnsavedBill) return null;
    final snap = _snap();
    final link = _link;
    return _locked(() => _writeDraft(snap, link: link, live: false));
  }

  /// "+ नवीन बिल": opens a completely empty bill — no party, products,
  /// rates or payment from any earlier bill. Saved drafts stay as they are;
  /// a bill in progress with unsaved changes is first saved as a draft
  /// (screens save it themselves first, so they can report a failure).
  void startNewBill() {
    _detachCurrentBill();
    _resetCart();
    notifyListeners();
  }

  /// Leaves the bill on screen without saving (after "Discard", or once it
  /// was saved). Saved drafts are not touched.
  void closeBill() {
    _resetCart();
    notifyListeners();
  }

  /// "▶ पुढे सुरू करा": loads draft [id] exactly as saved (party, lines,
  /// units, bill rates, planned payment). It stays a draft until finalized.
  String? openDraft(String id) {
    final d = drafts.where((x) => x.id == id).firstOrNull;
    if (d == null) return 'ड्राफ्ट सापडला नाही · Draft not found';
    if (_link?.id == id && editingBillId == null) return null; // already open
    _detachCurrentBill();
    _resetCart();
    for (final l in d.lines) {
      cart.add(CartLine(
          productId: l.productId,
          saleType: l.saleType,
          qty: l.qty,
          catalogRate: l.catalogRate,
          rate: l.rate));
    }
    cartCustomerId = d.customerId;
    payments.addAll(d.payments);
    // Never more than the customer owes today.
    cartDueCollect = d.dueCollect > cartPreviousDue ? cartPreviousDue : d.dueCollect;
    _link = _DraftLink(d.id, d.number, d.version, d.createdAt, d.createdBy);
    notifyListeners();
    return null;
  }

  /// "🗑 ड्राफ्ट हटवा" — removes only the draft; stock, khata, payments,
  /// reports and finalized bills are untouched.
  Future<String?> deleteDraft(String id) async {
    if (_link?.id == id) _resetCart();
    try {
      await draftSavesSettled;
      await repo.deleteDraft(id);
    } catch (e) {
      notifyListeners();
      return _saveError(e);
    }
    _auditNow('DRAFT_DELETED', 'DRAFT', id);
    drafts.removeWhere((d) => d.id == id);
    notifyListeners();
    return null;
  }

  /// Reloads drafts (another phone may have added or finished some).
  Future<void> refreshDrafts() async {
    final seq = _bootstrapSeq;
    try {
      final loaded = await repo.loadDrafts();
      if (seq != _bootstrapSeq) return; // another store/user meanwhile
      drafts = loaded;
      draftsError = null;
    } catch (e) {
      if (seq != _bootstrapSeq) return;
      draftsError = e;
      debugPrint('[pend] drafts load error: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _storeWatch?.cancel();
    _noteWatch?.cancel();
    super.dispose();
  }

  // ---- edit bill ----
  /// The bill currently loaded into the cart for correction, if any.
  String? editingBillId;

  bool billHasReturns(Bill b) =>
      logs.any((l) => l.type == StockLogType.returned && l.billId == b.id);

  /// Null when [b] may be edited/voided by this login, else the reason.
  String? whyBillLocked(Bill b) {
    if (b.status == BillStatus.voided) {
      return b.wasReplaced
          ? 'हे बिल आधीच दुरुस्त केले · Already corrected — open the latest revision'
          : 'बिल रद्द केले आहे · Bill is void';
    }
    if (!hasOwnerRights) {
      return 'फक्त मालक बदल करू शकतात · Only the owner (admin) can edit or void bills';
    }
    return null;
  }

  /// Why [b] can't be edited (null when it can). Bills with a recorded
  /// partial return must be voided or returned instead — rewriting them
  /// would double-count the returned stock.
  String? whyBillNotEditable(Bill b) {
    final locked = whyBillLocked(b);
    if (locked != null) return locked;
    if (billHasReturns(b)) {
      return 'या बिलावर परतावा नोंदवला आहे · This bill has returns — void it or record another return instead';
    }
    return null;
  }

  /// Loads [billId] into the cart (merging lines FEFO split across batches)
  /// so it can be corrected; [finalizeSale] then saves it as a revision.
  String? beginEditBill(String billId) {
    final b = bills.where((x) => x.id == billId).firstOrNull;
    if (b == null) return 'बिल सापडले नाही · Bill not found';
    final why = whyBillNotEditable(b);
    if (why != null) return why;
    // A new bill in progress is kept as a draft, never mixed into the edit.
    _detachCurrentBill();
    _resetCart();
    for (final it in b.items) {
      final existing = cart
          .where((l) =>
              l.productId == it.productId &&
              l.saleType == it.saleType &&
              l.rate == it.rate &&
              l.catalogRate == it.catalogRate)
          .firstOrNull;
      if (existing != null) {
        existing.qty = double.parse((existing.qty + it.qty).toStringAsFixed(3));
      } else {
        cart.add(CartLine(
          productId: it.productId,
          saleType: it.saleType,
          qty: it.qty,
          catalogRate: it.catalogRate,
          rate: it.rate,
        ));
      }
    }
    cartCustomerId = b.customerId;
    payments
      ..clear()
      ..addAll(b.payments);
    editingBillId = b.id;
    notifyListeners();
    return null;
  }

  /// Abandons an edit in progress (the original bill is untouched).
  void cancelEditBill() {
    _resetCart();
    notifyListeners();
  }

  /// Saves the cart as the corrected revision of [editingBillId]: in ONE
  /// commit, the original's stock goes back to its batches, the corrected
  /// lines are sold again (FEFO), the original is marked void +
  /// replaced-by, and khata credit is reversed and re-applied.
  Future<SaleResult> _finalizeEdit() async {
    final orig = bills.where((b) => b.id == editingBillId).firstOrNull;
    if (orig == null) {
      return const SaleResult.failure('बिल सापडले नाही · Bill not found');
    }
    final why = whyBillNotEditable(orig);
    if (why != null) return SaleResult.failure(why);
    final invalid = _checkCartAndPayments();
    if (invalid != null) return SaleResult.failure(invalid);

    final now = DateTime.now();
    final commit = StockCommit(now);
    final sim = _StockSim(this);
    final rev = orig.revision + 1;
    final rootId = orig.originalBillId ?? orig.id;
    final newId = '$rootId-R$rev';
    final branchId = orig.branchId ?? activeBranchId;
    final List<BillItem> items;
    try {
      _reverseBill(commit, sim, orig, 'edit #${orig.billNumber}');
      items = _sellLines(commit, sim, cart, branchId, newId,
          'edit #${orig.billNumber} rev $rev');
    } on _OpError catch (e) {
      return SaleResult.failure(e.message);
    }
    final cust = cartCustomerId == null
        ? null
        : customers.where((c) => c.id == cartCustomerId).firstOrNull;
    final bill = Bill(
      id: newId,
      billNumber: orig.billNumber,
      customerId: cartCustomerId,
      customerName: cust?.name ?? '',
      items: items,
      subtotal: cartSubtotal,
      discountTotal: cartDiscount,
      total: cartTotal,
      payments: List.of(payments),
      at: orig.at, // a correction keeps the bill's original date
      staffId: repo.currentUserId ?? owner.id,
      branchId: branchId,
      revision: rev,
      originalBillId: rootId,
      editedAt: now,
      // The due paid with the original stays as recorded.
      previousDue: orig.previousDue,
      dueCollected: orig.dueCollected,
    );
    commit.newBills.add(bill);
    commit.billPatches.add(
        StatusPatch(orig.id, status: BillStatus.voided, replacedById: newId));
    if (orig.customerId != null && orig.creditAmount > 0) {
      commit.ledger.add(LedgerChange(
          orig.customerId!,
          LedgerEntry(
              type: 'repayment',
              amount: orig.creditAmount,
              billId: orig.id,
              note: 'edit #${orig.billNumber} (old)',
              at: now),
          -orig.creditAmount));
    }
    if (cust != null && bill.creditAmount > 0) {
      commit.ledger.add(LedgerChange(
          cust.id,
          LedgerEntry(
              type: 'credit-sale',
              amount: bill.creditAmount,
              billId: bill.id,
              note: 'bill #${orig.billNumber} rev $rev',
              at: now),
          bill.creditAmount));
    }
    _auditIn(commit, 'BILL_CORRECTED', 'BILL', bill.id,
        note: 'replaces ${orig.id}');
    final error = await _commit(commit);
    if (error != null) {
      notifyListeners();
      return SaleResult.failure(error);
    }
    _resetCart();
    notifyListeners();
    return SaleResult.success(bill);
  }

  /// Voids [billId]: its stock goes back to the exact batches it came from
  /// (less anything already returned), khata credit is reversed, and the
  /// bill is kept, marked void. Returns an error message or null.
  Future<String?> voidBill(String billId) async {
    final b = bills.where((x) => x.id == billId).firstOrNull;
    if (b == null) return 'बिल सापडले नाही · Bill not found';
    final why = whyBillLocked(b);
    if (why != null) return why;
    final now = DateTime.now();
    final commit = StockCommit(now);
    _reverseBill(commit, _StockSim(this), b, 'bill #${b.billNumber}');
    commit.billPatches.add(StatusPatch(b.id, status: BillStatus.voided));
    if (b.customerId != null && b.creditAmount > 0) {
      commit.ledger.add(LedgerChange(
          b.customerId!,
          LedgerEntry(
              type: 'repayment',
              amount: b.creditAmount,
              billId: b.id,
              note: 'void #${b.billNumber}',
              at: now),
          -b.creditAmount));
    }
    // The previous due "paid" with this bill goes back on the khata.
    if (b.customerId != null && b.dueCollected > 0) {
      commit.ledger.add(LedgerChange(
          b.customerId!,
          LedgerEntry(
              type: 'credit-sale',
              amount: b.dueCollected,
              billId: b.id,
              note: 'void #${b.billNumber}',
              at: now),
          b.dueCollected));
    }
    _auditIn(commit, 'BILL_VOID', 'BILL', b.id);
    final error = await _commit(commit);
    notifyListeners();
    return error;
  }

  /// How much of one bill line has already been returned — scans existing
  /// [StockLogType.returned] entries logged against this exact bill+line
  /// (matched by billId + batchId + productId), so a partial return can
  /// never exceed what that line actually sold (spec §13/§19). A legacy
  /// line with no batchId is matched by billId + productId alone.
  double returnedSoFar(Bill bill, BillItem item) => logs
      .where((l) =>
          l.type == StockLogType.returned &&
          l.billId == bill.id &&
          l.productId == item.productId &&
          l.batchId == item.batchId)
      .fold(0.0, (s, l) => s + l.bagsDelta.abs() + l.looseKgDelta.abs());

  /// Partial sales return (spec §13): credits [qty] back to the exact batch
  /// [item] was sold from (falling back to the aggregate rollup for a
  /// legacy line with no batch), and never lets the total returned on this
  /// line exceed what it originally sold. Does not alter the original bill
  /// — bills are an immutable audit record; the return is its own logged
  /// movement, traceable back to [bill] via [StockLog.billId].
  Future<String?> returnSaleLine(Bill bill, BillItem item, double qty) async {
    if (qty <= 0) return 'योग्य प्रमाण टाका · Enter a valid quantity';
    final already = returnedSoFar(bill, item);
    if (already + qty > item.qty + 0.0001) {
      return 'मूळ विक्रीपेक्षा जास्त परतावा शक्य नाही · Cannot return more than sold';
    }
    final isBag = item.saleType == SaleType.bag;
    final commit = StockCommit(DateTime.now());
    final batch = item.batchId == null ? null : batchOf(item.batchId!);
    if (batch != null) {
      final d = commit.batch(batch.id, batch.productId);
      if (isBag) {
        d.bagsAvailable += qty.round();
        d.bagsReturned += qty.round();
      } else {
        d.looseKgAvailable += qty;
        d.looseKgReturned += qty;
      }
    } else {
      final d = commit.legacy(item.productId);
      if (isBag) {
        d.bags += qty.round();
      } else {
        d.looseKg += qty;
      }
    }
    commit.logs.add(StockLog(
      id: _uid('L'),
      productId: item.productId,
      type: StockLogType.returned,
      bagsDelta: isBag ? qty.round() : 0,
      looseKgDelta: isBag ? 0 : qty,
      billId: bill.id,
      note: 'partial return · bill #${bill.billNumber}',
      at: commit.at,
      branchId: bill.branchId,
      batchId: item.batchId,
      supplierId: item.supplierId,
    ));
    _auditIn(commit, 'RETURN_CREATED', 'BILL', bill.id,
        note: '${item.productId} × $qty');
    final error = await _commit(commit);
    notifyListeners();
    return error;
  }

  // ---- purchases ----
  Purchase? purchaseOf(String id) =>
      purchases.where((p) => p.id == id).firstOrNull;

  /// Checks a purchase before saving. Returns an error message or null.
  String? validatePurchase({
    required String? supplierId,
    required List<PurchaseLineInput> lines,
    double otherCharges = 0,
  }) {
    if (supplierId == null || supplierOf(supplierId) == null) {
      return 'खरेदी पार्टी निवडा · Pick the purchase party';
    }
    final filled = lines.where((l) => !l.isBlank).toList();
    if (filled.isEmpty) {
      return 'खरेदीमध्ये किमान एक उत्पादन जोडा · Add at least one product to the purchase';
    }
    for (var i = 0; i < filled.length; i++) {
      final l = filled[i];
      String row(String mr, String en) =>
          'ओळ ${i + 1}: $mr · Row ${i + 1}: $en';
      final p = l.productId == null ? null : productOf(l.productId!);
      if (p == null) return row('उत्पादन निवडा', 'pick a product');
      if (l.bags <= 0) return row('गोणी संख्या टाका', 'enter bags');
      if (l.rate <= 0) return row('खरेदी भाव टाका', 'enter the purchase rate');
      if (p.batchTrackingEnabled && l.batchNo.trim().isEmpty) {
        return row('बॅच क्र. टाका', 'enter the batch no.');
      }
      if (p.expiryTrackingEnabled && l.expiry == null) {
        return row('एक्सपायरी निवडा', 'pick the expiry date');
      }
    }
    if (otherCharges < 0) {
      return 'इतर खर्च चुकीचा · Other charges cannot be negative';
    }
    return null;
  }

  /// Receives [lines] into batches (creating a batch, or topping up the
  /// active batch with the same branch + product + batch no.) and records
  /// the actual purchase rate as the batch's unit cost.
  List<PurchaseItem> _receiveLines(
    StockCommit commit,
    _StockSim sim,
    List<PurchaseLineInput> lines, {
    required String branchId,
    required String supplierId,
    required int number,
    required String note,
  }) {
    final items = <PurchaseItem>[];
    final created = <String, Batch>{}; // "product|batchNo" -> new batch
    final supplierName = supplierOf(supplierId)?.name;
    for (final l in lines) {
      final p = productOf(l.productId!)!;
      final batchNo =
          l.batchNo.trim().isEmpty ? 'PUR-$number' : l.batchNo.trim();
      final key = '${p.id}|$batchNo';
      var target = created[key] ??
          batches
              .where((b) =>
                  b.branchId == branchId &&
                  b.productId == p.id &&
                  b.batchNo == batchNo &&
                  b.status == BatchStatus.active)
              .firstOrNull;
      final BatchDelta d;
      if (target == null) {
        target = Batch(
          id: _uid('batch'),
          branchId: branchId,
          productId: p.id,
          supplierId: supplierId,
          batchNo: batchNo,
          manufactureDate: l.manufactureDate,
          expiry: l.expiry,
          unitCost: l.rate,
          createdAt: commit.at,
          updatedAt: commit.at,
        );
        created[key] = target;
        d = commit.batches[target.id] =
            BatchDelta(target.id, p.id, create: target);
      } else {
        d = commit.batch(target.id, p.id);
      }
      d.bagsAvailable += l.bags;
      d.bagsReceived += l.bags;
      d.unitCost = l.rate; // latest purchase cost wins
      sim.batch(target).bags += l.bags;
      commit.logs.add(StockLog(
        id: _uid('L'),
        productId: p.id,
        type: StockLogType.purchase,
        bagsDelta: l.bags,
        cost: l.rate,
        batchNo: batchNo,
        expiry: l.expiry ?? target.expiry,
        supplier: supplierName,
        note: note,
        at: commit.at,
        branchId: branchId,
        batchId: target.id,
        supplierId: supplierId,
      ));
      items.add(PurchaseItem(
        productId: p.id,
        brandId: p.brandId,
        bags: l.bags,
        rate: l.rate,
        amount: l.amount,
        batchId: target.id,
        batchNo: batchNo,
        expiry: l.expiry ?? target.expiry,
        manufactureDate: l.manufactureDate,
        sellingRateAtPurchase: p.fullBagPrice,
      ));
    }
    return items;
  }

  /// Takes a purchase's bags back out of the batches they went into.
  void _reversePurchase(
      StockCommit commit, _StockSim sim, Purchase p, String note) {
    for (final it in p.items) {
      final b = batchOf(it.batchId);
      if (b == null) {
        throw _OpError('बॅच सापडली नाही · Batch ${it.batchNo} not found');
      }
      final d = commit.batch(b.id, b.productId);
      d.bagsAvailable -= it.bags;
      d.bagsReceived -= it.bags;
      sim.batch(b).bags -= it.bags;
      commit.logs.add(StockLog(
        id: _uid('L'),
        productId: it.productId,
        type: StockLogType.purchaseReturn,
        bagsDelta: -it.bags,
        cost: it.rate,
        batchNo: it.batchNo,
        note: note,
        at: commit.at,
        branchId: b.branchId,
        batchId: b.id,
        supplierId: p.supplierId,
      ));
    }
  }

  /// Null when [p] may be edited/voided by this login, else the reason.
  String? whyPurchaseLocked(Purchase p) {
    if (p.status == BillStatus.voided) {
      return p.replacedByPurchaseId != null
          ? 'ही खरेदी आधीच दुरुस्त केली · Already corrected — open the latest revision'
          : 'खरेदी रद्द केली आहे · Purchase is void';
    }
    if (!hasOwnerRights) {
      return 'फक्त मालक बदल करू शकतात · Only the owner (admin) can edit or void purchases';
    }
    return null;
  }

  String _alreadySold(_StockSim sim) {
    final id = sim.firstNegativeBatch();
    final b = id == null ? null : batchOf(id);
    return 'या खरेदीतील गोणी आधीच विकल्या · Bags from this purchase were already sold${b == null ? '' : ' (batch ${b.batchNo})'} — reduce the change or record a return instead';
  }

  /// Saves a multi-line purchase bill — or, with [editingPurchaseId], the
  /// corrected revision of that purchase (old bags out, new bags in, one
  /// commit). Stock, batches, purchase rate and the purchase party are all
  /// persisted through [Repository.commitStock].
  Future<PurchaseResult> savePurchase({
    required String? supplierId,
    String supplierBillNo = '',
    DateTime? purchaseDate,
    required List<PurchaseLineInput> lines,
    double otherCharges = 0,
    String? editingPurchaseId,
    BillPhotoChange photo = const BillPhotoChange.keep(),
  }) async {
    final invalid = validatePurchase(
        supplierId: supplierId, lines: lines, otherCharges: otherCharges);
    if (invalid != null) return PurchaseResult.failure(invalid);
    Purchase? orig;
    if (editingPurchaseId != null) {
      orig = purchaseOf(editingPurchaseId);
      if (orig == null) {
        return const PurchaseResult.failure(
            'खरेदी सापडली नाही · Purchase not found');
      }
      final why = whyPurchaseLocked(orig);
      if (why != null) return PurchaseResult.failure(why);
    }
    final branchId = orig?.branchId ?? activeBranchId;
    if (branchId == null) {
      return const PurchaseResult.failure(
          'शाखा निवडलेली नाही · No branch selected');
    }
    final filled = lines.where((l) => !l.isBlank).toList();
    // The number comes from its own small transaction (meta/counters); if
    // that is refused, stop here — nothing else has been written yet.
    final int number;
    try {
      number = orig?.purchaseNumber ?? await repo.nextPurchaseNumber();
    } catch (e) {
      return PurchaseResult.failure(_saveError(e));
    }
    final rev = orig == null ? 0 : orig.revision + 1;
    final rootId = orig?.originalPurchaseId ?? orig?.id;
    final id = orig == null ? _docId('PUR$number') : '$rootId-R$rev';
    final now = DateTime.now();
    final commit = StockCommit(now);
    final sim = _StockSim(this);
    final List<PurchaseItem> items;
    try {
      if (orig != null) {
        _reversePurchase(commit, sim, orig, 'purchase #$number edited');
      }
      items = _receiveLines(commit, sim, filled,
          branchId: branchId,
          supplierId: supplierId!,
          number: number,
          note: 'purchase #$number${rev > 0 ? ' rev $rev' : ''}'
              '${supplierBillNo.trim().isEmpty ? '' : ' · bill ${supplierBillNo.trim()}'}');
    } on _OpError catch (e) {
      return PurchaseResult.failure(e.message);
    }
    if (sim.firstNegativeBatch() != null) {
      return PurchaseResult.failure(_alreadySold(sim));
    }
    // Bill photo: an edit carries the original's photo forward unless it is
    // replaced or removed. A new photo is uploaded under this purchase's id
    // before the commit, so the purchase is written with it in one go.
    var photoUrl = orig?.billPhotoUrl, photoPath = orig?.billPhotoPath;
    StoredPhoto? uploaded;
    if (photo.remove) {
      photoUrl = photoPath = null;
    } else if (photo.bytes != null) {
      final bad = photoProblem(photo.bytes!);
      if (bad != null) return PurchaseResult.failure(bad);
      try {
        uploaded = await repo.uploadPurchaseBillPhoto(
            id, photo.bytes!, photoTypeOf(photo.bytes!)!);
      } catch (_) {
        return const PurchaseResult.failure(
            'बिल फोटो अपलोड झाला नाही — पुन्हा प्रयत्न करा किंवा फोटो काढा · Bill photo upload failed — try again or remove the photo');
      }
      photoUrl = uploaded.url;
      photoPath = uploaded.path;
    }
    final totals = PurchaseTotals.of(filled, otherCharges: otherCharges);
    final purchase = Purchase(
      id: id,
      purchaseNumber: number,
      supplierId: supplierId,
      supplierName: supplierOf(supplierId)?.name ?? '',
      supplierBillNo: supplierBillNo.trim(),
      purchaseDate: purchaseDate ?? orig?.purchaseDate ?? now,
      items: items,
      subtotal: totals.subtotal,
      otherCharges: otherCharges,
      total: totals.grandTotal,
      branchId: branchId,
      staffId: repo.currentUserId ?? owner.id,
      createdAt: now,
      revision: rev,
      originalPurchaseId: rootId,
      billPhotoUrl: photoUrl,
      billPhotoPath: photoPath,
    );
    commit.newPurchases.add(purchase);
    if (orig != null) {
      commit.purchasePatches.add(
          StatusPatch(orig.id, status: BillStatus.voided, replacedById: id));
    }
    _auditIn(commit, orig == null ? 'PURCHASE_CREATED' : 'PURCHASE_CORRECTED',
        'PURCHASE', id);
    final error = await _commit(commit);
    notifyListeners();
    if (error != null) {
      // Nothing was saved — don't leave the just-uploaded photo behind.
      if (uploaded != null) {
        try {
          await repo.deletePurchaseBillPhoto(uploaded.path);
        } catch (_) {}
      }
      return PurchaseResult.failure(error);
    }
    return PurchaseResult.success(purchase);
  }

  /// The supplier-bill photo saved with [p], or null when it has none (or
  /// the file can no longer be read).
  Future<Uint8List?> purchaseBillPhoto(Purchase p) async {
    if (!p.hasBillPhoto) return null;
    try {
      return await repo.loadPurchaseBillPhoto(p.billPhotoPath!);
    } catch (_) {
      return null;
    }
  }

  /// Voids a purchase: its bags come back out of stock. Refused when those
  /// bags have already been sold (stock can never go negative).
  Future<String?> voidPurchase(String purchaseId) async {
    final p = purchaseOf(purchaseId);
    if (p == null) return 'खरेदी सापडली नाही · Purchase not found';
    final why = whyPurchaseLocked(p);
    if (why != null) return why;
    final commit = StockCommit(DateTime.now());
    final sim = _StockSim(this);
    try {
      _reversePurchase(commit, sim, p, 'purchase #${p.purchaseNumber} void');
    } on _OpError catch (e) {
      return e.message;
    }
    if (sim.firstNegativeBatch() != null) return _alreadySold(sim);
    commit.purchasePatches.add(StatusPatch(p.id, status: BillStatus.voided));
    _auditIn(commit, 'PURCHASE_VOID', 'PURCHASE', p.id);
    final error = await _commit(commit);
    notifyListeners();
    return error;
  }

  // ---- inventory ----
  /// Records a purchase against a real [Batch] (spec §1/§5/§17: Branch →
  /// Product → Supplier → Batch → Expiry → Stock). If a still-active batch
  /// with the same (branch, product, batchNo) already exists, tops it up
  /// (spec §5 "handle it according to existing inventory rules instead of
  /// blindly creating duplicate batches") rather than creating a second one;
  /// otherwise creates a new batch. Always keeps the cross-branch [Stock]
  /// rollup in sync.
  ///
  /// Validation (spec §19) is the caller's job for user-facing messages
  /// (see [StockInScreen]) — this asserts the same invariants defensively so
  /// a programming mistake fails loudly rather than corrupting inventory.
  /// Throws [StateError] if the commit is rejected.
  Future<void> stockIn({
    required String branchId,
    required String productId,
    required String supplierId,
    String? batchNo,
    DateTime? manufactureDate,
    DateTime? expiry,
    int bags = 0,
    double looseKg = 0,
    double? cost,
  }) async {
    assert(bags > 0 || looseKg > 0, 'stockIn: quantity must be > 0');
    final product = productOf(productId);
    assert(product != null, 'stockIn: unknown product');
    if (product == null) return;
    assert(
        !product.batchTrackingEnabled ||
            (batchNo != null && batchNo.isNotEmpty),
        'stockIn: batch number required for this product');
    assert(!product.expiryTrackingEnabled || expiry != null,
        'stockIn: expiry required for this product');

    final commit = StockCommit(DateTime.now());
    Batch? target;
    if (batchNo != null && batchNo.isNotEmpty) {
      target = batches
          .where((b) =>
              b.branchId == branchId &&
              b.productId == productId &&
              b.batchNo == batchNo &&
              b.status == BatchStatus.active)
          .firstOrNull;
    }
    final BatchDelta d;
    if (target != null) {
      d = commit.batch(target.id, productId);
    } else {
      target = Batch(
        id: _uid('batch'),
        branchId: branchId,
        productId: productId,
        supplierId: supplierId,
        batchNo: batchNo ?? 'B-${commit.at.millisecondsSinceEpoch}',
        manufactureDate: manufactureDate,
        expiry: expiry,
        unitCost: cost ?? 0,
        createdAt: commit.at,
        updatedAt: commit.at,
      );
      d = commit.batches[target.id] =
          BatchDelta(target.id, productId, create: target);
    }
    d.bagsReceived += bags;
    d.bagsAvailable += bags;
    d.looseKgAvailable += looseKg;
    if (cost != null) d.unitCost = cost; // latest purchase cost wins
    commit.logs.add(StockLog(
      id: _uid('L'),
      productId: productId,
      type: StockLogType.purchase,
      bagsDelta: bags,
      looseKgDelta: looseKg,
      cost: cost,
      batchNo: target.batchNo,
      expiry: expiry,
      supplier: supplierOf(supplierId)?.name,
      at: commit.at,
      branchId: branchId,
      batchId: target.id,
      supplierId: supplierId,
    ));
    _auditIn(commit, 'STOCK_IN', 'BATCH', target.id);
    final error = await _commit(commit);
    notifyListeners();
    if (error != null) throw StateError(error);
  }

  Future<void> openBag(String productId) async {
    final s = stockOf(productId);
    final p = productOf(productId)!;
    if (s.bags < 1) return;
    s.bags -= 1;
    s.looseKg += p.bagWeightKg;
    stock[productId] = s;
    await repo.setStock(s);
    _log(StockLog(
        id: _uid('L'),
        productId: productId,
        type: StockLogType.bagOpened,
        bagsDelta: -1,
        looseKgDelta: p.bagWeightKg.toDouble(),
        note: 'manual',
        at: DateTime.now()));
    notifyListeners();
  }

  Future<void> adjustStock(
      String productId, int bagsDelta, double kgDelta, String note) async {
    final s = stockOf(productId);
    s.bags = (s.bags + bagsDelta).clamp(0, 1 << 30);
    s.looseKg = (s.looseKg + kgDelta).clamp(0, double.infinity).toDouble();
    stock[productId] = s;
    await repo.setStock(s);
    _log(StockLog(
        id: _uid('L'),
        productId: productId,
        type: StockLogType.adjustment,
        bagsDelta: bagsDelta,
        looseKgDelta: kgDelta,
        note: note,
        at: DateTime.now()));
    _auditNow('STOCK_ADJUSTED', 'PRODUCT', productId,
        note: '$bagsDelta bags, $kgDelta kg · $note');
    notifyListeners();
  }

  /// Branch-to-branch stock transfer (spec §14). Deducts [bags]/[looseKg]
  /// from [sourceBatchId] and creates or tops up a batch in [destBranchId]
  /// carrying the same batch no./expiry/cost/supplier, linked back via
  /// [Batch.sourceBatchId] — never merged into a destination batch that
  /// came from a *different* origin batch, so distinct lots stay distinct.
  Future<String?> transferStock(String sourceBatchId, String destBranchId,
      {int bags = 0, double looseKg = 0}) async {
    final source = batchOf(sourceBatchId);
    if (source == null) return 'बॅच सापडली नाही · Batch not found';
    if (bags <= 0 && looseKg <= 0) {
      return 'योग्य प्रमाण टाका · Enter a valid quantity';
    }
    if (bags > source.bagsAvailable ||
        looseKg > source.looseKgAvailable + 0.0001) {
      return 'उपलब्ध साठ्यापेक्षा जास्त हस्तांतरण शक्य नाही · Cannot transfer more than available';
    }
    final commit = StockCommit(DateTime.now());
    final out = commit.batch(source.id, source.productId);
    out.bagsAvailable -= bags;
    out.looseKgAvailable -= looseKg;
    commit.logs.add(StockLog(
      id: _uid('L'),
      productId: source.productId,
      type: StockLogType.transferOut,
      bagsDelta: -bags,
      looseKgDelta: -looseKg,
      note: 'to branch $destBranchId',
      at: commit.at,
      branchId: source.branchId,
      batchId: source.id,
      supplierId: source.supplierId,
    ));

    // Same batch no. already open at the destination (from an earlier
    // transfer of this same lot) — top it up rather than duplicating it.
    var dest = batches
        .where((b) =>
            b.branchId == destBranchId &&
            b.sourceBatchId == source.id &&
            b.status == BatchStatus.active)
        .firstOrNull;
    final BatchDelta inn;
    if (dest != null) {
      inn = commit.batch(dest.id, dest.productId);
    } else {
      dest = Batch(
        id: _uid('batch'),
        branchId: destBranchId,
        productId: source.productId,
        supplierId: source.supplierId,
        batchNo: source.batchNo,
        manufactureDate: source.manufactureDate,
        expiry: source.expiry,
        unitCost: source.unitCost,
        sourceBatchId: source.id,
        createdAt: commit.at,
        updatedAt: commit.at,
      );
      inn = commit.batches[dest.id] =
          BatchDelta(dest.id, dest.productId, create: dest);
    }
    inn.bagsReceived += bags;
    inn.bagsAvailable += bags;
    inn.looseKgAvailable += looseKg;
    commit.logs.add(StockLog(
      id: _uid('L'),
      productId: source.productId,
      type: StockLogType.transferIn,
      bagsDelta: bags,
      looseKgDelta: looseKg,
      note: 'from branch ${source.branchId}',
      at: commit.at,
      branchId: destBranchId,
      batchId: dest.id,
      supplierId: source.supplierId,
    ));
    _auditIn(commit, 'STOCK_TRANSFER', 'BATCH', source.id,
        note: 'to ${dest.id}');
    final error = await _commit(commit);
    notifyListeners();
    return error;
  }

  // ---- party master (customers = sales, suppliers = purchase) ----
  List<Party> get parties => Party.combine(customers, suppliers);
  List<Party> get salesParties => parties.where((p) => p.type.isSales).toList();
  List<Party> get purchaseParties =>
      parties.where((p) => p.type.isPurchase && p.active).toList();
  Party? partyOf(String id) => parties.where((p) => p.id == id).firstOrNull;

  /// Next free numeric party code (highest numeric code + 1).
  String nextPartyCode() {
    var max = 0;
    for (final p in parties) {
      final n = int.tryParse(p.code.trim());
      if (n != null && n > max) max = n;
    }
    return '${max + 1}';
  }

  bool partyCodeTaken(String code, {String? exceptId}) {
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return false;
    return parties
        .any((p) => p.id != exceptId && p.code.trim().toLowerCase() == c);
  }

  /// Creates or updates a party. The sales side is a [Customer] (khata),
  /// the purchase side a [Supplier]; a party of [PartyType.both] has one of
  /// each sharing the same id. Roles are only ever added here, never
  /// removed — a party with sales/purchase history must stay findable.
  Future<Party> saveParty({
    String? id,
    required String name,
    String code = '',
    String mobile = '',
    String address = '',
    required PartyType type,
  }) async {
    final partyId = id ?? _uid('party');
    final existingCustomer =
        customers.where((c) => c.id == partyId).firstOrNull;
    final supplierIdx = suppliers.indexWhere((s) => s.id == partyId);
    if (existingCustomer != null || type.isSales) {
      final c = existingCustomer ?? Customer(id: partyId, name: name);
      c
        ..name = name
        ..mobile = mobile
        ..code = code
        ..address = address;
      if (existingCustomer == null) customers.add(c);
      await repo.upsertCustomer(c);
    }
    if (supplierIdx >= 0 || type.isPurchase) {
      final s = supplierIdx >= 0
          ? suppliers[supplierIdx].copyWith(
              name: name, code: code, mobile: mobile, address: address)
          : Supplier(
              id: partyId,
              name: name,
              code: code,
              mobile: mobile,
              address: address,
              createdAt: DateTime.now());
      if (supplierIdx >= 0) {
        suppliers[supplierIdx] = s;
      } else {
        suppliers.add(s);
      }
      await repo.upsertSupplier(s);
    }
    notifyListeners();
    return partyOf(partyId)!;
  }

  // ---- customers / khata ----
  Future<Customer> saveCustomer(
      {String? id,
      required String name,
      String mobile = '',
      String? code,
      String? address}) async {
    if (id != null) {
      final c = customers.firstWhere((x) => x.id == id);
      c.name = name;
      c.mobile = mobile;
      if (code != null) c.code = code;
      if (address != null) c.address = address;
      await repo.upsertCustomer(c);
      notifyListeners();
      return c;
    }
    final c = Customer(
        id: _uid('c'),
        name: name,
        mobile: mobile,
        code: code ?? nextPartyCode(),
        address: address ?? '');
    customers.add(c);
    await repo.upsertCustomer(c);
    notifyListeners();
    return c;
  }

  Future<void> recordRepayment(
      String customerId, double amount, PayMode mode) async {
    final c = customers.firstWhere((x) => x.id == customerId);
    c.outstanding =
        (c.outstanding - amount).clamp(0, double.infinity).toDouble();
    final entry = LedgerEntry(
        type: 'repayment', amount: amount, note: mode.name, at: DateTime.now());
    c.ledger.insert(0, entry);
    await repo.addLedgerEntry(c.id, entry, c.outstanding);
    notifyListeners();
  }

  double get totalOutstanding =>
      customers.fold(0.0, (s, c) => s + c.outstanding);

  // ---- catalogue ----
  Future<Product> saveProduct(
      {String? id,
      required String brandId,
      required String name,
      required String nameMr,
      required int bagWeightKg,
      required double fullBagPrice,
      required double perKgPrice,
      double costPrice = 0,
      double minPriceFloor = 0,
      int? lowThreshold,
      Object? photoUrl = _notProvided,
      Object? category = _notProvided}) async {
    late final Product saved;
    if (id != null) {
      final idx = products.indexWhere((p) => p.id == id);
      final old = products[idx];
      if (old.fullBagPrice != fullBagPrice || old.perKgPrice != perKgPrice) {
        _auditNow('PRICE_CHANGED', 'PRODUCT', id,
            note: 'bag ${old.fullBagPrice}→$fullBagPrice, '
                'kg ${old.perKgPrice}→$perKgPrice');
      }
      products[idx] = products[idx].copyWith(
        brandId: brandId,
        name: name,
        nameMr: nameMr,
        bagWeightKg: bagWeightKg,
        fullBagPrice: fullBagPrice,
        perKgPrice: perKgPrice,
        costPrice: costPrice,
        minPriceFloor: minPriceFloor,
        lowStockThresholdBags: lowThreshold,
        photoUrl: identical(photoUrl, _notProvided)
            ? products[idx].photoUrl
            : photoUrl as String?,
        category: identical(category, _notProvided)
            ? products[idx].category
            : category as String?,
      );
      await repo.upsertProduct(products[idx]);
      saved = products[idx];
    } else {
      final np = Product(
        id: _uid('p'),
        brandId: brandId,
        name: name,
        nameMr: nameMr,
        bagWeightKg: bagWeightKg,
        fullBagPrice: fullBagPrice,
        perKgPrice: perKgPrice,
        costPrice: costPrice,
        minPriceFloor: minPriceFloor,
        lowStockThresholdBags: lowThreshold ?? settings.lowDefaultBags,
        qr: 'PEND-${DateTime.now().millisecondsSinceEpoch}',
        photoUrl:
            identical(photoUrl, _notProvided) ? null : photoUrl as String?,
        category:
            identical(category, _notProvided) ? null : category as String?,
        // Same as the bootstrap migration does for unassigned products —
        // done now so a product created mid-session is stockable at once.
        branchIds: activeBranchId == null ? const [] : [activeBranchId!],
      );
      products.add(np);
      stock[np.id] = Stock(productId: np.id);
      await repo.upsertProduct(np, initialStock: stock[np.id]);
      saved = np;
    }
    notifyListeners();
    return saved;
  }

  Future<void> deleteProduct(String id) async {
    products.removeWhere((p) => p.id == id);
    stock.remove(id);
    await repo.deleteProduct(id);
    notifyListeners();
  }

  Future<void> saveBrand(
      {String? id, required String name, required String nameMr}) async {
    if (id != null) {
      final idx = brands.indexWhere((b) => b.id == id);
      brands[idx] = brands[idx].copyWith(name: name, nameMr: nameMr);
      await repo.upsertBrand(brands[idx]);
    } else {
      final b = Brand(id: _uid('b'), name: name, nameMr: nameMr);
      brands.add(b);
      await repo.upsertBrand(b);
    }
    notifyListeners();
  }

  // ---- quick-create masters (from Purchase / Stock entry pickers) ----
  static String _normName(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// The existing brand whose English or Marathi name matches (ignoring
  /// case and extra spaces), else null.
  Brand? brandNamed(String name, [String nameMr = '', String? exceptId]) {
    final keys = {_normName(name), _normName(nameMr)}..remove('');
    return brands
        .where((b) =>
            b.id != exceptId &&
            (keys.contains(_normName(b.name)) ||
                keys.contains(_normName(b.nameMr))))
        .firstOrNull;
  }

  /// The existing product under [brandId] with the same English or Marathi
  /// name, else null. The same name under another brand is a different
  /// product ("Special" can exist for two brands).
  Product? productNamed(String brandId, String name, [String nameMr = '']) {
    final keys = {_normName(name), _normName(nameMr)}..remove('');
    return products
        .where((p) =>
            p.brandId == brandId &&
            (keys.contains(_normName(p.name)) ||
                keys.contains(_normName(p.nameMr))))
        .firstOrNull;
  }

  static const _ownerOnlyMasters =
      'फक्त मालक नवीन ब्रँड / उत्पादन जोडू शकतात · Only the owner can add brands or products';

  /// Creates a brand after checking owner rights (same as the Firestore
  /// rule on /brands) and that the name isn't already used.
  /// A brand name as it should be stored: trimmed, single spaces.
  static String cleanName(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  static const _dupBrand = 'हा ब्रँड आधीच आहे · This brand already exists';
  static const _photoFailed =
      'फोटो अपलोड झाला नाही — पुन्हा प्रयत्न करा किंवा फोटो काढा · Photo upload failed — try again or remove the photo';

  /// Creates a brand after checking owner rights (same as the Firestore
  /// rule on /brands) and that the name isn't already used. [photo] is an
  /// optional logo.
  Future<MasterResult<Brand>> createBrand(
      {required String name,
      String nameMr = '',
      bool active = true,
      BillPhotoChange photo = const BillPhotoChange.keep()}) async {
    final en = cleanName(name), mr = cleanName(nameMr);
    if (!hasOwnerRights) return const MasterResult.failure(_ownerOnlyMasters);
    if (en.isEmpty && mr.isEmpty) {
      return const MasterResult.failure(
          'ब्रँडचे नाव टाका · Enter the brand name');
    }
    final existing = brandNamed(en, mr);
    if (existing != null) {
      return MasterResult.failure(existing.active
          ? _dupBrand
          : 'हा ब्रँड आधीच आहे पण निष्क्रिय आहे — कॅटलॉगमध्ये सक्रिय करा · This brand already exists but is inactive — make it Active in the Catalogue');
    }
    final id = _uid('b');
    String? url;
    if (photo.bytes != null) {
      final bad = photoProblem(photo.bytes!);
      if (bad != null) return MasterResult.failure(bad);
      try {
        url = await repo.uploadBrandPhoto(
            id, photo.bytes!, photoTypeOf(photo.bytes!)!);
      } catch (_) {
        return const MasterResult.failure(_photoFailed);
      }
    }
    final b = Brand(
        id: id,
        name: en.isEmpty ? mr : en,
        nameMr: mr.isEmpty ? en : mr,
        active: active,
        photoUrl: url);
    await repo.upsertBrand(b);
    brands.add(b);
    notifyListeners();
    return MasterResult.success(b);
  }

  /// Edits a brand's names, active flag and/or photo (owner only; names
  /// must stay unique). Products keep their brand — nothing else changes.
  Future<MasterResult<Brand>> updateBrand(
    String id, {
    required String name,
    String nameMr = '',
    required bool active,
    BillPhotoChange photo = const BillPhotoChange.keep(),
  }) async {
    final idx = brands.indexWhere((b) => b.id == id);
    if (idx < 0) {
      return const MasterResult.failure('ब्रँड सापडला नाही · Brand not found');
    }
    if (!hasOwnerRights) return const MasterResult.failure(_ownerOnlyMasters);
    final en = cleanName(name), mr = cleanName(nameMr);
    if (en.isEmpty && mr.isEmpty) {
      return const MasterResult.failure(
          'ब्रँडचे नाव टाका · Enter the brand name');
    }
    if (brandNamed(en, mr, id) != null) {
      return const MasterResult.failure(_dupBrand);
    }
    final old = brands[idx];
    var url = old.photoUrl;
    if (photo.remove) {
      url = null;
    } else if (photo.bytes != null) {
      final bad = photoProblem(photo.bytes!);
      if (bad != null) return MasterResult.failure(bad);
      try {
        url = await repo.uploadBrandPhoto(
            id, photo.bytes!, photoTypeOf(photo.bytes!)!);
      } catch (_) {
        return const MasterResult.failure(_photoFailed);
      }
    }
    final next = old.copyWith(
        name: en.isEmpty ? mr : en,
        nameMr: mr.isEmpty ? en : mr,
        active: active,
        photoUrl: url);
    await repo.upsertBrand(next);
    brands[idx] = next;
    // The replaced/removed photo file is no longer referenced anywhere.
    if (old.photoUrl != null && old.photoUrl != url) {
      try {
        await repo.deleteBrandPhoto(old.photoUrl!);
      } catch (_) {}
    }
    notifyListeners();
    return MasterResult.success(next);
  }

  /// Brands offered when picking for a NEW sale / purchase.
  List<Brand> get activeBrands => brands.where((b) => b.active).toList();

  /// Whether [p] may be picked for a new sale / purchase (its brand is
  /// active). Existing stock, bills and reports are never affected.
  bool isProductSelectable(Product p) => brandOf(p.brandId)?.active ?? true;

  bool _productHasStock(String pid) {
    final s = stockOf(pid);
    if (s.bags != 0 || s.looseKg.abs() > 0.001) return true;
    return batches.any((b) =>
        b.productId == pid &&
        (b.bagsAvailable != 0 || b.looseKgAvailable.abs() > 0.001));
  }

  bool _productHasHistory(String pid) =>
      bills.any((b) => b.items.any((i) => i.productId == pid)) ||
      purchases.any((p) => p.items.any((i) => i.productId == pid)) ||
      batches.any((b) => b.productId == pid) ||
      logs.any((l) => l.productId == pid);

  /// Null when brand [id] may be deleted, else why not. Deleting is only
  /// for brands whose products (if any) hold NO stock and were never
  /// bought or sold — old bills keep pointing at their products, so a
  /// brand with history is made Inactive instead.
  String? whyBrandNotDeletable(String id) {
    if (!hasOwnerRights) return _ownerOnlyMasters;
    if (brandOf(id) == null) return 'ब्रँड सापडला नाही · Brand not found';
    if (historyLoading || historyError != null) {
      return 'इतिहास अजून लोड होत आहे — थोड्या वेळाने प्रयत्न करा · History is still loading — try again in a moment';
    }
    final ps = products.where((p) => p.brandId == id).toList();
    if (ps.any((p) => _productHasStock(p.id))) {
      return 'या ब्रँडच्या उत्पादनांचा साठा शिल्लक आहे — ब्रँड निष्क्रिय करा · Products of this brand still have stock — make the brand Inactive instead';
    }
    if (ps.any((p) => _productHasHistory(p.id))) {
      return 'या ब्रँडची जुनी बिले / खरेदी आहेत — ती जपण्यासाठी ब्रँड निष्क्रिय करा · This brand has past bills / purchases — make it Inactive to keep that history';
    }
    return null;
  }

  /// Deletes brand [id] and its (unused, zero-stock) products in one
  /// atomic write. Returns an error, or null when deleted.
  Future<String?> deleteBrand(String id) async {
    final why = whyBrandNotDeletable(id);
    if (why != null) return why;
    final brand = brandOf(id)!;
    final ids = [
      for (final p in products)
        if (p.brandId == id) p.id
    ];
    try {
      await repo.deleteBrand(id, productIds: ids);
    } catch (e) {
      return _saveError(e);
    }
    products.removeWhere((p) => ids.contains(p.id));
    for (final pid in ids) {
      stock.remove(pid);
    }
    brands.removeWhere((b) => b.id == id);
    if (brand.photoUrl != null) {
      try {
        await repo.deleteBrandPhoto(brand.photoUrl!);
      } catch (_) {}
    }
    notifyListeners();
    return null;
  }

  /// Creates a product under an EXISTING brand (never an orphan), rejecting
  /// a duplicate name within that brand. Selling prices go on the product;
  /// [costPrice] is only the default purchase rate.
  Future<MasterResult<Product>> createProduct({
    required String? brandId,
    required String name,
    String nameMr = '',
    required int bagWeightKg,
    required double fullBagPrice,
    double? perKgPrice,
    double costPrice = 0,
  }) async {
    final en = name.trim(), mr = nameMr.trim();
    if (!hasOwnerRights) return const MasterResult.failure(_ownerOnlyMasters);
    if (brandId == null || brandOf(brandId) == null) {
      return const MasterResult.failure('ब्रँड निवडा · Select a brand');
    }
    if (en.isEmpty && mr.isEmpty) {
      return const MasterResult.failure(
          'उत्पादनाचे नाव टाका · Enter the product name');
    }
    if (bagWeightKg <= 0) {
      return const MasterResult.failure(
          'गोणीचे वजन (किलो) टाका · Enter the bag weight (kg)');
    }
    if (fullBagPrice <= 0) {
      return const MasterResult.failure(
          'गोणीचा विक्री भाव टाका · Enter the bag selling price');
    }
    if (productNamed(brandId, en, mr) != null) {
      return const MasterResult.failure(
          'या ब्रँडमध्ये हे उत्पादन आधीच आहे · This product already exists under this brand');
    }
    final p = await saveProduct(
      brandId: brandId,
      name: en.isEmpty ? mr : en,
      nameMr: mr.isEmpty ? en : mr,
      bagWeightKg: bagWeightKg,
      fullBagPrice: fullBagPrice,
      perKgPrice: perKgPrice != null && perKgPrice > 0
          ? perKgPrice
          : double.parse((fullBagPrice / bagWeightKg).toStringAsFixed(2)),
      costPrice: costPrice,
    );
    return MasterResult.success(p);
  }

  Future<void> saveBranch(
      {String? id,
      required String name,
      required String nameMr,
      String address = '',
      bool active = true}) async {
    if (id != null) {
      final idx = branches.indexWhere((b) => b.id == id);
      branches[idx] = branches[idx].copyWith(
          name: name, nameMr: nameMr, address: address, active: active);
      await repo.upsertBranch(branches[idx]);
    } else {
      final b =
          Branch(id: _uid('br'), name: name, nameMr: nameMr, address: address);
      branches.add(b);
      await repo.upsertBranch(b);
      activeBranchId ??= b.id;
    }
    notifyListeners();
  }

  // ---- suppliers ----
  Future<Supplier> saveSupplier(
      {String? id,
      required String name,
      String mobile = '',
      String altMobile = '',
      String address = '',
      String gstin = '',
      String email = '',
      double openingBalance = 0,
      bool active = true,
      String notes = ''}) async {
    late final Supplier saved;
    if (id != null) {
      final idx = suppliers.indexWhere((s) => s.id == id);
      suppliers[idx] = suppliers[idx].copyWith(
        name: name,
        mobile: mobile,
        altMobile: altMobile,
        address: address,
        gstin: gstin,
        email: email,
        openingBalance: openingBalance,
        active: active,
        notes: notes,
      );
      saved = suppliers[idx];
    } else {
      saved = Supplier(
        id: _uid('sup'),
        code: nextPartyCode(),
        name: name,
        mobile: mobile,
        altMobile: altMobile,
        address: address,
        gstin: gstin,
        email: email,
        openingBalance: openingBalance,
        active: active,
        notes: notes,
        createdAt: DateTime.now(),
      );
      suppliers.add(saved);
    }
    await repo.upsertSupplier(saved);
    notifyListeners();
    return saved;
  }

  /// A supplier referenced by any batch/purchase can never be hard-deleted —
  /// only deactivated (spec: "Do NOT hard-delete a supplier that is
  /// referenced by purchases, stock batches, bills or accounting records").
  bool supplierHasHistory(String supplierId) =>
      batches.any((b) => b.supplierId == supplierId) ||
      logs.any((l) => l.supplierId == supplierId);

  Future<void> deleteSupplier(String id) async {
    if (supplierHasHistory(id)) {
      // Soft-delete: deactivate instead of removing the record.
      final idx = suppliers.indexWhere((s) => s.id == id);
      if (idx < 0) return;
      suppliers[idx] = suppliers[idx].copyWith(active: false);
      await repo.upsertSupplier(suppliers[idx]);
      notifyListeners();
      return;
    }
    suppliers.removeWhere((s) => s.id == id);
    await repo.deleteSupplier(id);
    notifyListeners();
  }

  Future<void> saveStaff(Staff member) async {
    // Store staff management never creates or promotes a super admin, and
    // a store user is always saved into the store being worked in.
    if (member.isSuperAdmin) {
      throw const StoreContextException(
          'A super admin can only be set up by a super admin.');
    }
    final before = staff.where((s) => s.id == member.id).firstOrNull;
    if (storeId != null) member = member.copyWith(storeId: storeId);
    final index = staff.indexWhere((s) => s.id == member.id);
    if (index < 0) {
      staff.add(member);
    } else {
      staff[index] = member;
    }
    try {
      await repo.upsertStaff(member);
      _auditNow(
          before == null
              ? 'STAFF_CREATED'
              : (before.active && !member.active
                  ? 'STAFF_DISABLED'
                  : 'STAFF_UPDATED'),
          'STAFF',
          member.id);
      final sid = storeId;
      if (sid != null) unawaited(platform.staffChanged(before, member, sid));
      notifyListeners();
    } catch (_) {
      if (index < 0) staff.removeWhere((s) => s.id == member.id);
      rethrow;
    }
  }

  // ---- settings ----
  Future<void> updateSettings(void Function(AppSettings) mutate) async {
    final next = settings.copy();
    mutate(next);
    await repo.saveSettings(next);
    settings = next;
    appLang = next.lang;
    notifyListeners();
  }

  Future<void> resetSampleData() async {
    await bootstrap();
    _resetCart();
    notifyListeners();
  }

  // ---- reports ----
  List<Bill> billsSince(DateTime since) =>
      finalBills.where((b) => b.at.isAfter(since)).toList();

  // ---- helpers ----
  void _log(StockLog l) => logs.insert(0, l);
  int _seq = 0;
  String _uid(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  /// Recomputes the cross-branch [Stock] rollup for one product from its
  /// [batches] — the batches are the source of truth; [stock] is only a fast,
  /// branch-agnostic read path for dashboard/product-list display (see the
  /// reviewed branch/batch/expiry architecture). Call after any batch
  /// mutation (stock-in, sale, void, adjustment, transfer).
  ///
  /// A product with no batches at all keeps its legacy aggregate as-is.
  /// [persist] is false after a [StockCommit], whose transaction already
  /// moved the stored rollup by the same amount.
  void recomputeStockFor(String productId, {bool persist = true}) {
    final own = batches.where((b) => b.productId == productId).toList();
    if (own.isEmpty) return;
    var bags = 0;
    var looseKg = 0.0;
    for (final b in own) {
      bags += b.bagsAvailable;
      looseKg += b.looseKgAvailable;
    }
    final s = Stock(
        productId: productId,
        bags: bags,
        looseKg: (looseKg * 1000).roundToDouble() / 1000);
    stock[productId] = s;
    if (persist) unawaited(repo.setStock(s));
  }

  // ---- migration: pre-branch/batch data → the new architecture ----
  // Runs once, automatically, the first time a shop with no branches yet is
  // opened (a fresh Firestore project or an existing one from before this
  // change) — see reviewed spec §18 "do not break existing data". Both steps
  // are idempotent (gated on "nothing to migrate yet") so a retried
  // bootstrap, or a shop that already has branches, never re-runs them.
  bool _migratedBranches = false;
  Future<void> _migrateBranchesAndProducts() async {
    if (_migratedBranches || branches.isNotEmpty) {
      _migratedBranches = true;
      return;
    }
    _migratedBranches = true;
    final main =
        Branch(id: _uid('br'), name: 'Main Branch', nameMr: 'मुख्य शाखा');
    branches.add(main);
    await repo.upsertBranch(main);
    for (var i = 0; i < products.length; i++) {
      if (products[i].branchIds.isNotEmpty) continue;
      products[i] = products[i].copyWith(branchIds: [main.id]);
      await repo.upsertProduct(products[i]);
    }
  }

  /// Step two of the migration — needs [batches] (history-tier) to know
  /// whether it has already run. For every product with real stock but no
  /// batch yet, creates exactly ONE legacy batch holding that current
  /// quantity (see the reviewed migration strategy: this deliberately does
  /// NOT try to reconstruct one batch per historical purchase log, since the
  /// old aggregate model never tracked remaining-quantity-per-purchase and
  /// guessing would misstate it — historical StockLogs stay exactly as they
  /// are, untouched, as a read-only audit trail).
  bool _migratedBatches = false;
  Future<void> _migrateLegacyStockToBatches() async {
    if (_migratedBatches || batches.isNotEmpty) {
      _migratedBatches = true;
      return;
    }
    _migratedBatches = true;
    final mainBranchId = activeBranchId ?? branches.firstOrNull?.id;
    if (mainBranchId == null) return; // no branch to attach legacy stock to
    final now = DateTime.now();
    for (final p in products) {
      final s = stockOf(p.id);
      if (s.bags <= 0 && s.looseKg <= 0) continue;
      final b = Batch(
        id: _uid('batch'),
        branchId: mainBranchId,
        productId: p.id,
        batchNo: 'LEGACY-${p.id}',
        unitCost: p.costPrice,
        bagsReceived: s.bags,
        bagsAvailable: s.bags,
        looseKgAvailable: s.looseKg,
        createdAt: now,
        updatedAt: now,
      );
      batches.add(b);
      await repo.upsertBatch(b);
    }
  }
}

const Object _notProvided = Object();

/// A business-rule failure while planning a stock operation (nothing has
/// been written yet).
class _OpError implements Exception {
  final String message;
  const _OpError(this.message);
}

class _Qty {
  int bags;
  double loose;
  _Qty(this.bags, this.loose);
}

/// Scratch copy of available quantities for planning one operation, so a
/// plan never mutates the real working copy before the commit succeeds.
class _StockSim {
  final AppState app;
  final Map<String, _Qty> _batches = {};
  final Map<String, _Qty> _legacy = {};
  _StockSim(this.app);

  _Qty batch(Batch b) => _batches.putIfAbsent(
      b.id, () => _Qty(b.bagsAvailable, b.looseKgAvailable));

  _Qty legacy(String productId) => _legacy.putIfAbsent(productId, () {
        final s = app.stockOf(productId);
        return _Qty(s.bags, s.looseKg);
      });

  /// A batch the plan would leave below zero, if any.
  String? firstNegativeBatch() {
    for (final e in _batches.entries) {
      if (e.value.bags < 0 || e.value.loose < -0.001) return e.key;
    }
    return null;
  }
}

/// Which saved draft the bill on screen belongs to; [version] is the one
/// last read or written, checked on the next save.
class _DraftLink {
  final String id;
  final int number;
  int version;
  final DateTime createdAt;
  final String? createdBy;
  _DraftLink(
      this.id, this.number, this.version, this.createdAt, this.createdBy);
}

/// The bill on screen at one moment, for a draft save.
class _BillSnap {
  final List<DraftLine> lines;
  final String? customerId;
  final List<Payment> payments;
  final double dueCollect;
  final int billSeq;
  final int changeSeq;
  const _BillSnap({
    required this.lines,
    required this.customerId,
    required this.payments,
    required this.dueCollect,
    required this.billSeq,
    required this.changeSeq,
  });
}

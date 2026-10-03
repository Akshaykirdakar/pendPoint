import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/firestore_repository.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'models/app_settings.dart';
import 'state/app_state.dart';
import 'ui/screens/sign_in_screen.dart';
import 'ui/screens/super_admin_screens.dart';
import 'ui/root_shell.dart';
import 'utils/theme.dart';
import 'utils/lang.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(PendApp(repo: FirestoreRepository(), requireAuthentication: true));
}

class PendApp extends StatelessWidget {
  final Repository repo;
  final bool requireAuthentication;
  const PendApp({
    required this.repo,
    this.requireAuthentication = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // AppState (and its Provider) is created unconditionally, right here at
    // the top, regardless of auth state. It must NEVER be created only
    // inside an authenticated branch further down the tree — on web,
    // Flutter can eagerly build a leftover/restored route's initState
    // (e.g. after a fresh sign-in) in the same frame the tree is still
    // assembling, and any screen that reads Provider<AppState> before a
    // conditionally-created Provider has mounted throws
    // ProviderNotFoundException. Keeping one Provider alive for the whole
    // app lifetime removes that whole class of race.
    return ChangeNotifierProvider(
      // Auth-required path: bootstrap is deferred to _AuthenticationGate,
      // which (re)triggers it once Firebase Auth actually has a user (it
      // needs an authenticated request to satisfy firestore.rules).
      // Non-auth path (demo mode / tests, InMemoryRepository): there is no
      // gate to trigger it, so bootstrap immediately as the old code did.
      create: (_) {
        final app = AppState(repo);
        if (!requireAuthentication) app.bootstrap();
        return app;
      },
      child: Consumer<AppState>(
        builder: (context, app, _) {
          final mode = switch (app.settings.theme) {
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
            AppThemeMode.system => ThemeMode.system,
          };
          return MaterialApp(
            title: 'पेंड Point',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, app.settings.colorTheme),
            darkTheme: buildTheme(Brightness.dark, app.settings.colorTheme),
            themeMode: mode,
            // Settings → Font size: scales every text through Flutter's
            // text scaler (on top of the phone's own accessibility size),
            // so layouts reflow — nothing is zoomed with a transform.
            builder: (context, child) => AppTextScale(
                fontSize: app.settings.fontSize, child: child!),
            // Flutter's own texts (date picker, OK/Cancel, back tooltip)
            // follow the shop's language: Marathi unless English-only.
            locale: app.settings.lang == AppLang.en
                ? const Locale('en')
                : const Locale('mr'),
            supportedLocales: const [Locale('mr'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: requireAuthentication
                ? const SessionNavigator(child: _AuthenticationGate())
                : (app.loading ? const _Splash() : const RootShell()),
          );
        },
      ),
    );
  }
}

/// Closes every screen opened on top of the first one when the session
/// ends or changes (sign-out, "All stores", opening another store), so the
/// sign-in page / store list / new store is what shows — not a leftover
/// Settings screen of the previous session.
class SessionNavigator extends StatefulWidget {
  final Widget child;
  const SessionNavigator({required this.child, super.key});
  @override
  State<SessionNavigator> createState() => _SessionNavigatorState();
}

class _SessionNavigatorState extends State<SessionNavigator> {
  AppState? _app;
  int _epoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!identical(app, _app)) {
      _app?.removeListener(_changed);
      _app = app..addListener(_changed);
      _epoch = app.sessionEpoch;
    }
  }

  void _changed() {
    final epoch = _app!.sessionEpoch;
    if (epoch == _epoch) return;
    _epoch = epoch;
    if (!mounted) return;
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) nav.popUntil((r) => r.isFirst);
  }

  @override
  void dispose() {
    _app?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows sign-in until Firebase Auth has a user, then (re)bootstraps
/// [AppState] from Firestore for that user and shows the shop once loaded.
/// Does NOT create its own Provider — see the comment in [PendApp].
class _AuthenticationGate extends StatefulWidget {
  const _AuthenticationGate();

  @override
  State<_AuthenticationGate> createState() => _AuthenticationGateState();
}

class _AuthenticationGateState extends State<_AuthenticationGate> {
  String? _bootstrappedUid;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // If Firebase Auth's own stream never emits (e.g. a hung
            // persistence/session lookup on web), this is where it sits
            // forever — surface *that* instead of an unlabeled splash.
            return _Splash(
                label: tr('साइन-इन तपासत आहे... · Checking sign-in...'));
          }
          if (snapshot.hasError) {
            return _DataLoadFailure(error: snapshot.error!);
          }
          final user = snapshot.data;
          if (user == null) {
            if (_bootstrappedUid != null) {
              // Signed out (here or elsewhere): forget the previous user's
              // store, data and cart before anyone else signs in.
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => context.read<AppState>().clearSession());
            }
            _bootstrappedUid = null;
            return const SignInScreen();
          }
          // Start (or restart, for a different user) the session exactly
          // once: profile → active? → role → store → store active? → data.
          // The Consumer below is always present to catch every
          // notifyListeners() that follows (see the note in PendApp).
          if (_bootstrappedUid != user.uid) {
            _bootstrappedUid = user.uid;
            debugPrint('[pend] starting session for uid=${user.uid}');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<AppState>().startSession().then(
                    (_) => debugPrint('[pend] session ready'),
                  );
            });
          }
          return const SessionScreen();
        },
      );
}

/// What a signed-in user sees, by [AppState.session]: the super-admin
/// dashboard, their store, or why they can't get in. Public so the routing
/// can be tested without Firebase.
class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AppState>(
        builder: (context, app, _) => switch (app.session) {
              SessionState.none || SessionState.checking => _Splash(
                  label: tr('खाते तपासत आहे... · Checking your account...')),
              SessionState.noProfile => _AccountBlocked(
                  icon: '🔒',
                  title: L('कर्मचारी खाते नाही', 'No staff profile'),
                  text: L(
                      'या लॉगिनसाठी कर्मचारी खाते तयार केलेले नाही. मालकाशी संपर्क करा.',
                      'This login has no staff profile yet. Please contact the administrator.')),
              SessionState.disabled => _AccountBlocked(
                  icon: '⛔',
                  title: L('खाते बंद आहे', 'Account disabled'),
                  text: L('तुमचे खाते बंद केले आहे. मालकाशी संपर्क करा.',
                      'Your account has been disabled. Please contact the administrator.')),
              SessionState.noStore => _AccountBlocked(
                  icon: '🏪',
                  title: L('दुकान नेमलेले नाही', 'No store assigned'),
                  text: L(
                      'तुमच्या खात्याला दुकान नेमलेले नाही. मालकाशी संपर्क करा.',
                      'Your account is not linked to a store. Please contact the administrator.')),
              SessionState.storeInactive => _AccountBlocked(
                  key: const ValueKey('store-inactive'),
                  icon: '🏪',
                  title: L('दुकान बंद आहे', 'Store inactive'),
                  text: L('हे दुकान सध्या बंद आहे. कृपया मालकाशी संपर्क करा.',
                      'This store is currently inactive. Please contact the administrator.')),
              SessionState.error =>
                _DataLoadFailure(error: app.bootstrapError ?? 'error'),
              SessionState.superAdmin => const SuperAdminHome(),
              SessionState.store => app.loading
                  ? _Splash(
                      label: tr('दुकानाचा डेटा आणत आहे... · Loading shop data...'))
                  : app.bootstrapError != null
                      ? _DataLoadFailure(error: app.bootstrapError!)
                      // A new store starts with an empty catalogue — the
                      // owner adds products from inside the app.
                      : const RootShell(),
            },
      );
}

/// Signed in, but not allowed in (no profile, disabled, no or inactive
/// store): says why, and offers sign-out — no store data is loaded.
class _AccountBlocked extends StatelessWidget {
  final String icon;
  final String title;
  final String text;
  const _AccountBlocked(
      {required this.icon, required this.title, required this.text, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(icon, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.read<AppState>().signOut(),
                child: Text(L('लॉगआउट', 'Sign out')),
              ),
            ]),
          ),
        ),
      );
}

class _DataLoadFailure extends StatelessWidget {
  final Object error;
  const _DataLoadFailure({required this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 52),
                const SizedBox(height: 16),
                Text(L('दुकानाचा डेटा आला नाही', 'Could not load shop data'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  L('इंटरनेट व कर्मचारी खाते तपासा, मग पुन्हा लॉगिन करा.',
                      'Check the Firebase staff account and Firestore rules, then sign in again.'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(error.toString(),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final app = context.read<AppState>();
                    app.session == SessionState.store
                        ? app.bootstrap()
                        : app.startSession();
                  },
                  child: Text(L('पुन्हा प्रयत्न', 'Retry')),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.read<AppState>().signOut(),
                  child: Text(L('लॉगआउट', 'Sign out')),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Splash extends StatelessWidget {
  final String? label;
  const _Splash({this.label});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.c.brand,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🌾', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text('पेंड Point',
                style: baloo(
                    size: 26,
                    weight: FontWeight.w800,
                    color: context.c.brandInk)),
            if (label != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: context.c.brandInk),
              ),
              const SizedBox(height: 10),
              Text(label!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.c.brandInk.withValues(alpha: 0.9),
                      fontSize: 12.5)),
            ],
          ]),
        ),
      );
}

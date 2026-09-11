import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'data/firestore_repository.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'models/app_settings.dart';
import 'state/app_state.dart';
import 'ui/screens/sign_in_screen.dart';
import 'ui/root_shell.dart';
import 'utils/theme.dart';

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
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: mode,
            home: requireAuthentication
                ? const _AuthenticationGate()
                : (app.loading ? const _Splash() : const RootShell()),
          );
        },
      ),
    );
  }
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
            return const _Splash(label: 'साइन-इन तपासत आहे... · Checking sign-in...');
          }
          if (snapshot.hasError) {
            return _DataLoadFailure(error: snapshot.error!);
          }
          final user = snapshot.data;
          if (user == null) {
            _bootstrappedUid = null;
            return const SignInScreen();
          }
          // Kick off (or re-kick off, for a different user) exactly once.
          if (_bootstrappedUid != user.uid) {
            _bootstrappedUid = user.uid;
            debugPrint('[pend] bootstrapping AppState for uid=${user.uid}');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<AppState>().bootstrap().then(
                    (_) => debugPrint('[pend] bootstrap finished'),
                  );
            });
            return const _Splash(label: 'दुकानाचा डेटा आणत आहे... · Loading shop data...');
          }
          return Consumer<AppState>(
            builder: (context, app, _) {
              if (app.loading) {
                return const _Splash(label: 'दुकानाचा डेटा आणत आहे... · Loading shop data...');
              }
              if (app.bootstrapError != null) {
                return _DataLoadFailure(error: app.bootstrapError!);
              }
              return const RootShell();
            },
          );
        },
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
                Text('Could not load shop data',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Check the Firebase staff account and Firestore rules, then sign in again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(error.toString(),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign out'),
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

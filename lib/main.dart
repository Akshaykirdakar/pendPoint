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
    if (requireAuthentication) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: _AuthenticationGate(repo: repo),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => AppState(repo)..bootstrap(),
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
            home: app.loading ? const _Splash() : const RootShell(),
          );
        },
      ),
    );
  }
}

class _AuthenticationGate extends StatelessWidget {
  final Repository repo;
  const _AuthenticationGate({required this.repo});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _Splash();
          }
          if (!snapshot.hasData) return const SignInScreen();
          return ChangeNotifierProvider(
            create: (_) => AppState(repo)..bootstrap(),
            child: Consumer<AppState>(
              builder: (context, app, _) {
                if (app.loading) return const _Splash();
                if (app.bootstrapError != null) {
                  return _DataLoadFailure(error: app.bootstrapError!);
                }
                return const RootShell();
              },
            ),
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
  const _Splash();
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
          ]),
        ),
      );
}

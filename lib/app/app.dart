import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/app_controller.dart';
import '../core/l10n/l10n.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../ui/theme.dart';
import 'home_shell.dart';

/// Opens the database and services before the first frame.
class HydraBoot extends StatefulWidget {
  const HydraBoot({super.key});

  @override
  State<HydraBoot> createState() => _HydraBootState();
}

class _HydraBootState extends State<HydraBoot> {
  late Future<AppController> _future;

  @override
  void initState() {
    super.initState();
    _future = AppController.bootstrap();
  }

  void _retry() {
    setState(() {
      _future = AppController.bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('fr'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        AppTheme.syncBrightness(Theme.of(context).brightness);
        return child ?? const SizedBox.shrink();
      },
      home: FutureBuilder<AppController>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BootError(error: snapshot.error!, onRetry: _retry);
          }
          if (!snapshot.hasData) {
            return const _Splash();
          }
          return HydraApp(controller: snapshot.data!);
        },
      ),
    );
  }
}

class HydraApp extends StatelessWidget {
  const HydraApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return AppScope(
          controller: controller,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Hydra POS',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: controller.themeMode,
            locale: controller.locale,
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              AppTheme.syncBrightness(Theme.of(context).brightness);
              return child ?? const SizedBox.shrink();
            },
            home: controller.onboardingDone
                ? const HomeShell()
                : const OnboardingScreen(),
          ),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.storefront_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Hydra POS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Caisse et gestion de boutique',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 56, color: AppTheme.danger),
                const SizedBox(height: 16),
                const Text(
                  'Impossible de démarrer Hydra POS',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

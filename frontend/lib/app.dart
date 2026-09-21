import 'package:flutter/material.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/startup_screen.dart';
import 'services/notification_service.dart';
import 'state/app_controller.dart';

/// Initializes local services before presenting the authenticated app.
class MediStockBootstrap extends StatefulWidget {
  const MediStockBootstrap({super.key});

  @override
  State<MediStockBootstrap> createState() => _MediStockBootstrapState();
}

class _MediStockBootstrapState extends State<MediStockBootstrap> {
  AppController? _controller;
  Object? _startupError;
  String _startupStatus = 'Preparing your workspace';

  @override
  void initState() {
    super.initState();
    // Paint the loading page before any local initialization work starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  Future<void> _initialize() async {
    setState(() {
      _startupError = null;
      _startupStatus = 'Preparing your workspace';
    });
    final stopwatch = Stopwatch()..start();
    AppController? pendingController;
    try {
      final preferences = await SharedPreferences.getInstance();

      // Alerts are optional, so permission or platform availability must never
      // prevent the offline workspace from opening.
      try {
        await NotificationService.initialize();
      } catch (error, stackTrace) {
        debugPrint('Notification initialization skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      if (!mounted) return;
      setState(() => _startupStatus = 'Getting your pharmacy ready');
      final controller = pendingController = AppController(
        database: AppDatabase.instance,
        preferences: preferences,
      );
      await controller.initialize();
      // Keep fast cold starts legible without adding time to slower starts.
      final reduceMotion = WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;
      final remaining =
          (reduceMotion ? 0 : 1600) - stopwatch.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      debugPrint('MediStock workspace ready');
    } catch (error, stackTrace) {
      debugPrint('Workspace initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      pendingController?.dispose();
      if (!mounted) return;
      setState(() => _startupError = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return MaterialApp(
      title: 'MediStock',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: controller == null
              ? StartupScreen(
                  key: const ValueKey('startup'),
                  error: _startupError,
                  status: _startupStatus,
                  onRetry: _startupError == null ? null : _initialize,
                )
              : _AppSession(
                  key: const ValueKey('session'),
                  controller: controller,
                ),
        ),
      ),
    );
  }
}

class MediStockApp extends StatelessWidget {
  const MediStockApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediStock',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _AppSession(controller: controller),
    );
  }
}

class _AppSession extends StatelessWidget {
  const _AppSession({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: controller.authenticated
              ? HomeShell(
                  key: const ValueKey('workspace'),
                  controller: controller,
                )
              : LoginScreen(
                  key: const ValueKey('login'),
                  controller: controller,
                ),
        );
      },
    );
  }
}

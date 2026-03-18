import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audio_service/audio_service.dart';
import 'package:go_router/go_router.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter/foundation.dart'; // Import for PlatformDispatcher
import 'core/router.dart';
import 'core/audio/audio_service.dart';
import 'core/audio/audio_handler.dart';
import 'core/audio/audio_playback_provider.dart';
// import 'core/backend/neon_database_service.dart'; // REMOVED: Using API service now
import 'core/services/background_ai_service.dart';

import 'features/onboarding/onboarding_provider.dart';
import 'theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow GoogleFonts to fetch fonts at runtime (especially needed on web unless fonts are bundled as assets).
  GoogleFonts.config.allowRuntimeFetching = true;

  // Capture errors in the framework
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🔥 Flutter Error: ${details.exception}');
    debugPrint('Stack trace: ${details.stack}');
  };

  // Capture errors outside the framework (async errors)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('🔥 Platform Error: $error');
    debugPrint('Stack trace: $stack');
    return true;
  };

  runApp(const _BootstrapApp());
}



class _InitResult {
  final bool hasSeenOnboarding;
  final AudioHandler handler;

  const _InitResult({
    required this.hasSeenOnboarding,
    required this.handler,
  });
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<_InitResult> _initFuture = _initialize();
  String _currentStep = 'Starting...';

  Future<_InitResult> _initialize() async {
    debugPrint('🚀 Starting initialization...');

    // 1. Load environment variables
    _currentStep = 'Loading configuration';
    await _loadEnv();

    // 2. Initialize Audio Service
    _currentStep = 'Initializing Audio';
    final handler = await _initAudio();

    // 3. Load preferences
    _currentStep = 'Loading preferences';
    final hasSeenOnboarding = await _loadPreferences();

    // 4. Initialize background service
    _currentStep = 'Initializing background service';
    try {
      await backgroundAIService.initialize();
    } catch (e) {
      debugPrint('⚠️ Background service init error: $e');
      // Continue initialization even if background service fails
    }

    _currentStep = 'Complete';
    return _InitResult(
      hasSeenOnboarding: hasSeenOnboarding,
      handler: handler,
    );
  }

  Future<void> _loadEnv() async {
    try {
      await dotenv.load(fileName: '.env');
      debugPrint('✅ Environment loaded (${dotenv.env.length} variables)');
    } catch (e) {
      debugPrint('⚠️ Dotenv error: $e - using fallback config');
      dotenv.testLoad(fileInput: '');
    }
  }

  Future<AudioHandler> _initAudio() async {
    try {
      return await initAudioService().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('⚠️ Audio service fallback: $e');
      return AudioPlayerHandler();
    }
  }

  Future<bool> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('has_seen_onboarding') ?? false;
    } catch (e) {
      debugPrint('⚠️ Preferences error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InitResult>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Error state
        if (snapshot.hasError) {
          return MaterialApp(
            home: _ErrorScreen(
              step: _currentStep,
              error: snapshot.error.toString(),
            ),
          );
        }

        // Loading state
        if (!snapshot.hasData) {
          return MaterialApp(
            title: 'NoteClaw',
            themeMode: ThemeMode.system,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: const _LoadingScreen(),
            debugShowCheckedModeBanner: false,
          );
        }

        // Ready state
        final result = snapshot.data!;
        return ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(result.handler),
          ],
          child: NoteClawApp(
            hasSeenOnboarding: result.hasSeenOnboarding,
          ),
        );
      },
    );
  }
}

class NoteClawApp extends ConsumerStatefulWidget {
  final bool hasSeenOnboarding;

  const NoteClawApp({
    super.key,
    required this.hasSeenOnboarding,
  });

  @override
  ConsumerState<NoteClawApp> createState() => _NoteClawAppState();
}

class _NoteClawAppState extends ConsumerState<NoteClawApp> {
  GoRouter? _router;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initServices();
    }
  }

  void _initServices() {
    // Initialize onboarding state
    if (widget.hasSeenOnboarding) {
      ref.read(onboardingProvider.notifier).completeOnboarding();
    }

    // Database initialization removed - using backend API now

    // Create router with provider container
    final container = ProviderScope.containerOf(context);
    _router = createRouter(widget.hasSeenOnboarding, container);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    if (_router == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return MaterialApp.router(
      title: 'NoteClaw',
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: _router!,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: child!,
        breakpoints: [
          const Breakpoint(start: 0, end: 450, name: MOBILE),
          const Breakpoint(start: 451, end: 800, name: TABLET),
          const Breakpoint(start: 801, end: 1920, name: DESKTOP),
          const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
        ],
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String step;
  final String error;

  const _ErrorScreen({
    required this.step,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Error during: $step',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

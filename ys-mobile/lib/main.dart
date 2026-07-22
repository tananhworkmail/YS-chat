import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'src/app/app_config.dart';
import 'src/app/app_state.dart';
import 'src/l10n/app_localizations.dart';
import 'src/screens/chat_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/services/api_client.dart';
import 'src/services/push_service.dart';
import 'src/services/realtime_service.dart';
import 'src/services/token_store.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _initializeWebRTC();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.empty,
      );
    };

    try {
      final tokenStore = TokenStore();
      final apiClient = ApiClient(AppConfig.apiBaseUrl, tokenStore);
      final realtimeService = RealtimeService(
        AppConfig.apiBaseUrl,
        tokenStore,
        ticketProvider: apiClient.realtimeTicket,
      );
      final pushService = PushService(apiClient, tokenStore);
      await pushService.initialize();
      final appState = AppState(
        apiClient: apiClient,
        tokenStore: tokenStore,
        realtimeService: realtimeService,
        pushService: pushService,
      );
      await appState.restoreSession();

      runApp(YSChatApp(appState: appState));
    } catch (error, stackTrace) {
      debugPrint('YS Chat startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      runApp(StartupErrorApp(error: error));
    }
  }, (error, stackTrace) {
    debugPrint('YS Chat uncaught error: $error');
    debugPrintStack(stackTrace: stackTrace);
  });
}

const _deviceChannel = MethodChannel('com.tythac.ys_mobile/device');

Future<void> _initializeWebRTC() async {
  var forceSoftwareCodec = false;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      forceSoftwareCodec =
          await _deviceChannel.invokeMethod<bool>('isEmulator') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Cannot detect Android emulator: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Android device channel is unavailable: $error');
    }
  }

  await WebRTC.initialize(
    options: forceSoftwareCodec ? {'forceSWCodec': true} : const {},
  );
  if (forceSoftwareCodec) {
    debugPrint('WebRTC software video codecs enabled for Android emulator');
  }
}

class YSChatApp extends StatelessWidget {
  const YSChatApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: const _YSChatMaterialApp(),
    );
  }
}

class _YSChatMaterialApp extends StatelessWidget {
  const _YSChatMaterialApp();

  @override
  Widget build(BuildContext context) {
    final languageCode = context.select(
      (AppState state) => state.languageCode,
    );

    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.t('appTitle'),
      debugShowCheckedModeBanner: false,
      locale: Locale(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildYSTheme(),
      home: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.isAuthenticated) return const ChatScreen();
          return const LoginScreen();
        },
      ),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YS Chat',
      debugShowCheckedModeBanner: false,
      theme: buildYSTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandLogo(size: 58, padding: 8),
                  const SizedBox(height: 18),
                  Text(
                    context.l10n.t('startupFailed'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

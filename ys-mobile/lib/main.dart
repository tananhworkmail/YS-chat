import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app/app_config.dart';
import 'src/app/app_state.dart';
import 'src/screens/chat_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/services/api_client.dart';
import 'src/services/push_service.dart';
import 'src/services/realtime_service.dart';
import 'src/services/token_store.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final tokenStore = TokenStore();
  final apiClient = ApiClient(AppConfig.apiBaseUrl, tokenStore);
  final realtimeService = RealtimeService(AppConfig.apiBaseUrl, tokenStore);
  final pushService = PushService(apiClient);
  final appState = AppState(
    apiClient: apiClient,
    tokenStore: tokenStore,
    realtimeService: realtimeService,
    pushService: pushService,
  );
  await appState.restoreSession();

  runApp(YSChatApp(appState: appState));
}

class YSChatApp extends StatelessWidget {
  const YSChatApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        title: 'YS Chat',
        debugShowCheckedModeBanner: false,
        theme: buildYSTheme(),
        home: Consumer<AppState>(
          builder: (context, state, _) {
            if (state.isAuthenticated) return const ChatScreen();
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import 'token_store.dart';

class RealtimeService {
  RealtimeService(String apiBaseUrl, this._tokenStore)
      : _apiBaseUrl = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  final String _apiBaseUrl;
  final TokenStore _tokenStore;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  void connect({
    required void Function(RealtimeEvent event) onEvent,
    required void Function(Object error) onError,
    void Function()? onDone,
  }) {
    disconnect();
    final token = _tokenStore.token;
    if (token == null || token.isEmpty) return;

    final apiUri = Uri.parse(_apiBaseUrl);
    final wsUri = apiUri.replace(
      scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
      path: '${apiUri.path}/chat/realtime',
      queryParameters: {'token': token},
    );
    final channel = WebSocketChannel.connect(wsUri);
    _channel = channel;
    _subscription = channel.stream.listen(
      (raw) {
        final decoded = jsonDecode('$raw');
        if (decoded is Map<String, dynamic>) {
          onEvent(RealtimeEvent.fromJson(decoded));
        }
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: true,
    );
  }

  void sendCallEvent(Map<String, dynamic> event) {
    _channel?.sink.add(jsonEncode(event));
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'token_store.dart';

class RealtimeService {
  RealtimeService(String apiBaseUrl, this._tokenStore)
      : _apiBaseUrl = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  final String _apiBaseUrl;
  final TokenStore _tokenStore;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final List<Map<String, dynamic>> _pendingEvents = [];
  bool _ready = false;

  bool get isConnected => _ready && _channel != null;

  void connect({
    required void Function(RealtimeEvent event) onEvent,
    required void Function(Object error) onError,
    void Function()? onConnected,
    void Function()? onDone,
  }) {
    final oldSubscription = _subscription;
    final oldChannel = _channel;
    _subscription = null;
    _channel = null;
    _ready = false;
    unawaited(oldSubscription?.cancel() ?? Future<void>.value());
    unawaited(oldChannel?.sink.close() ?? Future<void>.value());

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
    unawaited(channel.ready.then((_) {
      if (!identical(_channel, channel)) return;
      _ready = true;
      onConnected?.call();
      final pending = List<Map<String, dynamic>>.from(_pendingEvents);
      _pendingEvents.clear();
      for (final event in pending) {
        channel.sink.add(jsonEncode(event));
      }
    }).catchError((_) {}));
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

  bool sendEvent(
    String type, {
    required int conversationId,
    int messageId = 0,
    Map<String, dynamic> payload = const {},
    bool queueWhenDisconnected = false,
  }) {
    final now = DateTime.now().toUtc();
    final eventId = const Uuid().v4();
    final event = <String, dynamic>{
      'type': type,
      'eventId': eventId,
      'serverTimestamp': now.toIso8601String(),
      'conversationId': conversationId,
      if (messageId > 0) 'messageId': messageId,
      'version': 1,
      'payload': payload,
      // Legacy top-level fields are kept until older servers are retired.
      ...payload,
    };
    return _sendRaw(event, queueWhenDisconnected: queueWhenDisconnected);
  }

  void sendCallEvent(Map<String, dynamic> event) {
    _sendRaw(event, queueWhenDisconnected: true);
  }

  bool _sendRaw(Map<String, dynamic> event,
      {required bool queueWhenDisconnected}) {
    final channel = _channel;
    if (channel == null || !_ready) {
      if (queueWhenDisconnected) {
        _pendingEvents.add(Map<String, dynamic>.from(event));
        if (_pendingEvents.length > 64) {
          _pendingEvents.removeAt(0);
        }
      }
      return false;
    }
    channel.sink.add(jsonEncode(event));
    return true;
  }

  Future<void> disconnect() async {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    _ready = false;
    _pendingEvents.clear();
    await subscription?.cancel();
    await channel?.sink.close();
  }
}

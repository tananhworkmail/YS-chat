import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';
import 'api_client.dart';

class PushService {
  PushService(this._apiClient);

  // Kept injected so Firebase token registration can be enabled without
  // changing AppState/main wiring once google-services.json is available.
  // ignore: unused_field
  final ApiClient _apiClient;
  final _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> registerCurrentDevice() async {
    await _ensureInitialized();

    // FCM device-token registration still needs Firebase configuration
    // (android/app/google-services.json and backend Firebase credentials).
    // Until then, realtime messages are surfaced with local notifications.
  }

  Future<void> showChatMessage({
    required ChatMessage message,
    required String conversationTitle,
  }) async {
    await _ensureInitialized();
    await _notifications.show(
      message.id,
      conversationTitle,
      _notificationBody(message),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ys_chat_messages',
          'YS Chat messages',
          channelDescription: 'Realtime chat message notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: '${message.conversationId}',
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(initializationSettings);
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  String _notificationBody(ChatMessage message) {
    final sender = message.senderName.trim().isEmpty
        ? message.senderUserid
        : message.senderName.trim();
    final content = message.content.trim();
    if (content.isNotEmpty) return '$sender: $content';
    if (message.type == 'poll') return '$sender: Bình chọn mới';
    if (message.attachments.any((item) => item.mimeType.startsWith('image/'))) {
      return '$sender: Đã gửi ảnh';
    }
    if (message.attachments.any((item) => item.mimeType.startsWith('video/'))) {
      return '$sender: Đã gửi video';
    }
    if (message.type == 'voice' ||
        message.attachments.any((item) => item.mimeType.startsWith('audio/'))) {
      return '$sender: Đã gửi tin nhắn thoại';
    }
    if (message.attachments.isNotEmpty) return '$sender: Đã gửi tệp';
    return '$sender: Tin nhắn mới';
  }
}

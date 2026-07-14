import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../app/app_config.dart';
import 'api_client.dart';
import 'token_store.dart';

final _backgroundNotifications = FlutterLocalNotificationsPlugin();

enum NativeCallActionType { accept, decline, ended }

class RemoteCallEvent {
  const RemoteCallEvent({
    required this.type,
    required this.callId,
    required this.conversationId,
  });

  final String type;
  final String callId;
  final int conversationId;
}

class NativeCallAction {
  const NativeCallAction({
    required this.type,
    required this.callId,
    required this.conversationId,
    required this.callerName,
    required this.fromUserid,
  });

  final NativeCallActionType type;
  final String callId;
  final int conversationId;
  final String callerName;
  final String fromUserid;

  factory NativeCallAction.fromParams(
    NativeCallActionType type,
    CallKitParams params,
  ) {
    final extra = params.extra ?? const <String, dynamic>{};
    return NativeCallAction(
      type: type,
      callId: params.id,
      conversationId: _asInt(extra['conversationId']),
      callerName: '${extra['callerName'] ?? params.nameCaller ?? ''}',
      fromUserid: '${extra['fromUserid'] ?? params.handle ?? ''}',
    );
  }

  bool get isValid => callId.isNotEmpty && conversationId > 0;
}

@pragma('vm:entry-point')
Future<void> ysFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return;
  }

  final type = '${message.data['type'] ?? ''}';
  if (type == 'call.invite') {
    await _showNativeIncomingCall(message.data);
    return;
  }
  if (_isCallControlType(type)) {
    await _endNativeCall('${message.data['callId'] ?? ''}');
    return;
  }

  // Notification payloads are shown by the OS automatically in background.
  // Data-only chat payloads need a local notification fallback.
  if (message.notification != null) return;

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _backgroundNotifications.initialize(settings);
  await _backgroundNotifications.show(
    message.messageId.hashCode,
    _remoteTitle(message),
    _remoteBody(message),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'ys_chat_messages',
        'YS Chat messages',
        channelDescription: 'Realtime chat notifications',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        channelShowBadge: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: message.data['conversationId'],
  );
}

@pragma('vm:entry-point')
Future<void> ysCallkitBackgroundHandler(CallEvent event) async {
  if (event is CallEventActionCallDecline) {
    await _sendBackgroundCallControl(event.callKitParams, 'call.reject');
    return;
  }
  if (event is CallEventActionCallEnded) {
    await _sendBackgroundCallControl(event.callKitParams, 'call.end');
  }
}

Future<void> _sendBackgroundCallControl(
  CallKitParams params,
  String type,
) async {
  final action = NativeCallAction.fromParams(
    type == 'call.reject'
        ? NativeCallActionType.decline
        : NativeCallActionType.ended,
    params,
  );
  if (!action.isValid) return;

  try {
    try {
      await Firebase.initializeApp();
    } catch (_) {}
    final tokenStore = TokenStore();
    await tokenStore.load();
    if (tokenStore.token?.isNotEmpty != true) return;
    final apiClient = ApiClient(AppConfig.apiBaseUrl, tokenStore);
    final sourceToken =
        (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
    await apiClient.sendCallControlEvent(
      type: type,
      conversationId: action.conversationId,
      callId: action.callId,
      deviceId: await tokenStore.ensureDeviceId(),
      token: sourceToken,
    );
  } catch (_) {}
}

class PushService {
  PushService(this._apiClient, this._tokenStore);

  final ApiClient _apiClient;
  final TokenStore _tokenStore;
  final _notifications = FlutterLocalNotificationsPlugin();
  final _nativeCallActions = StreamController<NativeCallAction>.broadcast();
  final _remoteCallEvents = StreamController<RemoteCallEvent>.broadcast();
  final List<NativeCallAction> _pendingNativeCallActions = [];
  final Set<String> _shownNativeCallIds = {};
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<CallEvent?>? _callkitEventSubscription;
  bool _localInitialized = false;
  bool _firebaseInitialized = false;
  bool _firebaseUnavailable = false;
  bool _nativeCallsInitialized = false;

  Stream<NativeCallAction> get nativeCallActions => _nativeCallActions.stream;
  Stream<RemoteCallEvent> get remoteCallEvents => _remoteCallEvents.stream;

  Future<void> initialize() async {
    await _ensureLocalInitialized();
    await _ensureNativeCallsInitialized();
    await _ensureFirebaseInitialized();
  }

  List<NativeCallAction> takePendingNativeCallActions() {
    final actions = List<NativeCallAction>.from(_pendingNativeCallActions);
    _pendingNativeCallActions.clear();
    return actions;
  }

  Future<void> registerCurrentDevice() async {
    await initialize();
    if (!await _ensureFirebaseInitialized()) return;

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (Platform.isAndroid) {
      try {
        await FlutterCallkitIncoming.requestNotificationPermission({
          'title': 'Cho phép thông báo cuộc gọi',
          'rationaleMessagePermission':
              'YS Chat cần quyền thông báo để báo cuộc gọi đến.',
          'postNotificationMessageRequired':
              'Vui lòng bật quyền thông báo cho YS Chat trong cài đặt.',
        });
        final canUseFullScreen =
            await FlutterCallkitIncoming.canUseFullScreenIntent();
        if (!canUseFullScreen) {
          await FlutterCallkitIncoming.requestFullIntentPermission();
        }
      } catch (_) {}
    }

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _registerToken(token);
    }

    _tokenRefreshSubscription ??= messaging.onTokenRefresh
        .listen((token) => unawaited(_registerToken(token)));
  }

  Future<String> currentDeviceToken() async {
    if (!await _ensureFirebaseInitialized()) return '';
    try {
      return (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> unregisterCurrentDevice() async {
    final deviceId = await _tokenStore.ensureDeviceId();
    final token = await currentDeviceToken();
    if (deviceId.isEmpty) return;
    await _apiClient.unregisterDeviceToken(
      deviceId: deviceId,
      token: token,
    );
  }

  Future<void> showIncomingCall({
    required String callId,
    required int conversationId,
    required String callerName,
    required String fromUserid,
    String avatarUrl = '',
  }) async {
    if (callId.isEmpty || conversationId <= 0) return;
    if (!_shownNativeCallIds.add(callId)) return;
    try {
      await _showNativeIncomingCall({
        'callId': callId,
        'conversationId': '$conversationId',
        'callerName': callerName,
        'fromUserid': fromUserid,
        'avatarUrl': avatarUrl,
      });
    } catch (_) {
      _shownNativeCallIds.remove(callId);
    }
  }

  Future<void> endIncomingCall(String callId) async {
    _shownNativeCallIds.remove(callId);
    await _endNativeCall(callId);
  }

  Future<void> markCallConnected(String callId) async {
    if (callId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (_) {}
  }

  Future<void> showChatMessage({
    required ChatMessage message,
    required String conversationTitle,
    int unreadCount = 1,
  }) async {
    await _ensureLocalInitialized();
    final body = _notificationBody(message);

    await _notifications.show(
      message.id,
      conversationTitle,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'ys_chat_messages',
          'YS Chat messages',
          channelDescription: 'Realtime chat notifications',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          channelShowBadge: true,
          color: AppColors.brand,
          enableVibration: true,
          groupKey: 'ys_chat_messages',
          number: unreadCount,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: conversationTitle,
            summaryText: unreadCount > 1 ? '$unreadCount tin mới' : 'YS Chat',
          ),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          badgeNumber: unreadCount,
        ),
      ),
      payload: '${message.conversationId}',
    );
  }

  Future<void> _ensureNativeCallsInitialized() async {
    if (_nativeCallsInitialized) return;
    await FlutterCallkitIncoming.onBackgroundMessage(
      ysCallkitBackgroundHandler,
    );
    _callkitEventSubscription =
        FlutterCallkitIncoming.onEvent.listen(_handleCallkitEvent);
    _nativeCallsInitialized = true;

    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      for (final call in activeCalls) {
        _shownNativeCallIds.add(call.id);
        if (call.isAccepted) {
          _emitNativeCallAction(
            NativeCallAction.fromParams(NativeCallActionType.accept, call),
          );
        }
      }
    } catch (_) {}
  }

  void _handleCallkitEvent(CallEvent? event) {
    if (event == null) return;
    if (event is CallEventActionCallIncoming) {
      _shownNativeCallIds.add(event.callKitParams.id);
      return;
    }
    if (event is CallEventActionCallAccept) {
      _emitNativeCallAction(
        NativeCallAction.fromParams(
          NativeCallActionType.accept,
          event.callKitParams,
        ),
      );
      return;
    }
    if (event is CallEventActionCallDecline) {
      _shownNativeCallIds.remove(event.callKitParams.id);
      _emitNativeCallAction(
        NativeCallAction.fromParams(
          NativeCallActionType.decline,
          event.callKitParams,
        ),
      );
      return;
    }
    if (event is CallEventActionCallEnded) {
      _shownNativeCallIds.remove(event.callKitParams.id);
      _emitNativeCallAction(
        NativeCallAction.fromParams(
          NativeCallActionType.ended,
          event.callKitParams,
        ),
      );
    }
  }

  void _emitNativeCallAction(NativeCallAction action) {
    if (!action.isValid) return;
    _pendingNativeCallActions.removeWhere(
      (item) => item.type == action.type && item.callId == action.callId,
    );
    _pendingNativeCallActions.add(action);
    _nativeCallActions.add(action);
  }

  Future<void> _handleForegroundRemoteMessage(RemoteMessage message) async {
    final type = '${message.data['type'] ?? ''}';
    if (type == 'call.invite') {
      final data = message.data;
      await showIncomingCall(
        callId: '${data['callId'] ?? ''}',
        conversationId: _asInt(data['conversationId']),
        callerName: '${data['callerName'] ?? data['title'] ?? 'YS Chat'}',
        fromUserid: '${data['fromUserid'] ?? ''}',
        avatarUrl: '${data['avatarUrl'] ?? ''}',
      );
      return;
    }
    if (_isCallControlType(type)) {
      await endIncomingCall('${message.data['callId'] ?? ''}');
      _remoteCallEvents.add(RemoteCallEvent(
        type: type,
        callId: '${message.data['callId'] ?? ''}',
        conversationId: _asInt(message.data['conversationId']),
      ));
    }
  }

  Future<void> _ensureLocalInitialized() async {
    if (_localInitialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(initializationSettings);
    final androidNotifications =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        'ys_chat_messages',
        'YS Chat messages',
        description: 'Realtime chat notifications',
        importance: Importance.high,
        playSound: true,
      ),
    );
    await androidNotifications?.requestNotificationsPermission();
    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _localInitialized = true;
  }

  Future<bool> _ensureFirebaseInitialized() async {
    if (_firebaseInitialized) return true;
    if (_firebaseUnavailable) return false;

    try {
      FirebaseMessaging.onBackgroundMessage(
        ysFirebaseMessagingBackgroundHandler,
      );
      await Firebase.initializeApp();
      _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_handleForegroundRemoteMessage(message)),
      );
      _firebaseInitialized = true;
      return true;
    } catch (_) {
      _firebaseUnavailable = true;
      return false;
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final deviceId = await _tokenStore.ensureDeviceId();
      await _apiClient.registerDeviceToken(
        token: token,
        platform: _platformName,
        deviceId: deviceId,
      );
    } catch (_) {
      // Token refresh will retry later; avoid blocking login/session restore.
    }
  }

  String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  String _notificationBody(ChatMessage message) {
    final sender = message.senderName.trim().isEmpty
        ? message.senderUserid
        : message.senderName.trim();
    final content = message.content.trim();
    if (message.type == 'call') return '$sender: Thông tin cuộc gọi';
    if (content.isNotEmpty) return '$sender: $content';
    if (message.type == 'poll') return '$sender: Bình chọn mới';
    if (message.attachments.any((item) => item.mimeType.startsWith('image/'))) {
      return '$sender: Đã gửi hình ảnh';
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

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _callkitEventSubscription?.cancel();
    await _nativeCallActions.close();
    await _remoteCallEvents.close();
  }
}

Future<void> _showNativeIncomingCall(Map<String, dynamic> data) async {
  final callId = '${data['callId'] ?? ''}'.trim();
  final conversationId = _asInt(data['conversationId']);
  final callerName =
      '${data['callerName'] ?? data['title'] ?? 'YS Chat'}'.trim();
  final fromUserid = '${data['fromUserid'] ?? ''}'.trim();
  final avatarUrl = _resolveCallAvatar('${data['avatarUrl'] ?? ''}'.trim());
  if (callId.isEmpty || conversationId <= 0) return;

  final params = CallKitParams(
    id: callId,
    nameCaller: callerName.isEmpty ? 'YS Chat' : callerName,
    avatar: avatarUrl.isEmpty ? null : avatarUrl,
    appName: 'YS Chat',
    handle: fromUserid,
    type: 0,
    duration: 45000,
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Cuộc gọi nhỡ',
    ),
    callingNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Đang gọi',
      callbackText: 'Kết thúc',
    ),
    extra: {
      'conversationId': conversationId,
      'callId': callId,
      'callerName': callerName,
      'fromUserid': fromUserid,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#111827',
      actionColor: '#16A34A',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'Cuộc gọi đến',
      missedCallNotificationChannelName: 'Cuộc gọi nhỡ',
      isShowCallID: false,
      isShowFullLockedScreen: true,
      isImportant: true,
      isFullScreen: true,
      textAccept: 'Nghe máy',
      textDecline: 'Từ chối',
    ),
    ios: const IOSParams(
      handleType: 'generic',
      supportsVideo: false,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'voiceChat',
      audioSessionActive: true,
      supportsDTMF: false,
      supportsHolding: false,
      supportsGrouping: false,
      supportsUngrouping: false,
      includesCallsInRecents: true,
      ringtonePath: 'system_ringtone_default',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

String _resolveCallAvatar(String value) {
  if (value.isEmpty ||
      value.startsWith('http://') ||
      value.startsWith('https://')) {
    return value;
  }
  final baseUri = Uri.parse(AppConfig.apiBaseUrl);
  final path = value.startsWith('/') ? value : '/$value';
  return baseUri.replace(path: path, query: null, fragment: null).toString();
}

Future<void> _endNativeCall(String callId) async {
  if (callId.trim().isEmpty) return;
  try {
    await FlutterCallkitIncoming.endCall(callId);
  } catch (_) {}
}

bool _isCallControlType(String type) {
  return type == 'call.accept' ||
      type == 'call.reject' ||
      type == 'call.busy' ||
      type == 'call.cancel' ||
      type == 'call.end';
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

String _remoteTitle(RemoteMessage message) {
  final title = message.notification?.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return '${message.data['title'] ?? 'YS Chat'}';
}

String _remoteBody(RemoteMessage message) {
  final body = message.notification?.body?.trim();
  if (body != null && body.isNotEmpty) return body;
  return '${message.data['body'] ?? 'Tin nhắn mới'}';
}

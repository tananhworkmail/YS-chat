import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import '../services/token_store.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.apiClient,
    required this.tokenStore,
    required this.realtimeService,
    required this.pushService,
  });

  final ApiClient apiClient;
  final TokenStore tokenStore;
  final RealtimeService realtimeService;
  final PushService pushService;

  bool loading = false;
  String? error;
  ChatUser? me;
  List<ChatConversation> conversations = [];
  List<ChatUser> contacts = [];
  List<ChatMessage> messages = [];
  ChatConversation? selectedConversation;
  Timer? _reconnectTimer;

  bool get isAuthenticated => tokenStore.token?.isNotEmpty == true;

  Future<void> restoreSession() async {
    await tokenStore.load();
    if (!isAuthenticated) return;
    try {
      await _guard(() async {
        me = await apiClient.profile();
        await refreshChat();
        _connectRealtime();
        unawaited(pushService.registerCurrentDevice());
      });
    } catch (_) {
      await tokenStore.clear();
      me = null;
      conversations = [];
      contacts = [];
      messages = [];
      selectedConversation = null;
    }
  }

  Future<void> login(String userid, String password) async {
    await _guard(() async {
      final payload = await apiClient.login(userid, password);
      await tokenStore.saveSession(
        token: '${payload['token'] ?? ''}',
        userid: '${payload['userid'] ?? ''}',
        fullname: '${payload['fullname'] ?? ''}',
        accountId: payload['account_id'],
      );
      me = ChatUser(
          userid: tokenStore.userid ?? '', fullname: tokenStore.fullname ?? '');
      await refreshChat();
      _connectRealtime();
      unawaited(pushService.registerCurrentDevice());
    });
  }

  Future<void> logout() async {
    await realtimeService.disconnect();
    _reconnectTimer?.cancel();
    await tokenStore.clear();
    me = null;
    conversations = [];
    contacts = [];
    messages = [];
    selectedConversation = null;
    notifyListeners();
  }

  Future<void> refreshChat() async {
    contacts = await apiClient.contacts();
    conversations = await apiClient.conversations();
    conversations.sort(_sortConversations);
    notifyListeners();
    final selected = selectedConversation;
    if (selected != null) {
      await selectConversation(selected);
    }
  }

  Future<void> selectConversation(ChatConversation conversation) async {
    selectedConversation = conversation;
    messages = await apiClient.messages(conversation.id);
    messages.sort((a, b) => a.id.compareTo(b.id));
    notifyListeners();
  }

  void clearSelectedConversation() {
    selectedConversation = null;
    messages = [];
    notifyListeners();
  }

  Future<void> sendText(String content) async {
    final conversation = selectedConversation;
    final trimmed = content.trim();
    if (conversation == null || trimmed.isEmpty) return;
    final message = await apiClient.sendMessage(conversation.id,
        type: 'text', content: trimmed);
    _upsertMessage(message);
  }

  Future<void> sendFiles(List<File> files, {String type = 'file'}) async {
    final conversation = selectedConversation;
    if (conversation == null || files.isEmpty) return;
    final attachments = await apiClient.uploadFiles(files);
    final message = await apiClient.sendMessage(conversation.id,
        type: type, attachments: attachments);
    _upsertMessage(message);
  }

  Future<void> updateFullname(String fullname) async {
    final trimmed = fullname.trim();
    if (trimmed.isEmpty) return;
    me = await apiClient.updateProfile(trimmed);
    await tokenStore.saveSession(
      token: tokenStore.token ?? '',
      userid: tokenStore.userid ?? me?.userid ?? '',
      fullname: me?.fullname ?? trimmed,
      accountId: tokenStore.accountId,
    );
    notifyListeners();
  }

  Future<void> uploadAvatar(File file) async {
    me = await apiClient.uploadAvatar(file);
    notifyListeners();
  }

  Future<void> openDirectConversation(String userid) async {
    final conversation = await apiClient.createDirectConversation(userid);
    final index =
        conversations.indexWhere((item) => item.id == conversation.id);
    if (index >= 0) {
      conversations[index] = conversation;
    } else {
      conversations.insert(0, conversation);
    }
    await selectConversation(conversation);
  }

  void _connectRealtime() {
    realtimeService.connect(
      onEvent: _handleRealtimeEvent,
      onError: (_) => _scheduleRealtimeReconnect(),
      onDone: _scheduleRealtimeReconnect,
    );
  }

  void _scheduleRealtimeReconnect() {
    if (!isAuthenticated) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connectRealtime);
  }

  void _handleRealtimeEvent(RealtimeEvent event) {
    if (event.type == 'chat.message.created' ||
        event.type == 'chat.poll.updated') {
      final message = event.message;
      if (message != null) _upsertMessage(message);
      unawaited(refreshChat());
      return;
    }
    if (event.type == 'chat.presence.changed' && event.userid.isNotEmpty) {
      contacts = contacts
          .map((user) => user.userid == event.userid
              ? user.copyWith(isOnline: event.isOnline)
              : user)
          .toList();
      conversations = conversations.map((conversation) {
        final members = conversation.members
            .map((user) => user.userid == event.userid
                ? user.copyWith(isOnline: event.isOnline)
                : user)
            .toList();
        return conversation.copyWith(members: members);
      }).toList();
      notifyListeners();
    }
  }

  void _upsertMessage(ChatMessage message) {
    if (selectedConversation?.id == message.conversationId) {
      final index = messages.indexWhere((item) => item.id == message.id);
      if (index >= 0) {
        messages[index] = message;
      } else {
        messages.add(message);
      }
      messages.sort((a, b) => a.id.compareTo(b.id));
    }
    conversations = conversations.map((conversation) {
      if (conversation.id == message.conversationId) {
        return conversation.copyWith(lastMessage: message);
      }
      return conversation;
    }).toList()
      ..sort(_sortConversations);
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (err) {
      error = '$err';
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  int _sortConversations(ChatConversation a, ChatConversation b) {
    final left =
        a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right =
        b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  }
}

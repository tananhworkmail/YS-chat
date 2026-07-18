import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/call_state_machine.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import '../services/token_store.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({
    required this.apiClient,
    required this.tokenStore,
    required this.realtimeService,
    required this.pushService,
  }) {
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _nativeCallSubscription = pushService.nativeCallActions.listen(
      (action) => unawaited(_handleNativeCallAction(action)),
    );
    _remoteCallSubscription = pushService.remoteCallEvents.listen(
      (event) => unawaited(_handleRemoteCallEvent(event)),
    );
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
          _handleConnectivityChanged,
        );
    unawaited(_initializeConnectivity());
  }

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
  Map<int, int> unreadMessageCounts = {};
  final Map<int, Map<String, DateTime>> _typingUsers = {};
  final Map<String, ChatMessage> _pendingMessagesByClientId = {};
  final Set<String> _submittingClientMessageIds = {};
  ChatConversation? selectedConversation;
  bool hasMoreMessages = false;
  bool loadingOlderMessages = false;
  int messageFocusId = 0;
  int messageFocusConversationId = 0;
  int messageFocusSequence = 0;
  String callState = 'idle';
  String callStatus = '';
  String callId = '';
  int callConversationId = 0;
  String callPeerName = '';
  bool callMuted = false;
  bool callSpeakerOn = false;
  int callDuration = 0;
  String callNotice = '';
  int callNoticeSequence = 0;
  String languageCode = 'vi';
  Timer? _reconnectTimer;
  Timer? _realtimeStableTimer;
  Timer? _outgoingTypingExpiryTimer;
  final Map<String, Timer> _incomingTypingExpiryTimers = {};
  final Map<int, int> _lastSeenMessageIds = {};
  final Map<int, int> _lastSeenSequences = {};
  final Set<String> _handledRealtimeEventIds = {};
  final List<String> _handledRealtimeEventOrder = [];
  final Map<int, int> _pendingReadTargets = {};
  final Set<int> _markReadInFlight = {};
  final Map<int, int> _activeReadTargets = {};
  final Map<int, int> _pendingDeliveredTargets = {};
  final Set<int> _deliveredInFlight = {};
  final Map<int, int> _activeDeliveredTargets = {};
  bool _catchingUp = false;
  bool _networkAvailable = true;
  int _reconnectAttempt = 0;
  final Random _reconnectRandom = Random();
  int _nextLocalMessageId = -1;
  int _outgoingTypingConversationId = 0;
  DateTime? _lastTypingStartSentAt;
  AppLifecycleState? _appLifecycleState;
  Timer? _runtimePersistenceTimer;
  Future<void> _runtimePersistenceTail = Future<void>.value();
  int _runtimePersistenceEpoch = 0;
  bool _restoringRuntimeSnapshot = false;
  Timer? _callTimeoutTimer;
  Timer? _callDurationTimer;
  DateTime? _callStartedAt;
  bool _callStartedByMe = false;
  bool _callOfferStarted = false;
  NativeCallAction? _pendingNativeCallAction;
  late final StreamSubscription<NativeCallAction> _nativeCallSubscription;
  late final StreamSubscription<RemoteCallEvent> _remoteCallSubscription;
  late final StreamSubscription<List<ConnectivityResult>>
      _connectivitySubscription;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localCallStream;
  final List<Map<String, dynamic>> _pendingIceCandidates = [];

  bool get isAuthenticated => tokenStore.token?.isNotEmpty == true;
  bool get isAppResumed => _appLifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      if (isAuthenticated && _networkAvailable) {
        if (realtimeService.isConnected) {
          unawaited(_handleRealtimeConnected());
        } else {
          _connectRealtime();
        }
      }
      unawaited(_reconcileCurrentCall());
      unawaited(_markSelectedConversationReadOnResume());
    } else {
      stopTyping();
      if (callState == 'idle') {
        _reconnectTimer?.cancel();
        unawaited(realtimeService.disconnect());
      }
    }
  }

  Future<void> _initializeConnectivity() async {
    try {
      _handleConnectivityChanged(await Connectivity().checkConnectivity());
    } catch (_) {}
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    final available =
        results.any((result) => result != ConnectivityResult.none);
    if (_networkAvailable == available) return;
    _networkAvailable = available;
    if (!available) {
      _reconnectTimer?.cancel();
      unawaited(realtimeService.disconnect());
      return;
    }
    _reconnectAttempt = 0;
    if (isAuthenticated && (isAppResumed || callState != 'idle')) {
      _connectRealtime();
    }
  }

  Future<void> _markSelectedConversationReadOnResume() async {
    final conversation = selectedConversation;
    if (!isAppResumed || conversation == null) return;
    var latestMessageId = conversation.lastMessage?.id ?? 0;
    for (final message in messages) {
      if (message.conversationId == conversation.id &&
          message.id > latestMessageId) {
        latestMessageId = message.id;
      }
    }
    if (latestMessageId > 0) {
      await markConversationRead(conversation.id, latestMessageId);
    }
  }

  Future<void> _reconcileCurrentCall() async {
    final expectedCallId = callId;
    if (!isAuthenticated || expectedCallId.isEmpty) return;
    try {
      final record = await apiClient.callState(expectedCallId);
      if (callId != expectedCallId) return;
      final status = '${record['status'] ?? ''}';
      const terminalStatuses = {
        'rejected',
        'busy',
        'canceled',
        'completed',
        'missed',
        'failed'
      };
      if (terminalStatuses.contains(status)) {
        _cleanupCall('Cuoc goi da ket thuc');
        return;
      }
      if (callState == 'incoming' &&
          status != 'ringing' &&
          '${record['acceptedByDeviceId'] ?? ''}' != tokenStore.deviceId) {
        _cleanupCall('Cuoc goi da duoc nghe tren thiet bi khac');
      }
    } catch (_) {}
  }

  Future<void> restoreSession() async {
    try {
      await tokenStore.load();
      languageCode = tokenStore.languageCode;
      if (!isAuthenticated) return;
      await _guard(() async {
        await _restoreRuntimeSnapshot();
        me = await apiClient.profile();
        await refreshChat();
        _connectRealtime();
        unawaited(_retryPendingOutbox());
        await _resumeNativeCallActions();
        unawaited(pushService.registerCurrentDevice());
      });
    } catch (err) {
      if (_isUnauthorizedError(err)) {
        _resetMessagingSessionState();
        await _runtimePersistenceTail.catchError((_) {});
        await tokenStore.clearSession();
        me = null;
        conversations = [];
        contacts = [];
        messages = [];
        unreadMessageCounts = {};
        selectedConversation = null;
        hasMoreMessages = false;
        loadingOlderMessages = false;
      } else {
        me ??= ChatUser(
          userid: tokenStore.userid ?? '',
          fullname: tokenStore.fullname ?? '',
        );
        if (isAuthenticated) {
          _connectRealtime();
          unawaited(_retryPendingOutbox());
        }
        notifyListeners();
      }
    }
  }

  Future<void> login(String userid, String password) async {
    await _guard(() async {
      final payload = await apiClient.login(userid, password);
      _resetMessagingSessionState();
      await _runtimePersistenceTail.catchError((_) {});
      await tokenStore.saveSession(
        token: '${payload['token'] ?? ''}',
        userid: '${payload['userid'] ?? ''}',
        fullname: '${payload['fullname'] ?? ''}',
        accountId: payload['account_id'],
      );
      me = ChatUser(
          userid: tokenStore.userid ?? '', fullname: tokenStore.fullname ?? '');
      await _restoreRuntimeSnapshot();
      await refreshChat();
      _connectRealtime();
      unawaited(_retryPendingOutbox());
      await _resumeNativeCallActions();
      unawaited(pushService.registerCurrentDevice());
    });
  }

  Future<void> setLanguage(String code) async {
    languageCode = code;
    await tokenStore.saveLanguage(code);
    notifyListeners();
  }

  Future<void> logout() async {
    _cleanupCall();
    await realtimeService.disconnect();
    _reconnectTimer?.cancel();
    _realtimeStableTimer?.cancel();
    _reconnectAttempt = 0;
    try {
      await pushService.unregisterCurrentDevice();
    } catch (_) {
      // The session must still be cleared if the network is unavailable.
    }
    _resetMessagingSessionState();
    await _runtimePersistenceTail.catchError((_) {});
    await tokenStore.clearSession(clearChatRuntime: true);
    me = null;
    conversations = [];
    contacts = [];
    messages = [];
    unreadMessageCounts = {};
    _pendingNativeCallAction = null;
    selectedConversation = null;
    hasMoreMessages = false;
    loadingOlderMessages = false;
    notifyListeners();
  }

  Future<void> refreshChat({
    bool reloadSelected = true,
    bool seedMissing = true,
  }) async {
    final selectedId = selectedConversation?.id;
    contacts = await apiClient.contacts();
    contacts.sort(_compareContacts);
    conversations = await apiClient.conversations();
    unreadMessageCounts = {
      for (final conversation in conversations)
        if (conversation.unreadCount > 0)
          conversation.id: conversation.unreadCount,
    };
    var initializedCursor = false;
    for (final conversation in conversations) {
      final lastMessage = conversation.lastMessage;
      final hasMessageCursor = _lastSeenMessageIds.containsKey(conversation.id);
      final hasSequenceCursor = _lastSeenSequences.containsKey(conversation.id);
      if (!hasMessageCursor && !hasSequenceCursor) {
        _lastSeenMessageIds[conversation.id] = 0;
        _lastSeenSequences[conversation.id] = 0;
        initializedCursor = true;
      } else {
        if (!hasMessageCursor) {
          _lastSeenMessageIds[conversation.id] = 0;
          initializedCursor = true;
        }
        if (!hasSequenceCursor) {
          _lastSeenSequences[conversation.id] = 0;
          initializedCursor = true;
        }
      }
      if (seedMissing &&
          lastMessage != null &&
          !hasMessageCursor &&
          !hasSequenceCursor) {
        _observeMessageCursor(lastMessage);
      }
    }
    if (initializedCursor) _scheduleRuntimePersistence();
    _applyPendingOutboxToConversationSummaries();
    conversations.sort(_sortConversations);
    if (selectedId != null) {
      selectedConversation = conversations
              .where((conversation) => conversation.id == selectedId)
              .firstOrNull ??
          selectedConversation;
    }
    notifyListeners();
    final selected = selectedConversation;
    if (reloadSelected && selected != null) {
      await selectConversation(selected);
    }
  }

  Future<void> selectConversation(ChatConversation conversation) async {
    stopTyping();
    selectedConversation =
        conversations.where((item) => item.id == conversation.id).firstOrNull ??
            conversation;
    messageFocusId = 0;
    messageFocusConversationId = 0;
    loadingOlderMessages = false;
    final page = await apiClient.messages(conversation.id, limit: 50);
    final serverClientMessageIds = page.messages
        .where((message) => message.senderUserid == tokenStore.userid)
        .map((message) => message.clientMessageId)
        .where((clientMessageId) => clientMessageId.isNotEmpty)
        .toSet();
    var reconciledOutbox = false;
    for (final clientMessageId in serverClientMessageIds) {
      reconciledOutbox =
          _pendingMessagesByClientId.remove(clientMessageId) != null ||
              reconciledOutbox;
    }
    if (reconciledOutbox) _scheduleRuntimePersistence();
    final pending = _pendingMessagesByClientId.values
        .where((message) =>
            message.conversationId == conversation.id &&
            !serverClientMessageIds.contains(message.clientMessageId))
        .toList();
    messages = [...page.messages, ...pending];
    hasMoreMessages = page.hasMore;
    messages.sort(_sortMessages);
    for (final message in page.messages) {
      _observeMessageCursor(message);
    }
    notifyListeners();
    final latestIncoming = page.messages
        .where((message) => message.senderUserid != tokenStore.userid)
        .fold<int>(
            0, (latest, message) => message.id > latest ? message.id : latest);
    if (latestIncoming > 0) {
      unawaited(_ackDelivered(conversation.id, latestIncoming));
    }
    final latest = page.messages.fold<int>(
        0, (value, message) => message.id > value ? message.id : value);
    if (latest > 0 && isAppResumed) {
      unawaited(markConversationRead(conversation.id, latest));
    }
  }

  Future<void> loadOlderMessages() async {
    final conversation = selectedConversation;
    if (conversation == null ||
        loadingOlderMessages ||
        !hasMoreMessages ||
        messages.isEmpty) {
      return;
    }

    loadingOlderMessages = true;
    notifyListeners();
    try {
      final oldestMessageId = messages.first.id;
      final page = await apiClient.messages(
        conversation.id,
        limit: 50,
        beforeId: oldestMessageId,
      );
      final existingIds = messages.map((message) => message.id).toSet();
      final olderMessages = page.messages
          .where((message) => !existingIds.contains(message.id))
          .toList();
      messages = [...olderMessages, ...messages]..sort(_sortMessages);
      for (final message in olderMessages) {
        _observeMessageCursor(message);
      }
      hasMoreMessages = page.hasMore;
    } finally {
      loadingOlderMessages = false;
      notifyListeners();
    }
  }

  Future<void> loadAllMessages() async {
    final conversationId = selectedConversation?.id;
    if (conversationId == null) return;
    while (selectedConversation?.id == conversationId && hasMoreMessages) {
      if (loadingOlderMessages) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        continue;
      }
      final previousCount = messages.length;
      await loadOlderMessages();
      if (messages.length == previousCount && hasMoreMessages) break;
    }
  }

  Future<bool> loadMessageUntilVisible(int messageId) async {
    if (messageId <= 0) return false;
    while (!messages.any((message) => message.id == messageId) &&
        hasMoreMessages) {
      if (loadingOlderMessages) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        continue;
      }
      final beforeCount = messages.length;
      await loadOlderMessages();
      if (messages.length == beforeCount &&
          !messages.any((message) => message.id == messageId)) {
        break;
      }
    }
    return messages.any((message) => message.id == messageId);
  }

  void clearSelectedConversation() {
    stopTyping();
    selectedConversation = null;
    messageFocusId = 0;
    messageFocusConversationId = 0;
    messages = [];
    hasMoreMessages = false;
    loadingOlderMessages = false;
    notifyListeners();
  }

  int unreadCountFor(int conversationId) =>
      unreadMessageCounts[conversationId] ?? 0;

  List<String> typingUsersFor(int conversationId) {
    final now = DateTime.now();
    return (_typingUsers[conversationId] ?? const <String, DateTime>{})
        .entries
        .where((entry) => entry.value.isAfter(now))
        .map((entry) {
      final conversation =
          conversations.where((item) => item.id == conversationId).firstOrNull;
      return conversation?.members
              .where((member) => member.userid == entry.key)
              .firstOrNull
              ?.displayName ??
          entry.key;
    }).toList();
  }

  int get totalUnreadMessages => unreadMessageCounts.values.fold(
        0,
        (total, count) => total + count,
      );

  void updateTyping(String text) {
    final conversationId = selectedConversation?.id ?? 0;
    if (conversationId <= 0) return;
    final isTyping = text.trim().isNotEmpty;
    if (!isTyping) {
      stopTyping();
      return;
    }
    if (_outgoingTypingConversationId != 0 &&
        _outgoingTypingConversationId != conversationId) {
      stopTyping();
    }
    final now = DateTime.now();
    final shouldSendStart = _outgoingTypingConversationId != conversationId ||
        _lastTypingStartSentAt == null ||
        now.difference(_lastTypingStartSentAt!) >= const Duration(seconds: 2);
    _outgoingTypingConversationId = conversationId;
    if (shouldSendStart) {
      _lastTypingStartSentAt = now;
      _sendTyping(conversationId, true);
    }
    _outgoingTypingExpiryTimer?.cancel();
    _outgoingTypingExpiryTimer = Timer(const Duration(seconds: 4), stopTyping);
  }

  void stopTyping() {
    _outgoingTypingExpiryTimer?.cancel();
    _outgoingTypingExpiryTimer = null;
    final conversationId = _outgoingTypingConversationId;
    _outgoingTypingConversationId = 0;
    _lastTypingStartSentAt = null;
    if (conversationId > 0) _sendTyping(conversationId, false);
  }

  void _sendTyping(int conversationId, bool isTyping) {
    final sent = realtimeService.sendEvent(
      isTyping ? 'typing.start' : 'typing.stop',
      conversationId: conversationId,
      payload: {'isTyping': isTyping},
    );
    if (!sent) {
      unawaited(
          apiClient.setTyping(conversationId, isTyping).catchError((_) {}));
    }
  }

  Future<void> markConversationRead(int conversationId, int messageId) async {
    if (conversationId <= 0 ||
        messageId <= 0 ||
        !isAppResumed ||
        selectedConversation?.id != conversationId) {
      return;
    }
    final previousPending = _pendingReadTargets[conversationId] ?? 0;
    final previousActive = _activeReadTargets[conversationId] ?? 0;
    if (messageId > previousPending && messageId > previousActive) {
      _pendingReadTargets[conversationId] = messageId;
    }
    if (!_markReadInFlight.add(conversationId)) return;
    try {
      while ((_pendingReadTargets[conversationId] ?? 0) > 0) {
        if (!isAppResumed || selectedConversation?.id != conversationId) {
          break;
        }
        final target = _pendingReadTargets.remove(conversationId)!;
        _activeReadTargets[conversationId] = target;
        try {
          final state =
              await apiClient.markConversationRead(conversationId, target);
          _applyReadState(state);
        } catch (_) {
          final queued = _pendingReadTargets[conversationId] ?? 0;
          if (target > queued) _pendingReadTargets[conversationId] = target;
          break;
        }
      }
    } finally {
      _activeReadTargets.remove(conversationId);
      _markReadInFlight.remove(conversationId);
    }
  }

  Future<void> _ackDelivered(int conversationId, int messageId) async {
    if (conversationId <= 0 || messageId <= 0) return;
    final previousPending = _pendingDeliveredTargets[conversationId] ?? 0;
    final previousActive = _activeDeliveredTargets[conversationId] ?? 0;
    if (messageId > previousPending && messageId > previousActive) {
      _pendingDeliveredTargets[conversationId] = messageId;
    }
    if (!_deliveredInFlight.add(conversationId)) return;
    try {
      while ((_pendingDeliveredTargets[conversationId] ?? 0) > 0) {
        final target = _pendingDeliveredTargets.remove(conversationId)!;
        _activeDeliveredTargets[conversationId] = target;
        try {
          await apiClient.markMessageDelivered(conversationId, target);
        } catch (_) {
          final queued = _pendingDeliveredTargets[conversationId] ?? 0;
          if (target > queued) {
            _pendingDeliveredTargets[conversationId] = target;
          }
          break;
        }
      }
    } finally {
      _activeDeliveredTargets.remove(conversationId);
      _deliveredInFlight.remove(conversationId);
    }
  }

  Future<void> sendText(String content, {ChatMessage? replyTo}) async {
    final conversation = selectedConversation;
    final trimmed = content.trim();
    if (conversation == null || trimmed.isEmpty) return;
    stopTyping();
    final pending = _newPendingMessage(
      conversationId: conversation.id,
      clientMessageId: const Uuid().v4(),
      type: _isLinkMessageContent(trimmed) ? 'link' : 'text',
      content: trimmed,
      replyTo: replyTo,
    );
    _upsertMessage(pending);
    await _submitPendingMessage(pending);
  }

  Future<void> sendFiles(List<File> files,
      {String type = 'file', ChatMessage? replyTo}) async {
    final conversation = selectedConversation;
    if (conversation == null || files.isEmpty) return;
    final attachments = await apiClient.uploadFiles(files);
    final pending = _newPendingMessage(
      conversationId: conversation.id,
      clientMessageId: const Uuid().v4(),
      type: type,
      attachments: attachments,
      replyTo: replyTo,
    );
    _upsertMessage(pending);
    await _submitPendingMessage(pending);
  }

  Future<bool> forwardMessage(
      ChatConversation target, ChatMessage message) async {
    if (message.type == 'poll' || message.type == 'system') return false;
    final pending = _newPendingMessage(
      conversationId: target.id,
      clientMessageId: const Uuid().v4(),
      type: message.type,
      content: message.content,
      attachments: message.attachments,
      forwardedFrom: message,
    );
    _upsertMessage(pending);
    final sent = await _submitPendingMessage(pending);
    if (sent) {
      await refreshChat(reloadSelected: false);
    }
    return sent;
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (!message.canRetry) return;
    final retrying = message.copyWith(state: MessageState.sending);
    _upsertMessage(retrying);
    await _submitPendingMessage(retrying);
  }

  Future<void> editMessage(ChatMessage message, String content) async {
    final trimmed = content.trim();
    if (message.id <= 0 ||
        message.senderUserid != tokenStore.userid ||
        message.isDeleted ||
        trimmed.isEmpty ||
        trimmed == message.content.trim()) {
      return;
    }
    final updated = await apiClient.editMessage(
      message.id,
      content: trimmed,
      version: message.version,
    );
    _upsertMessage(updated);
  }

  Future<void> recallMessage(ChatMessage message) async {
    if (message.id <= 0 ||
        message.senderUserid != tokenStore.userid ||
        message.isDeleted) {
      return;
    }
    final updated = await apiClient.recallMessage(
      message.id,
      version: message.version,
    );
    _upsertMessage(updated);
  }

  Future<void> deleteMessageForMe(ChatMessage message) async {
    if (message.id <= 0) {
      final pending = _pendingMessagesByClientId[message.clientMessageId];
      if (message.senderUserid == tokenStore.userid &&
          pending?.hasSameClientIdentity(message) == true) {
        _pendingMessagesByClientId.remove(message.clientMessageId);
      }
      messages.removeWhere((item) => item.id == message.id);
      notifyListeners();
      await _persistRuntimeSnapshot();
      return;
    }
    await apiClient.deleteMessageForMe(message.id);
    _removeMessage(message.conversationId, message.id);
  }

  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    if (message.id <= 0 || message.isDeleted || emoji.trim().isEmpty) return;
    final existing = message.reactions
        .where((reaction) => reaction.emoji == emoji)
        .firstOrNull;
    final reactions = existing?.reactedByMe == true
        ? await apiClient.removeReaction(message.id, emoji)
        : await apiClient.addReaction(message.id, emoji);
    _upsertMessage(message.copyWith(reactions: reactions));
  }

  Future<void> setConversationMuted(ChatConversation conversation, bool muted,
      {Duration duration = const Duration(hours: 8)}) async {
    final settings = await apiClient.updateConversationSettings(
      conversation.id,
      muteUntil: muted ? DateTime.now().add(duration) : null,
    );
    _updateConversationSettings(conversation.id, settings);
  }

  Future<void> setConversationPinned(
      ChatConversation conversation, bool pinned) async {
    final settings = await apiClient.updateConversationSettings(
      conversation.id,
      pinnedAt: pinned ? DateTime.now() : null,
    );
    _updateConversationSettings(conversation.id, settings);
  }

  Future<void> setConversationArchived(
      ChatConversation conversation, bool archived) async {
    final settings = await apiClient.updateConversationSettings(
      conversation.id,
      archivedAt: archived ? DateTime.now() : null,
    );
    _updateConversationSettings(conversation.id, settings);
  }

  ChatMessage _newPendingMessage({
    required int conversationId,
    required String clientMessageId,
    required String type,
    String content = '',
    List<ChatAttachment> attachments = const [],
    ChatMessage? replyTo,
    ChatMessage? forwardedFrom,
  }) {
    final currentUser = me;
    return ChatMessage(
      id: _nextLocalMessageId--,
      conversationId: conversationId,
      senderUserid: tokenStore.userid ?? currentUser?.userid ?? '',
      senderName: currentUser?.displayName ?? tokenStore.fullname ?? '',
      senderAvatar: currentUser?.avatar ?? '',
      type: type,
      content: content,
      replyTo: replyTo == null
          ? null
          : ChatMessageReference(
              id: replyTo.id,
              senderUserid: replyTo.senderUserid,
              senderName: replyTo.senderName,
              type: replyTo.type,
              content: replyTo.content,
            ),
      forwardedFrom: forwardedFrom == null
          ? null
          : ChatMessageReference(
              id: forwardedFrom.id,
              senderUserid: forwardedFrom.senderUserid,
              senderName: forwardedFrom.senderName,
              type: forwardedFrom.type,
              content: forwardedFrom.content,
            ),
      attachments: attachments,
      createdAt: DateTime.now(),
      clientMessageId: clientMessageId,
      state: MessageState.sending,
    );
  }

  Future<bool> _submitPendingMessage(ChatMessage pending) async {
    if (pending.clientMessageId.isEmpty ||
        !_submittingClientMessageIds.add(pending.clientMessageId)) {
      return false;
    }
    try {
      final persisted = await _persistRuntimeSnapshot();
      if (!persisted) {
        final current = _pendingMessagesByClientId[pending.clientMessageId];
        if (current != null) {
          _upsertMessage(current.copyWith(state: MessageState.failed));
        }
        return false;
      }
      final message = await apiClient.sendMessage(
        pending.conversationId,
        clientMessageId: pending.clientMessageId,
        type: pending.type,
        content: pending.content,
        replyToMessageId: pending.replyTo?.id ?? 0,
        forwardedFromMessageId: pending.forwardedFrom?.id ?? 0,
        attachments: pending.attachments,
      );
      _upsertMessage(message.clientMessageId.isEmpty
          ? message.copyWith(clientMessageId: pending.clientMessageId)
          : message);
      await _persistRuntimeSnapshot();
      return true;
    } catch (_) {
      final current = _pendingMessagesByClientId[pending.clientMessageId];
      if (current != null && current.id <= 0) {
        _upsertMessage(current.copyWith(state: MessageState.failed));
      }
      await _persistRuntimeSnapshot();
      return false;
    } finally {
      _submittingClientMessageIds.remove(pending.clientMessageId);
    }
  }

  void _updateConversationSettings(
      int conversationId, ConversationSettings settings) {
    conversations = conversations
        .map((conversation) => conversation.id == conversationId
            ? conversation.copyWith(settings: settings)
            : conversation)
        .toList()
      ..sort(_sortConversations);
    if (selectedConversation?.id == conversationId) {
      selectedConversation = conversations
          .where((conversation) => conversation.id == conversationId)
          .firstOrNull;
    }
    notifyListeners();
  }

  Future<void> _restoreRuntimeSnapshot() async {
    final currentUserid = tokenStore.userid?.trim() ?? '';
    if (currentUserid.isEmpty) return;
    _restoringRuntimeSnapshot = true;
    try {
      final raw = await tokenStore.readChatRuntime(currentUserid);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Invalid chat runtime');
      final snapshot = ChatRuntimeSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      _pendingMessagesByClientId.clear();
      var lowestLocalId = -1;
      for (final message in snapshot.pendingMessages) {
        if (message.senderUserid != currentUserid) {
          continue;
        }
        final restored = message.copyWith(state: MessageState.failed);
        _pendingMessagesByClientId[restored.clientMessageId] = restored;
        if (restored.id <= lowestLocalId) lowestLocalId = restored.id - 1;
      }
      _lastSeenMessageIds
        ..clear()
        ..addAll(snapshot.lastSeenMessageIds);
      _lastSeenSequences
        ..clear()
        ..addAll(snapshot.lastSeenSequences);
      _nextLocalMessageId = lowestLocalId;
    } catch (_) {
      _pendingMessagesByClientId.clear();
      _lastSeenMessageIds.clear();
      _lastSeenSequences.clear();
      _nextLocalMessageId = -1;
      try {
        await tokenStore.clearChatRuntime(currentUserid);
      } catch (_) {}
    } finally {
      _restoringRuntimeSnapshot = false;
    }
  }

  ChatRuntimeSnapshot _runtimeSnapshot() {
    final pending = _pendingMessagesByClientId.values.toList()
      ..sort(_sortMessages);
    return ChatRuntimeSnapshot(
      pendingMessages: pending,
      lastSeenMessageIds: Map<int, int>.from(_lastSeenMessageIds),
      lastSeenSequences: Map<int, int>.from(_lastSeenSequences),
    );
  }

  ChatMessageReference? pinnedMessageFor(int conversationId) {
    if (selectedConversation?.id == conversationId) {
      return selectedConversation?.pinnedMessage;
    }
    return conversations
        .where((conversation) => conversation.id == conversationId)
        .firstOrNull
        ?.pinnedMessage;
  }

  Future<void> pinMessage(ChatMessage message) async {
    if (message.conversationId <= 0 || message.id <= 0) return;
    final state =
        await apiClient.setPinnedMessage(message.conversationId, message.id);
    _applyPinnedMessageState(state);
  }

  Future<void> unpinMessage(int conversationId) async {
    if (conversationId <= 0) return;
    final state = await apiClient.setPinnedMessage(conversationId, 0);
    _applyPinnedMessageState(state);
  }

  Future<bool> _persistRuntimeSnapshot() {
    _runtimePersistenceTimer?.cancel();
    _runtimePersistenceTimer = null;
    if (_restoringRuntimeSnapshot) return Future<bool>.value(true);
    final currentUserid = tokenStore.userid?.trim() ?? '';
    if (currentUserid.isEmpty) return Future<bool>.value(false);
    final epoch = _runtimePersistenceEpoch;
    final encoded = jsonEncode(_runtimeSnapshot().toJson());
    final result = _runtimePersistenceTail.then<bool>((_) async {
      if (epoch != _runtimePersistenceEpoch ||
          currentUserid != (tokenStore.userid?.trim() ?? '')) {
        return false;
      }
      try {
        await tokenStore.writeChatRuntime(currentUserid, encoded);
        return true;
      } catch (_) {
        return false;
      }
    });
    _runtimePersistenceTail = result.then<void>((_) {});
    return result;
  }

  void _scheduleRuntimePersistence() {
    if (_restoringRuntimeSnapshot || !isAuthenticated) return;
    _runtimePersistenceTimer?.cancel();
    _runtimePersistenceTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistRuntimeSnapshot());
    });
  }

  void _applyPendingOutboxToConversationSummaries() {
    if (_pendingMessagesByClientId.isEmpty || conversations.isEmpty) return;
    var reconciled = false;
    for (final conversation in conversations) {
      final clientMessageId = conversation.lastMessage?.clientMessageId ?? '';
      if (clientMessageId.isNotEmpty &&
          conversation.lastMessage?.senderUserid == tokenStore.userid) {
        reconciled =
            _pendingMessagesByClientId.remove(clientMessageId) != null ||
                reconciled;
      }
    }
    if (reconciled) _scheduleRuntimePersistence();
    for (final pending in _pendingMessagesByClientId.values) {
      conversations = conversations.map((conversation) {
        if (conversation.id != pending.conversationId) return conversation;
        final last = conversation.lastMessage;
        if (last == null || _isMessageLater(pending, last)) {
          return conversation.copyWith(lastMessage: pending);
        }
        return conversation;
      }).toList();
    }
  }

  Future<void> _retryPendingOutbox() async {
    final pending = _pendingMessagesByClientId.values.toList()
      ..sort(_sortMessages);
    for (final message in pending) {
      if (!isAuthenticated ||
          !_pendingMessagesByClientId.containsKey(message.clientMessageId)) {
        continue;
      }
      final retrying = message.copyWith(state: MessageState.sending);
      _upsertMessage(retrying);
      await _submitPendingMessage(retrying);
    }
  }

  Future<void> createPoll({
    required String question,
    required List<String> options,
    required bool allowCustomOptions,
    required bool allowMultiple,
    required bool showVoters,
  }) async {
    final conversation = selectedConversation;
    if (conversation == null) return;
    final message = await apiClient.createPoll(
      conversation.id,
      question: question,
      options: options,
      allowCustomOptions: allowCustomOptions,
      allowMultiple: allowMultiple,
      showVoters: showVoters,
    );
    _upsertMessage(message);
    await refreshChat(reloadSelected: false);
  }

  Future<void> votePoll(ChatMessage message, List<int> optionIds,
      {String customOption = ''}) async {
    final updated = await apiClient.votePoll(
      message.id,
      optionIds: optionIds,
      customOption: customOption,
    );
    _upsertMessage(updated);
  }

  Future<void> closePoll(ChatMessage message) async {
    final updated = await apiClient.closePoll(message.id);
    _upsertMessage(updated);
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

  Future<void> createGroupConversation(
    String name,
    List<String> memberUserids,
  ) async {
    final conversation =
        await apiClient.createGroupConversation(name, memberUserids);
    conversations.removeWhere((item) => item.id == conversation.id);
    conversations.insert(0, conversation);
    await selectConversation(conversation);
  }

  Future<void> openSearchMessage(
    ChatConversation conversation,
    int messageId,
  ) async {
    await selectConversation(conversation);
    await loadMessageUntilVisible(messageId);
    messageFocusId = messageId;
    messageFocusConversationId = conversation.id;
    messageFocusSequence += 1;
    notifyListeners();
  }

  void clearMessageFocus(int sequence) {
    if (sequence != messageFocusSequence) return;
    messageFocusId = 0;
    messageFocusConversationId = 0;
  }

  Future<void> addContact(String userid) async {
    final contact = await apiClient.addContact(userid);
    final index = contacts.indexWhere((item) => item.userid == contact.userid);
    if (index >= 0) {
      contacts[index] = contact;
    } else {
      contacts.add(contact);
    }
    contacts.sort(_compareContacts);
    notifyListeners();
  }

  Future<void> updateContactNickname(String userid, String nickname) async {
    final contact = await apiClient.updateContactNickname(userid, nickname);
    final index = contacts.indexWhere((item) => item.userid == contact.userid);
    if (index >= 0) contacts[index] = contact;
    contacts.sort(_compareContacts);
    await refreshChat(reloadSelected: false);
    final selectedId = selectedConversation?.id;
    if (selectedId != null) {
      selectedConversation = conversations
          .where((conversation) => conversation.id == selectedId)
          .firstOrNull;
    }
    notifyListeners();
  }

  Future<void> updateConversationMemberNickname(
    int conversationId,
    String userid,
    String nickname,
  ) async {
    final conversation = await apiClient.updateConversationMemberNickname(
      conversationId,
      userid,
      nickname,
    );
    final index =
        conversations.indexWhere((item) => item.id == conversation.id);
    if (index >= 0) {
      conversations[index] = conversation;
    }
    if (selectedConversation?.id == conversation.id) {
      await selectConversation(conversation);
    } else {
      notifyListeners();
    }
  }

  int _compareContacts(ChatUser first, ChatUser second) {
    final firstName = _contactDisplayName(first).toLowerCase();
    final secondName = _contactDisplayName(second).toLowerCase();
    final byName = firstName.compareTo(secondName);
    if (byName != 0) return byName;
    return first.userid.toLowerCase().compareTo(second.userid.toLowerCase());
  }

  String _contactDisplayName(ChatUser user) {
    return user.displayName;
  }

  void _connectRealtime() {
    if (!isAuthenticated || !_networkAvailable) return;
    if (!isAppResumed && callState == 'idle') return;
    unawaited(realtimeService.connect(
      onEvent: _handleRealtimeEvent,
      onError: (_) => _scheduleRealtimeReconnect(),
      onConnected: () => unawaited(_handleRealtimeConnected()),
      onDone: _scheduleRealtimeReconnect,
    ));
  }

  Future<void> _handleRealtimeConnected() async {
    _reconnectTimer?.cancel();
    realtimeService.restoreSubscriptions(
      conversations.map((conversation) => conversation.id),
    );
    _realtimeStableTimer?.cancel();
    _realtimeStableTimer = Timer(const Duration(seconds: 30), () {
      _reconnectAttempt = 0;
      _realtimeStableTimer = null;
    });
    final knownConversationIds =
        conversations.map((conversation) => conversation.id).toSet();
    await _catchUpAfterReconnect();
    if (!isAuthenticated) return;
    try {
      await refreshChat(
        reloadSelected: false,
        seedMissing: false,
      );
      final newConversationIds = conversations
          .map((conversation) => conversation.id)
          .where((id) => !knownConversationIds.contains(id))
          .toSet();
      if (newConversationIds.isNotEmpty) {
        await _catchUpAfterReconnect(
          conversationIds: newConversationIds,
          startAtBeginning: true,
        );
      }
    } catch (_) {
      // Realtime remains usable while the conversation summary retries later.
    }
  }

  Future<void> _catchUpAfterReconnect({
    Set<int>? conversationIds,
    bool startAtBeginning = false,
  }) async {
    if (_catchingUp || !isAuthenticated) return;
    _catchingUp = true;
    try {
      final snapshot = conversations.map((conversation) {
        return (
          conversation: conversation,
          afterMessageId:
              startAtBeginning ? 0 : _lastSeenMessageIds[conversation.id] ?? 0,
          afterSequence:
              startAtBeginning ? 0 : _lastSeenSequences[conversation.id] ?? 0,
        );
      }).where((cursor) {
        return conversationIds == null ||
            conversationIds.contains(cursor.conversation.id);
      }).toList();
      for (final cursorSnapshot in snapshot) {
        final conversation = cursorSnapshot.conversation;
        var afterMessageId = cursorSnapshot.afterMessageId;
        var afterSequence = cursorSnapshot.afterSequence;
        var hasMore = true;
        var pageCount = 0;
        var latestIncoming = 0;
        while (hasMore && pageCount < 100) {
          pageCount += 1;
          try {
            final page = await apiClient.catchUpMessages(
              conversation.id,
              afterMessageId: afterMessageId,
              afterSequence: afterSequence,
              limit: 100,
            );
            for (final message in page.messages) {
              _upsertMessage(message, notify: false);
              if (message.senderUserid != tokenStore.userid &&
                  message.id > latestIncoming) {
                latestIncoming = message.id;
              }
            }
            if (page.unreadCount != null) {
              _setUnreadCount(conversation.id, page.unreadCount!);
            }
            final nextMessageId = page.nextAfterMessageId;
            final nextSequence = page.nextAfterSequence;
            final advanced = nextMessageId > afterMessageId ||
                nextSequence > afterSequence ||
                page.messages.isNotEmpty;
            final lastPageMessage =
                page.messages.isEmpty ? null : page.messages.last;
            afterMessageId = nextMessageId > 0
                ? nextMessageId
                : lastPageMessage?.id ?? afterMessageId;
            afterSequence = nextSequence > 0
                ? nextSequence
                : lastPageMessage?.serverSequence ?? afterSequence;
            hasMore = page.hasMore && advanced;
          } catch (_) {
            break;
          }
        }
        if (latestIncoming > 0) {
          unawaited(_ackDelivered(conversation.id, latestIncoming));
        }
        if (selectedConversation?.id == conversation.id && afterMessageId > 0) {
          unawaited(markConversationRead(conversation.id, afterMessageId));
        }
      }
      notifyListeners();
    } finally {
      _catchingUp = false;
    }
  }

  void _scheduleRealtimeReconnect() {
    if (!isAuthenticated || !_networkAvailable) return;
    if (!isAppResumed && callState == 'idle') return;
    _reconnectTimer?.cancel();
    _realtimeStableTimer?.cancel();
    _realtimeStableTimer = null;
    const baseDelayMs = 1000;
    const maxDelayMs = 30000;
    final exponent = _reconnectAttempt > 10 ? 10 : _reconnectAttempt;
    final cappedDelay = min(maxDelayMs, baseDelayMs * (1 << exponent));
    final delayMs = (cappedDelay ~/ 2) +
        _reconnectRandom.nextInt(max(1, cappedDelay - (cappedDelay ~/ 2)));
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), _connectRealtime);
  }

  void _handleRealtimeEvent(RealtimeEvent event) {
    if (event.eventId.isNotEmpty && !_rememberRealtimeEvent(event.eventId)) {
      return;
    }
    if (event.type.startsWith('call.')) {
      unawaited(_handleCallRealtimeEvent(event));
      return;
    }
    final type = event.type.startsWith('chat.')
        ? event.type.substring('chat.'.length)
        : event.type;
    if (type == 'message.created' ||
        type == 'message.updated' ||
        type == 'message.edited' ||
        type == 'message.recalled' ||
        type == 'poll.updated') {
      final rawMessage = event.message;
      final message =
          rawMessage == null ? null : _personalizeMessageReactions(rawMessage);
      if (message != null) {
        final wasKnown = _containsMessage(message);
        _upsertMessage(message);
        if (type == 'message.created' &&
            message.type != 'system' &&
            message.senderUserid != tokenStore.userid) {
          unawaited(_ackDelivered(message.conversationId, message.id));
          final activelyReading = isAppResumed &&
              message.conversationId == selectedConversation?.id;
          if (activelyReading) {
            unawaited(markConversationRead(message.conversationId, message.id));
          } else if (!wasKnown) {
            final serverUnread = _eventInt(event, 'unreadCount');
            if (serverUnread >= 0) {
              _setUnreadCount(message.conversationId, serverUnread);
            } else {
              _incrementUnread(message.conversationId);
            }
            final conversation = conversations
                .where((item) => item.id == message.conversationId)
                .firstOrNull;
            if (isAppResumed && conversation?.settings.isMuted != true) {
              unawaited(pushService.showChatMessage(
                message: message,
                conversationTitle: _notificationConversationTitle(message),
                unreadCount: unreadCountFor(message.conversationId),
              ));
            }
          }
        }
      }
      if (message == null && event.messageId > 0) {
        _applyMessageLifecycleEvent(type, event);
      }
      if (type == 'message.recalled') {
        unawaited(refreshChat(reloadSelected: false).catchError((_) {}));
      }
      return;
    }
    if (type == 'message.deleted' || type == 'message.deleted.for_me') {
      final affectedUserid = _eventString(event, 'userid', 'userId');
      if (affectedUserid.isEmpty || affectedUserid == tokenStore.userid) {
        _removeMessage(event.conversationId, event.messageId);
      }
      return;
    }
    if (type.startsWith('reaction.')) {
      final message = event.message == null
          ? null
          : _personalizeMessageReactions(event.message!);
      if (message != null) {
        _upsertMessage(message);
      } else {
        final action = _eventString(event, 'action');
        _applyReaction(
          messageId: event.messageId,
          emoji: _eventString(event, 'emoji'),
          userid: event.userid.isNotEmpty
              ? event.userid
              : _eventString(event, 'userid', 'userId'),
          added: action != 'removed' && type != 'reaction.removed',
        );
      }
      return;
    }
    if (type == 'read.receipt') {
      _applyReadReceipt(event);
      return;
    }
    if (type == 'delivery.receipt' || type == 'delivered.receipt') {
      _applyDeliveryReceipt(event);
      return;
    }
    if (type == 'typing.start' || type == 'typing.stop') {
      _applyTypingEvent(event, started: type == 'typing.start');
      return;
    }
    if (type == 'message.pinned' || type == 'message.unpinned') {
      final payload = Map<String, dynamic>.from(event.payload);
      payload.putIfAbsent('conversationId', () => event.conversationId);
      payload.putIfAbsent('actorUserid', () => event.userid);
      final state = PinnedMessageState.fromJson(payload);
      _applyPinnedMessageState(state);
      return;
    }
    if (type == 'conversation.settings.updated') {
      final raw = event.payload['settings'];
      if (raw is Map) {
        _updateConversationSettings(
          event.conversationId,
          ConversationSettings.fromJson(Map<String, dynamic>.from(raw)),
        );
      }
      return;
    }
    if (type == 'presence.changed' && event.userid.isNotEmpty) {
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

  void _upsertMessage(ChatMessage message, {bool notify = true}) {
    var outboxChanged = false;
    if (message.clientMessageId.isNotEmpty &&
        (message.id <= 0 || message.senderUserid == tokenStore.userid)) {
      if (message.id <= 0) {
        _pendingMessagesByClientId[message.clientMessageId] = message;
        outboxChanged = true;
      } else {
        outboxChanged =
            _pendingMessagesByClientId.remove(message.clientMessageId) != null;
      }
    }
    _observeMessageCursor(message);
    if (selectedConversation?.id == message.conversationId) {
      final index = messages.indexWhere((item) =>
          (message.id > 0 && item.id == message.id) ||
          item.hasSameClientIdentity(message));
      if (index >= 0) {
        messages[index] = _mergeMessage(messages[index], message);
      } else {
        messages.add(message);
      }
      messages.sort(_sortMessages);
    }
    conversations = conversations.map((conversation) {
      if (conversation.id == message.conversationId) {
        final last = conversation.lastMessage;
        if (last == null ||
            last.id == message.id ||
            last.hasSameClientIdentity(message) ||
            _isMessageLater(message, last)) {
          return conversation.copyWith(
              lastMessage:
                  last == null ? message : _mergeMessage(last, message));
        }
      }
      return conversation;
    }).toList()
      ..sort(_sortConversations);
    if (outboxChanged) _scheduleRuntimePersistence();
    if (notify) notifyListeners();
  }

  void _incrementUnread(int conversationId) {
    _setUnreadCount(conversationId, unreadCountFor(conversationId) + 1);
  }

  void _setUnreadCount(int conversationId, int count) {
    unreadMessageCounts = Map<int, int>.from(unreadMessageCounts);
    if (count <= 0) {
      unreadMessageCounts.remove(conversationId);
    } else {
      unreadMessageCounts[conversationId] = count;
    }
    conversations = conversations
        .map((conversation) => conversation.id == conversationId
            ? conversation.copyWith(unreadCount: count)
            : conversation)
        .toList();
    notifyListeners();
  }

  bool _rememberRealtimeEvent(String eventId) {
    if (!_handledRealtimeEventIds.add(eventId)) return false;
    _handledRealtimeEventOrder.add(eventId);
    if (_handledRealtimeEventOrder.length > 2048) {
      final removed = _handledRealtimeEventOrder.removeAt(0);
      _handledRealtimeEventIds.remove(removed);
    }
    return true;
  }

  bool _containsMessage(ChatMessage message) {
    if (message.clientMessageId.isNotEmpty &&
        _pendingMessagesByClientId.containsKey(message.clientMessageId)) {
      final pending = _pendingMessagesByClientId[message.clientMessageId];
      if (pending?.senderUserid == message.senderUserid) return true;
    }
    if (selectedConversation?.id == message.conversationId &&
        messages.any((item) =>
            (message.id > 0 && item.id == message.id) ||
            item.hasSameClientIdentity(message))) {
      return true;
    }
    return conversations.any((conversation) {
      final last = conversation.lastMessage;
      return conversation.id == message.conversationId &&
          last != null &&
          ((message.id > 0 && last.id == message.id) ||
              last.hasSameClientIdentity(message));
    });
  }

  ChatMessage _personalizeMessageReactions(ChatMessage message) {
    final currentUserid = tokenStore.userid ?? '';
    if (currentUserid.isEmpty || message.reactions.isEmpty) return message;
    return message.copyWith(
      reactions: message.reactions
          .map((reaction) => reaction.copyWith(
                reactedByMe: reaction.userids.contains(currentUserid),
              ))
          .toList(),
    );
  }

  Object? _eventValue(RealtimeEvent event, String first,
      [String? second, String? third]) {
    if (event.payload.containsKey(first)) return event.payload[first];
    if (second != null && event.payload.containsKey(second)) {
      return event.payload[second];
    }
    if (third != null && event.payload.containsKey(third)) {
      return event.payload[third];
    }
    final nested = event.payload['receipt'];
    if (nested is Map) {
      if (nested.containsKey(first)) return nested[first];
      if (second != null && nested.containsKey(second)) return nested[second];
      if (third != null && nested.containsKey(third)) return nested[third];
    }
    return null;
  }

  int _eventInt(RealtimeEvent event, String first,
      [String? second, String? third]) {
    final value = _eventValue(event, first, second, third);
    if (value == null) return -1;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? -1;
  }

  String _eventString(RealtimeEvent event, String first, [String? second]) {
    final value = _eventValue(event, first, second);
    return value == null ? '' : '$value';
  }

  ChatMessage _mergeMessage(ChatMessage existing, ChatMessage incoming) {
    if (existing.id > 0 &&
        existing.id == incoming.id &&
        incoming.version < existing.version) {
      return existing;
    }
    final localTransition = incoming.state == MessageState.sending ||
        incoming.state == MessageState.failed ||
        existing.state == MessageState.sending ||
        existing.state == MessageState.failed;
    final state = localTransition
        ? incoming.state
        : _messageStateRank(existing.state) > _messageStateRank(incoming.state)
            ? existing.state
            : incoming.state;
    return incoming.copyWith(
      state: state,
      totalRecipients: incoming.totalRecipients > 0
          ? incoming.totalRecipients
          : existing.totalRecipients,
      deliveredCount: incoming.deliveredCount > existing.deliveredCount
          ? incoming.deliveredCount
          : existing.deliveredCount,
      readCount: incoming.readCount > existing.readCount
          ? incoming.readCount
          : existing.readCount,
      readReceipts: incoming.readReceipts.isEmpty &&
              incoming.deliveredCount == 0 &&
              incoming.readCount == 0 &&
              (existing.deliveredCount > 0 || existing.readCount > 0)
          ? existing.readReceipts
          : incoming.readReceipts,
      reactions: incoming.reactions,
    );
  }

  int _messageStateRank(MessageState state) => switch (state) {
        MessageState.failed => 0,
        MessageState.sending => 1,
        MessageState.sent => 2,
        MessageState.delivered => 3,
        MessageState.read => 4,
      };

  void _observeMessageCursor(ChatMessage message) {
    if (message.id <= 0 || message.conversationId <= 0) return;
    var changed = false;
    final previousId = _lastSeenMessageIds[message.conversationId] ?? 0;
    if (message.id > previousId) {
      _lastSeenMessageIds[message.conversationId] = message.id;
      changed = true;
    }
    if (message.serverSequence > 0) {
      final previousSequence = _lastSeenSequences[message.conversationId] ?? 0;
      if (message.serverSequence > previousSequence) {
        _lastSeenSequences[message.conversationId] = message.serverSequence;
        changed = true;
      }
    }
    if (changed) _scheduleRuntimePersistence();
  }

  bool _isMessageLater(ChatMessage left, ChatMessage right) {
    if (left.serverSequence > 0 && right.serverSequence > 0) {
      return left.serverSequence > right.serverSequence;
    }
    final leftTime = left.createdAt;
    final rightTime = right.createdAt;
    if (leftTime != null && rightTime != null && leftTime != rightTime) {
      return leftTime.isAfter(rightTime);
    }
    if (left.id <= 0) return right.id > 0 || leftTime != null;
    if (right.id <= 0) return false;
    return left.id > right.id;
  }

  int _sortMessages(ChatMessage left, ChatMessage right) {
    if (left.serverSequence > 0 && right.serverSequence > 0) {
      final bySequence = left.serverSequence.compareTo(right.serverSequence);
      if (bySequence != 0) return bySequence;
    }
    final leftTime = left.createdAt;
    final rightTime = right.createdAt;
    if (leftTime != null && rightTime != null) {
      final byTime = leftTime.compareTo(rightTime);
      if (byTime != 0) return byTime;
    }
    if (left.id <= 0 && right.id > 0) return 1;
    if (right.id <= 0 && left.id > 0) return -1;
    return left.id.compareTo(right.id);
  }

  void _applyMessageLifecycleEvent(String type, RealtimeEvent event) {
    final messageId = event.messageId;
    if (messageId <= 0) return;
    final existing = _messageById(messageId);
    if (existing == null) return;
    if (type == 'message.edited' || type == 'message.updated') {
      final content = _eventString(event, 'content');
      final editedAt = DateTime.tryParse(_eventString(event, 'editedAt')) ??
          event.serverTimestamp ??
          DateTime.now();
      _upsertMessage(existing.copyWith(
        content: content.isEmpty ? existing.content : content,
        editedAt: editedAt,
        version: event.version > existing.version
            ? event.version
            : existing.version + 1,
      ));
      return;
    }
    if (type == 'message.recalled') {
      _upsertMessage(existing.copyWith(
        content: '',
        attachments: const [],
        deletedAt: event.serverTimestamp ?? DateTime.now(),
        deletedBy: event.userid,
        version: event.version > existing.version
            ? event.version
            : existing.version + 1,
      ));
    }
  }

  ChatMessage? _messageById(int messageId) {
    final selected =
        messages.where((message) => message.id == messageId).firstOrNull;
    if (selected != null) return selected;
    return conversations
        .map((conversation) => conversation.lastMessage)
        .whereType<ChatMessage>()
        .where((message) => message.id == messageId)
        .firstOrNull;
  }

  void _removeMessage(int conversationId, int messageId) {
    if (messageId == 0) return;
    var outboxChanged = false;
    if (selectedConversation?.id == conversationId) {
      final removedMessages =
          messages.where((message) => message.id == messageId).toList();
      for (final removed in removedMessages) {
        if (removed.senderUserid != tokenStore.userid ||
            removed.clientMessageId.isEmpty) {
          continue;
        }
        final pending = _pendingMessagesByClientId[removed.clientMessageId];
        if (pending?.hasSameClientIdentity(removed) == true) {
          _pendingMessagesByClientId.remove(removed.clientMessageId);
          outboxChanged = true;
        }
      }
      messages.removeWhere((message) => message.id == messageId);
    }
    if (outboxChanged) unawaited(_persistRuntimeSnapshot());
    notifyListeners();
    unawaited(refreshChat(reloadSelected: false).catchError((_) {}));
  }

  void _applyReaction({
    required int messageId,
    required String emoji,
    required String userid,
    required bool added,
  }) {
    if (messageId <= 0 || emoji.isEmpty) return;
    final existing = _messageById(messageId);
    if (existing == null) return;
    final reactions = List<ChatReaction>.from(existing.reactions);
    final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
    final isMine = userid.isNotEmpty && userid == tokenStore.userid;
    if (index < 0 && added) {
      reactions.add(ChatReaction(
        emoji: emoji,
        count: 1,
        reactedByMe: isMine,
        userids: userid.isEmpty ? const [] : [userid],
      ));
    } else if (index >= 0) {
      final current = reactions[index];
      final userids = current.userids.toSet();
      if (added && userid.isNotEmpty) userids.add(userid);
      if (!added && userid.isNotEmpty) userids.remove(userid);
      final nextCount = (userids.isNotEmpty
              ? userids.length
              : (current.count + (added ? 1 : -1)).clamp(0, 1 << 30))
          .toInt();
      if (nextCount <= 0) {
        reactions.removeAt(index);
      } else {
        reactions[index] = current.copyWith(
          count: nextCount,
          reactedByMe: isMine ? added : current.reactedByMe,
          userids: userids.toList(),
        );
      }
    }
    _upsertMessage(existing.copyWith(reactions: reactions));
  }

  void _applyReadState(ConversationReadState state) {
    final conversationId = state.conversationId;
    if (conversationId <= 0) return;
    _setUnreadCount(conversationId, state.unreadCount);
    conversations = conversations
        .map((conversation) => conversation.id == conversationId
            ? conversation.copyWith(
                lastReadMessageId: state.lastReadMessageId,
                lastReadAt: state.lastReadAt,
                unreadCount: state.unreadCount,
              )
            : conversation)
        .toList();
    if (selectedConversation?.id == conversationId) {
      selectedConversation = conversations
          .where((conversation) => conversation.id == conversationId)
          .firstOrNull;
    }
    notifyListeners();
  }

  void _applyReadReceipt(RealtimeEvent event) {
    final conversationId = event.conversationId;
    final userid = event.userid.isNotEmpty
        ? event.userid
        : _eventString(event, 'userid', 'userId');
    final rawReadState = event.payload['readState'];
    final readState = rawReadState is Map
        ? ConversationReadState.fromJson(
            Map<String, dynamic>.from(rawReadState))
        : null;
    final lastReadMessageId = readState?.lastReadMessageId ??
        _eventInt(
          event,
          'lastReadMessageId',
          'messageId',
          'last_read_message_id',
        );
    if (conversationId <= 0 || lastReadMessageId <= 0) return;
    if (userid == tokenStore.userid) {
      _applyReadState(readState ??
          ConversationReadState(
            conversationId: conversationId,
            userid: userid,
            lastReadMessageId: lastReadMessageId,
            lastReadAt: event.serverTimestamp,
            unreadCount: _eventInt(event, 'unreadCount') < 0
                ? 0
                : _eventInt(event, 'unreadCount'),
          ));
      return;
    }
    final readAt = readState?.lastReadAt ??
        DateTime.tryParse(_eventString(event, 'readAt')) ??
        event.serverTimestamp ??
        DateTime.now();
    _updateOutgoingReceipts(
      conversationId: conversationId,
      throughMessageId: lastReadMessageId,
      userid: userid,
      at: readAt,
      read: true,
    );
  }

  void _applyDeliveryReceipt(RealtimeEvent event) {
    final userid = event.userid.isNotEmpty
        ? event.userid
        : _eventString(event, 'userid', 'userId');
    final messageId = event.messageId > 0
        ? event.messageId
        : _eventInt(event, 'messageId', 'lastDeliveredMessageId');
    // Receipt snapshots contain recipients only. Ignore the actor's own
    // delivery acknowledgement so it cannot be counted as a group recipient.
    if (event.conversationId <= 0 ||
        messageId <= 0 ||
        userid.isEmpty ||
        userid == tokenStore.userid) {
      return;
    }
    _updateOutgoingReceipts(
      conversationId: event.conversationId,
      throughMessageId: messageId,
      userid: userid,
      at: event.serverTimestamp ?? DateTime.now(),
      read: false,
    );
  }

  void _updateOutgoingReceipts({
    required int conversationId,
    required int throughMessageId,
    required String userid,
    required DateTime at,
    required bool read,
  }) {
    if (selectedConversation?.id == conversationId) {
      messages = messages.map((message) {
        if (message.id <= 0 ||
            message.id > throughMessageId ||
            message.senderUserid != tokenStore.userid) {
          return message;
        }
        return _messageWithReceipt(
          message,
          userid: userid,
          at: at,
          read: read,
        );
      }).toList();
    }
    final last = conversations
        .where((conversation) => conversation.id == conversationId)
        .firstOrNull
        ?.lastMessage;
    if (last != null &&
        last.id <= throughMessageId &&
        last.senderUserid == tokenStore.userid) {
      final updated = _messageWithReceipt(
        last,
        userid: userid,
        at: at,
        read: read,
      );
      conversations = conversations
          .map((conversation) => conversation.id == conversationId
              ? conversation.copyWith(lastMessage: updated)
              : conversation)
          .toList();
    }
    notifyListeners();
  }

  ChatMessage _messageWithReceipt(
    ChatMessage message, {
    required String userid,
    required DateTime at,
    required bool read,
  }) {
    final receipts = List<ChatReadReceipt>.from(message.readReceipts);
    final index = receipts.indexWhere((receipt) => receipt.userid == userid);
    final previous = index >= 0 ? receipts[index] : null;
    final receipt = ChatReadReceipt(
      userid: userid,
      messageId: message.id,
      deliveredAt: previous?.deliveredAt ?? at,
      readAt: read ? (previous?.readAt ?? at) : previous?.readAt,
    );
    if (index >= 0) {
      receipts[index] = receipt;
    } else if (userid.isNotEmpty) {
      receipts.add(receipt);
    }
    final deliveredCount =
        receipts.where((item) => item.deliveredAt != null).length;
    final readCount = receipts.where((item) => item.readAt != null).length;
    final total = message.totalRecipients;
    final computedState = total > 0 && readCount >= total
        ? MessageState.read
        : total > 0 && deliveredCount >= total
            ? MessageState.delivered
            : MessageState.sent;
    final state =
        _messageStateRank(message.state) > _messageStateRank(computedState)
            ? message.state
            : computedState;
    return message.copyWith(
      state: state,
      deliveredCount: deliveredCount > message.deliveredCount
          ? deliveredCount
          : message.deliveredCount,
      readCount: readCount > message.readCount ? readCount : message.readCount,
      readReceipts: receipts,
    );
  }

  void _applyTypingEvent(RealtimeEvent event, {required bool started}) {
    final userid = event.userid.isNotEmpty
        ? event.userid
        : _eventString(event, 'userid', 'userId');
    if (event.conversationId <= 0 ||
        userid.isEmpty ||
        userid == tokenStore.userid) {
      return;
    }
    final key = '${event.conversationId}:$userid';
    _incomingTypingExpiryTimers.remove(key)?.cancel();
    final users = Map<String, DateTime>.from(
        _typingUsers[event.conversationId] ?? const {});
    if (!started) {
      users.remove(userid);
    } else {
      users[userid] = DateTime.now().add(const Duration(seconds: 6));
      _incomingTypingExpiryTimers[key] = Timer(const Duration(seconds: 6), () {
        final current = Map<String, DateTime>.from(
            _typingUsers[event.conversationId] ?? const {});
        current.remove(userid);
        if (current.isEmpty) {
          _typingUsers.remove(event.conversationId);
        } else {
          _typingUsers[event.conversationId] = current;
        }
        _incomingTypingExpiryTimers.remove(key);
        notifyListeners();
      });
    }
    if (users.isEmpty) {
      _typingUsers.remove(event.conversationId);
    } else {
      _typingUsers[event.conversationId] = users;
    }
    notifyListeners();
  }

  void _applyPinnedMessageState(PinnedMessageState state) {
    if (state.conversationId <= 0) return;
    conversations = conversations
        .map((conversation) => conversation.id == state.conversationId
            ? conversation.copyWith(pinnedMessage: state.pinnedMessage)
            : conversation)
        .toList();
    if (selectedConversation?.id == state.conversationId) {
      selectedConversation =
          selectedConversation!.copyWith(pinnedMessage: state.pinnedMessage);
    }
    if (state.systemMessage != null) {
      _upsertMessage(state.systemMessage!, notify: false);
    }
    notifyListeners();
  }

  void _resetMessagingSessionState() {
    _runtimePersistenceTimer?.cancel();
    _runtimePersistenceTimer = null;
    _runtimePersistenceEpoch += 1;
    _outgoingTypingExpiryTimer?.cancel();
    _outgoingTypingExpiryTimer = null;
    for (final timer in _incomingTypingExpiryTimers.values) {
      timer.cancel();
    }
    _incomingTypingExpiryTimers.clear();
    _typingUsers.clear();
    _pendingMessagesByClientId.clear();
    _submittingClientMessageIds.clear();
    _lastSeenMessageIds.clear();
    _lastSeenSequences.clear();
    _handledRealtimeEventIds.clear();
    _handledRealtimeEventOrder.clear();
    _pendingReadTargets.clear();
    _markReadInFlight.clear();
    _activeReadTargets.clear();
    _pendingDeliveredTargets.clear();
    _deliveredInFlight.clear();
    _activeDeliveredTargets.clear();
    _catchingUp = false;
    _outgoingTypingConversationId = 0;
    _lastTypingStartSentAt = null;
    _nextLocalMessageId = -1;
  }

  String _notificationConversationTitle(ChatMessage message) {
    final conversation = conversations
        .where((item) => item.id == message.conversationId)
        .firstOrNull;
    if (conversation != null) {
      return conversation.titleFor(tokenStore.userid ?? '');
    }
    return message.senderName.trim().isNotEmpty
        ? message.senderName.trim()
        : 'YS Chat';
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

  bool _isUnauthorizedError(Object error) {
    return error is DioException && error.response?.statusCode == 401;
  }

  int _sortConversations(ChatConversation a, ChatConversation b) {
    if (a.settings.isArchived != b.settings.isArchived) {
      return a.settings.isArchived ? 1 : -1;
    }
    if (a.settings.isPinned != b.settings.isPinned) {
      return a.settings.isPinned ? -1 : 1;
    }
    if (a.settings.isPinned && b.settings.isPinned) {
      final byPin = b.settings.pinnedAt!.compareTo(a.settings.pinnedAt!);
      if (byPin != 0) return byPin;
    }
    final left =
        a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right =
        b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  }

  bool _transitionCallState(String nextState) {
    if (!CallStateMachine.canTransition(callState, nextState)) return false;
    callState = nextState;
    return true;
  }

  Future<void> startAudioCall() async {
    final conversation = selectedConversation;
    if (conversation == null ||
        conversation.type != 'direct' ||
        callState != 'idle') {
      return;
    }
    callId = const Uuid().v4();
    callConversationId = conversation.id;
    callPeerName = conversation.titleFor(tokenStore.userid ?? '');
    if (!_transitionCallState('outgoing')) return;
    callStatus = 'Dang goi...';
    callMuted = false;
    callSpeakerOn = false;
    _callStartedByMe = true;
    notifyListeners();

    try {
      await _prepareLocalCallMedia();
      if (!await _sendCallControlEvent(
        type: 'call.invite',
        conversationId: callConversationId,
        callId: callId,
      )) {
        _cleanupCall('Khong the bat dau cuoc goi');
        return;
      }
      _startCallTimeout();
    } catch (_) {
      _cleanupCall('Khong truy cap duoc micro');
    }
  }

  Future<void> acceptIncomingCall() async {
    if (callState != 'incoming' || callId.isEmpty) return;
    try {
      if (!await _sendCallControlEvent(
        type: 'call.accept',
        conversationId: callConversationId,
        callId: callId,
      )) {
        _cleanupCall('Cuoc goi da duoc nghe tren thiet bi khac');
        return;
      }
      if (!_transitionCallState('connecting')) return;
      callStatus = 'Dang ket noi...';
      notifyListeners();
      await _prepareLocalCallMedia();
      await _ensurePeerConnection();
      _startCallTimeout();
    } catch (_) {
      _sendCallEvent('call.end');
      _cleanupCall('Khong truy cap duoc micro');
    }
  }

  void rejectIncomingCall() {
    if (callState != 'incoming') return;
    _sendCallEvent('call.reject');
    _cleanupCall('Cuoc goi bi tu choi');
  }

  void endOrCancelCall() {
    if (callId.isEmpty) return;
    final wasActive = callState == 'active';
    _sendCallEvent(wasActive ? 'call.end' : 'call.cancel');
    _cleanupCall(
      wasActive ? 'Cuoc goi da ket thuc' : 'Cuoc goi da huy',
    );
  }

  void toggleCallMute() {
    callMuted = !callMuted;
    for (final track
        in _localCallStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !callMuted;
    }
    notifyListeners();
  }

  Future<void> toggleCallSpeaker() async {
    final nextValue = !callSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(nextValue);
      callSpeakerOn = nextValue;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _resumeNativeCallActions() async {
    final actions = <NativeCallAction>[
      ...pushService.takePendingNativeCallActions(),
      if (_pendingNativeCallAction != null) _pendingNativeCallAction!,
    ];
    _pendingNativeCallAction = null;
    for (final action in actions) {
      await _handleNativeCallAction(action);
    }
  }

  Future<void> _handleNativeCallAction(NativeCallAction action) async {
    if (!isAuthenticated || conversations.isEmpty) {
      _pendingNativeCallAction = action;
      return;
    }

    if (action.type == NativeCallActionType.accept) {
      if (callState == 'idle') {
        final conversation = conversations
            .where((item) => item.id == action.conversationId)
            .firstOrNull;
        if (conversation == null || conversation.type != 'direct') return;
        callId = action.callId;
        callConversationId = action.conversationId;
        callPeerName = action.callerName.trim().isNotEmpty
            ? action.callerName.trim()
            : conversation.titleFor(tokenStore.userid ?? '');
        if (!_transitionCallState('incoming')) return;
        callStatus = 'Cuoc goi den';
        callMuted = false;
        callSpeakerOn = false;
        _callStartedByMe = false;
        _startCallTimeout();
        notifyListeners();
      }
      if (callId == action.callId && callState == 'incoming') {
        await acceptIncomingCall();
      }
      return;
    }

    if (callId != action.callId) {
      if (action.type == NativeCallActionType.decline) {
        unawaited(_sendCallControlEvent(
          type: 'call.reject',
          conversationId: action.conversationId,
          callId: action.callId,
        ).then((_) {}));
        unawaited(pushService.endIncomingCall(action.callId));
      } else if (action.type == NativeCallActionType.ended) {
        unawaited(_sendCallControlEvent(
          type: 'call.end',
          conversationId: action.conversationId,
          callId: action.callId,
        ).then((_) {}));
        unawaited(pushService.endIncomingCall(action.callId));
      }
      return;
    }
    if (action.type == NativeCallActionType.decline &&
        callState == 'incoming') {
      rejectIncomingCall();
      return;
    }
    if (action.type == NativeCallActionType.ended && callState != 'idle') {
      endOrCancelCall();
    }
  }

  Future<void> _handleRemoteCallEvent(RemoteCallEvent event) async {
    if (event.callId != callId ||
        (event.conversationId != 0 &&
            event.conversationId != callConversationId)) {
      return;
    }

    switch (event.type) {
      case 'call.accept':
        if (callState == 'incoming') {
          unawaited(pushService.endIncomingCall(callId));
          _cleanupCall('Cuoc goi da duoc nghe tren thiet bi khac');
        } else if (callState == 'outgoing') {
          await _startOutgoingCallConnection();
        }
        break;
      case 'call.reject':
        _cleanupCall('Cuoc goi bi tu choi');
        break;
      case 'call.busy':
        _cleanupCall('Nguoi kia dang ban');
        break;
      case 'call.cancel':
        _cleanupCall('Cuoc goi da huy');
        break;
      case 'call.end':
        _cleanupCall('Cuoc goi da ket thuc');
        break;
    }
  }

  Future<void> _handleCallRealtimeEvent(RealtimeEvent event) async {
    final sender =
        event.fromUserid.isNotEmpty ? event.fromUserid : event.userid;
    if (event.sourceDeviceId.isNotEmpty &&
        event.sourceDeviceId == tokenStore.deviceId) {
      return;
    }

    if (event.type == 'call.invite') {
      if (event.callId == callId &&
          event.conversationId == callConversationId) {
        return;
      }
      if (callState != 'idle') {
        unawaited(_sendCallControlEvent(
          type: 'call.busy',
          conversationId: event.conversationId,
          callId: event.callId,
        ).then((_) {}));
        unawaited(pushService.endIncomingCall(event.callId));
        return;
      }
      final conversation = conversations
          .where((item) => item.id == event.conversationId)
          .firstOrNull;
      if (conversation == null || conversation.type != 'direct') return;
      callId = event.callId;
      callConversationId = event.conversationId;
      callPeerName = conversation.titleFor(tokenStore.userid ?? '');
      if (!_transitionCallState('incoming')) {
        callId = '';
        callConversationId = 0;
        return;
      }
      callStatus = 'Cuoc goi den';
      callMuted = false;
      callSpeakerOn = false;
      _callStartedByMe = false;
      _startCallTimeout();
      final caller = conversation.members
          .where((member) => member.userid == sender)
          .firstOrNull;
      unawaited(pushService.showIncomingCall(
        callId: callId,
        conversationId: callConversationId,
        callerName: callPeerName,
        fromUserid: sender,
        avatarUrl: caller == null || caller.avatar.isEmpty
            ? ''
            : apiClient.absoluteUrl(caller.avatar),
      ));
      notifyListeners();
      return;
    }

    if (event.callId != callId || event.conversationId != callConversationId) {
      return;
    }

    switch (event.type) {
      case 'call.accept':
        if (sender == tokenStore.userid && callState == 'incoming') {
          unawaited(pushService.endIncomingCall(callId));
          _cleanupCall('Cuoc goi da duoc nghe tren thiet bi khac');
          break;
        }
        if (callState == 'incoming') {
          unawaited(pushService.endIncomingCall(callId));
          _cleanupCall('Cuoc goi da duoc nghe tren thiet bi khac');
        } else if (callState == 'outgoing') {
          await _startOutgoingCallConnection();
        }
        break;
      case 'call.reject':
        unawaited(pushService.endIncomingCall(callId));
        _cleanupCall('Cuoc goi bi tu choi');
        break;
      case 'call.busy':
        unawaited(pushService.endIncomingCall(callId));
        _cleanupCall('Nguoi kia dang ban');
        break;
      case 'call.cancel':
        unawaited(pushService.endIncomingCall(callId));
        _cleanupCall('Cuoc goi da huy');
        break;
      case 'call.end':
        unawaited(pushService.endIncomingCall(callId));
        _cleanupCall('Cuoc goi da ket thuc');
        break;
      case 'call.offer':
        if (event.signal == null) return;
        try {
          if (callState == 'incoming' && !_transitionCallState('connecting')) {
            return;
          }
          callStatus = 'Dang ket noi...';
          notifyListeners();
          await _prepareLocalCallMedia();
          final pc = await _ensurePeerConnection();
          await pc.setRemoteDescription(_sessionDescription(event.signal!));
          await _flushPendingIceCandidates();
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          _sendCallEvent('call.answer', answer.toMap());
        } catch (_) {
          _sendCallEvent('call.end');
          _cleanupCall();
        }
        break;
      case 'call.answer':
        if (event.signal == null || _peerConnection == null) return;
        try {
          await _peerConnection!
              .setRemoteDescription(_sessionDescription(event.signal!));
          await _flushPendingIceCandidates();
        } catch (_) {
          _cleanupCall();
        }
        break;
      case 'call.ice':
        if (event.signal == null) return;
        if (_peerConnection?.getRemoteDescription() == null) {
          _pendingIceCandidates.add(event.signal!);
          return;
        }
        try {
          await _peerConnection!.addCandidate(_iceCandidate(event.signal!));
        } catch (_) {}
        break;
    }
  }

  Future<void> _prepareLocalCallMedia() async {
    if (_localCallStream != null) return;
    _localCallStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    callMuted = false;
    callSpeakerOn = false;
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  Future<RTCPeerConnection> _ensurePeerConnection() async {
    if (_peerConnection != null) return _peerConnection!;
    final pc = await createPeerConnection({
      'iceServers': await apiClient.iceServers(),
    });
    _peerConnection = pc;
    for (final track in _localCallStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(track, _localCallStream!);
    }
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _sendCallEvent('call.ice', candidate.toMap());
      }
    };
    pc.onTrack = (_) => _activateCall();
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _activateCall();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _cleanupCall();
      }
    };
    return pc;
  }

  Future<void> _startOutgoingCallConnection() async {
    if (callState != 'outgoing' || _callOfferStarted) return;
    _callOfferStarted = true;
    if (!_transitionCallState('connecting')) return;
    callStatus = 'Dang ket noi...';
    notifyListeners();
    try {
      await _prepareLocalCallMedia();
      final pc = await _ensurePeerConnection();
      final offer = await pc.createOffer(
          {'offerToReceiveAudio': true, 'offerToReceiveVideo': false});
      await pc.setLocalDescription(offer);
      _sendCallEvent('call.offer', offer.toMap());
      _startCallTimeout();
    } catch (_) {
      _sendCallEvent('call.end');
      _cleanupCall('Goi dien khong thanh cong');
    }
  }

  Future<bool> _sendCallControlEvent({
    required String type,
    required int conversationId,
    required String callId,
  }) async {
    if (conversationId <= 0 || callId.trim().isEmpty) return false;
    try {
      final deviceId = await tokenStore.ensureDeviceId();
      final token = await pushService.currentDeviceToken();
      await apiClient.sendCallControlEvent(
        type: type,
        conversationId: conversationId,
        callId: callId,
        deviceId: deviceId,
        token: token,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _sendCallEvent(String type, [Map<String, dynamic>? signal]) {
    if (callId.isEmpty || callConversationId == 0) return;
    final isControlEvent = type == 'call.invite' ||
        type == 'call.accept' ||
        type == 'call.reject' ||
        type == 'call.busy' ||
        type == 'call.cancel' ||
        type == 'call.end';
    if (isControlEvent) {
      // Keep call control on HTTP so the other device receives FCM even when
      // the realtime socket is reconnecting or the app is backgrounded.
      unawaited(_sendCallControlEvent(
        type: type,
        conversationId: callConversationId,
        callId: callId,
      ).then((_) {}));
      return;
    }
    realtimeService.sendCallEvent({
      'type': type,
      'eventId': const Uuid().v4(),
      'conversationId': callConversationId,
      'callId': callId,
      'sourceDeviceId': tokenStore.deviceId ?? '',
      if (signal != null) 'signal': signal,
    });
  }

  RTCSessionDescription _sessionDescription(Map<String, dynamic> signal) {
    return RTCSessionDescription(
        '${signal['sdp'] ?? ''}', '${signal['type'] ?? ''}');
  }

  RTCIceCandidate _iceCandidate(Map<String, dynamic> signal) {
    return RTCIceCandidate(
      '${signal['candidate'] ?? ''}',
      signal['sdpMid']?.toString(),
      signal['sdpMLineIndex'] is int
          ? signal['sdpMLineIndex'] as int
          : int.tryParse('${signal['sdpMLineIndex']}'),
    );
  }

  Future<void> _flushPendingIceCandidates() async {
    final pc = _peerConnection;
    if (pc == null || _pendingIceCandidates.isEmpty) return;
    final candidates = List<Map<String, dynamic>>.from(_pendingIceCandidates);
    _pendingIceCandidates.clear();
    for (final candidate in candidates) {
      try {
        await pc.addCandidate(_iceCandidate(candidate));
      } catch (_) {}
    }
  }

  void _activateCall() {
    if (callState == 'active') return;
    _callTimeoutTimer?.cancel();
    if (!_transitionCallState('active')) return;
    callStatus = 'Dang goi';
    _callStartedAt = DateTime.now();
    callDuration = 0;
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _callStartedAt;
      if (started == null) return;
      callDuration = DateTime.now().difference(started).inSeconds;
      notifyListeners();
    });
    unawaited(pushService.markCallConnected(callId));
    notifyListeners();
  }

  void _startCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (callState == 'outgoing' || callState == 'connecting') {
        _sendCallEvent('call.cancel');
      }
      _cleanupCall('Cuoc goi da het thoi gian cho');
    });
  }

  void _cleanupCall([String message = '']) {
    final previousCallId = callId;
    final previousState = callState;
    final previousConversationId = callConversationId;
    final previousDuration = callDuration;
    final shouldLogCall = _callStartedByMe && previousConversationId > 0;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
    _peerConnection?.close();
    _peerConnection = null;
    for (final track in _localCallStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localCallStream?.dispose();
    _localCallStream = null;
    _pendingIceCandidates.clear();
    _transitionCallState('idle');
    callStatus = message;
    callId = '';
    callConversationId = 0;
    callPeerName = '';
    callMuted = false;
    callSpeakerOn = false;
    callDuration = 0;
    _callStartedAt = null;
    _callStartedByMe = false;
    _callOfferStarted = false;
    if (message.trim().isNotEmpty) {
      callNotice = message.trim();
      callNoticeSequence += 1;
    }
    try {
      unawaited(Helper.setSpeakerphoneOn(false));
    } catch (_) {}
    unawaited(pushService.endIncomingCall(previousCallId));
    notifyListeners();
    if (shouldLogCall) {
      unawaited(_logCallToConversation(
        previousConversationId,
        previousState,
        previousDuration,
        message,
      ));
    }
  }

  Future<void> _logCallToConversation(
    int conversationId,
    String previousState,
    int duration,
    String message,
  ) async {
    final content = _callLogContent(previousState, duration, message);
    if (content.isEmpty || !isAuthenticated) return;
    try {
      final pending = _newPendingMessage(
        conversationId: conversationId,
        clientMessageId: const Uuid().v4(),
        type: 'call',
        content: content,
      );
      _upsertMessage(pending);
      if (await _submitPendingMessage(pending)) {
        await refreshChat(reloadSelected: false);
      }
    } catch (_) {}
  }

  String _callLogContent(String previousState, int duration, String message) {
    if (previousState == 'active' || duration > 0) {
      return jsonEncode({
        'kind': 'audio',
        'status': 'completed',
        'duration': duration,
      });
    }
    final normalized = message.toLowerCase();
    if (normalized.contains('het thoi gian')) {
      return jsonEncode({
        'kind': 'audio',
        'status': 'missed',
        'duration': 0,
      });
    }
    return '';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _realtimeStableTimer?.cancel();
    unawaited(realtimeService.disconnect());
    _resetMessagingSessionState();
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    unawaited(_nativeCallSubscription.cancel());
    unawaited(_remoteCallSubscription.cancel());
    unawaited(_connectivitySubscription.cancel());
    unawaited(pushService.dispose());
    super.dispose();
  }
}

bool _isLinkMessageContent(String value) {
  final content = value.trim();
  if (content.isEmpty || RegExp(r'\s').hasMatch(content)) return false;
  final hasProtocol =
      RegExp(r'^https?://', caseSensitive: false).hasMatch(content);
  final uri = Uri.tryParse(hasProtocol ? content : 'https://$content');
  return uri != null &&
      uri.host.contains('.') &&
      !uri.host.startsWith('.') &&
      !uri.host.endsWith('.');
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

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
  }) {
    _nativeCallSubscription = pushService.nativeCallActions.listen(
      (action) => unawaited(_handleNativeCallAction(action)),
    );
    _remoteCallSubscription = pushService.remoteCallEvents.listen(
      (event) => unawaited(_handleRemoteCallEvent(event)),
    );
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
  Timer? _callTimeoutTimer;
  Timer? _callDurationTimer;
  DateTime? _callStartedAt;
  bool _callStartedByMe = false;
  bool _callOfferStarted = false;
  NativeCallAction? _pendingNativeCallAction;
  late final StreamSubscription<NativeCallAction> _nativeCallSubscription;
  late final StreamSubscription<RemoteCallEvent> _remoteCallSubscription;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localCallStream;
  final List<Map<String, dynamic>> _pendingIceCandidates = [];

  bool get isAuthenticated => tokenStore.token?.isNotEmpty == true;

  Future<void> restoreSession() async {
    try {
      await tokenStore.load();
      languageCode = tokenStore.languageCode;
      if (!isAuthenticated) return;
      await _guard(() async {
        me = await apiClient.profile();
        await refreshChat();
        _connectRealtime();
        await _resumeNativeCallActions();
        unawaited(pushService.registerCurrentDevice());
      });
    } catch (_) {
      await tokenStore.clear();
      me = null;
      conversations = [];
      contacts = [];
      messages = [];
      unreadMessageCounts = {};
      selectedConversation = null;
      hasMoreMessages = false;
      loadingOlderMessages = false;
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
    try {
      await pushService.unregisterCurrentDevice();
    } catch (_) {
      // The session must still be cleared if the network is unavailable.
    }
    await tokenStore.clear();
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

  Future<void> refreshChat({bool reloadSelected = true}) async {
    contacts = await apiClient.contacts();
    contacts.sort(_compareContacts);
    conversations = await apiClient.conversations();
    conversations.sort(_sortConversations);
    notifyListeners();
    final selected = selectedConversation;
    if (reloadSelected && selected != null) {
      await selectConversation(selected);
    }
  }

  Future<void> selectConversation(ChatConversation conversation) async {
    selectedConversation = conversation;
    messageFocusId = 0;
    messageFocusConversationId = 0;
    loadingOlderMessages = false;
    final page = await apiClient.messages(conversation.id, limit: 50);
    messages = page.messages;
    hasMoreMessages = page.hasMore;
    messages.sort((a, b) => a.id.compareTo(b.id));
    if (unreadMessageCounts[conversation.id] != null) {
      unreadMessageCounts = Map<int, int>.from(unreadMessageCounts)
        ..remove(conversation.id);
    }
    notifyListeners();
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
      messages = [...olderMessages, ...messages]
        ..sort((a, b) => a.id.compareTo(b.id));
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

  int get totalUnreadMessages => unreadMessageCounts.values.fold(
        0,
        (total, count) => total + count,
      );

  Future<void> sendText(String content, {ChatMessage? replyTo}) async {
    final conversation = selectedConversation;
    final trimmed = content.trim();
    if (conversation == null || trimmed.isEmpty) return;
    final message = await apiClient.sendMessage(conversation.id,
        type: _isLinkMessageContent(trimmed) ? 'link' : 'text',
        content: trimmed,
        replyToMessageId: replyTo?.id ?? 0);
    _upsertMessage(message);
  }

  Future<void> sendFiles(List<File> files,
      {String type = 'file', ChatMessage? replyTo}) async {
    final conversation = selectedConversation;
    if (conversation == null || files.isEmpty) return;
    final attachments = await apiClient.uploadFiles(files);
    final message = await apiClient.sendMessage(conversation.id,
        type: type,
        attachments: attachments,
        replyToMessageId: replyTo?.id ?? 0);
    _upsertMessage(message);
  }

  Future<void> forwardMessage(
      ChatConversation target, ChatMessage message) async {
    if (message.type == 'poll' || message.type == 'system') return;
    final forwarded = await apiClient.sendMessage(
      target.id,
      type: message.type,
      content: message.content,
      forwardedFromMessageId: message.id,
      attachments: message.attachments,
    );
    if (selectedConversation?.id == target.id) {
      _upsertMessage(forwarded);
    }
    await refreshChat(reloadSelected: false);
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
    if (event.type.startsWith('call.')) {
      unawaited(_handleCallRealtimeEvent(event));
      return;
    }
    if (event.type == 'chat.message.created' ||
        event.type == 'chat.poll.updated') {
      final message = event.message;
      if (message != null) {
        _upsertMessage(message);
        if (event.type == 'chat.message.created' &&
            message.senderUserid != tokenStore.userid) {
          if (message.conversationId != selectedConversation?.id) {
            _incrementUnread(message.conversationId);
            unawaited(pushService.showChatMessage(
              message: message,
              conversationTitle: _notificationConversationTitle(message),
              unreadCount: unreadCountFor(message.conversationId),
            ));
          }
        }
      }
      unawaited(refreshChat(reloadSelected: false));
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

  void _incrementUnread(int conversationId) {
    unreadMessageCounts = Map<int, int>.from(unreadMessageCounts)
      ..update(conversationId, (count) => count + 1, ifAbsent: () => 1);
    notifyListeners();
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

  int _sortConversations(ChatConversation a, ChatConversation b) {
    final left =
        a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right =
        b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
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
    callState = 'outgoing';
    callStatus = 'Dang goi...';
    callMuted = false;
    callSpeakerOn = false;
    _callStartedByMe = true;
    notifyListeners();

    try {
      await _prepareLocalCallMedia();
      _sendCallEvent('call.invite');
      _startCallTimeout();
    } catch (_) {
      _cleanupCall('Khong truy cap duoc micro');
    }
  }

  Future<void> acceptIncomingCall() async {
    if (callState != 'incoming' || callId.isEmpty) return;
    callState = 'connecting';
    callStatus = 'Dang ket noi...';
    notifyListeners();
    try {
      await _prepareLocalCallMedia();
      await _ensurePeerConnection();
      _sendCallEvent('call.accept');
      _startCallTimeout();
    } catch (_) {
      _sendCallEvent('call.reject');
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
        callState = 'incoming';
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
        ));
        unawaited(pushService.endIncomingCall(action.callId));
      } else if (action.type == NativeCallActionType.ended) {
        unawaited(_sendCallControlEvent(
          type: 'call.end',
          conversationId: action.conversationId,
          callId: action.callId,
        ));
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
    if (sender == tokenStore.userid) return;

    if (event.type == 'call.invite') {
      if (event.callId == callId &&
          event.conversationId == callConversationId) {
        return;
      }
      if (callState != 'idle') {
        _sendCallControlEvent(
          type: 'call.busy',
          conversationId: event.conversationId,
          callId: event.callId,
        );
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
      callState = 'incoming';
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
          callState = 'connecting';
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
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
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
    callState = 'connecting';
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

  Future<void> _sendCallControlEvent({
    required String type,
    required int conversationId,
    required String callId,
  }) async {
    if (conversationId <= 0 || callId.trim().isEmpty) return;
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
    } catch (_) {}
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
      ));
      return;
    }
    realtimeService.sendCallEvent({
      'type': type,
      'conversationId': callConversationId,
      'callId': callId,
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
    callState = 'active';
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
    callState = 'idle';
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
    if (content.isEmpty) return;
    try {
      final callMessage = await apiClient.sendMessage(
        conversationId,
        type: 'call',
        content: content,
      );
      _upsertMessage(callMessage);
      await refreshChat(reloadSelected: false);
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
    _reconnectTimer?.cancel();
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    unawaited(_nativeCallSubscription.cancel());
    unawaited(_remoteCallSubscription.cancel());
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  bool hasMoreMessages = false;
  bool loadingOlderMessages = false;
  String callState = 'idle';
  String callStatus = '';
  String callId = '';
  int callConversationId = 0;
  String callPeerName = '';
  bool callMuted = false;
  int callDuration = 0;
  String languageCode = 'vi';
  Timer? _reconnectTimer;
  Timer? _callTimeoutTimer;
  Timer? _callDurationTimer;
  DateTime? _callStartedAt;
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
        unawaited(pushService.registerCurrentDevice());
      });
    } catch (_) {
      await tokenStore.clear();
      me = null;
      conversations = [];
      contacts = [];
      messages = [];
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
    await tokenStore.clear();
    me = null;
    conversations = [];
    contacts = [];
    messages = [];
    selectedConversation = null;
    hasMoreMessages = false;
    loadingOlderMessages = false;
    notifyListeners();
  }

  Future<void> refreshChat({bool reloadSelected = true}) async {
    contacts = await apiClient.contacts();
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
    loadingOlderMessages = false;
    final page = await apiClient.messages(conversation.id, limit: 50);
    messages = page.messages;
    hasMoreMessages = page.hasMore;
    messages.sort((a, b) => a.id.compareTo(b.id));
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

  void clearSelectedConversation() {
    selectedConversation = null;
    messages = [];
    hasMoreMessages = false;
    loadingOlderMessages = false;
    notifyListeners();
  }

  Future<void> sendText(String content, {ChatMessage? replyTo}) async {
    final conversation = selectedConversation;
    final trimmed = content.trim();
    if (conversation == null || trimmed.isEmpty) return;
    final message = await apiClient.sendMessage(conversation.id,
        type: 'text', content: trimmed, replyToMessageId: replyTo?.id ?? 0);
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
      if (message != null) _upsertMessage(message);
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
    callId =
        '${conversation.id}-${tokenStore.userid ?? 'user'}-${DateTime.now().millisecondsSinceEpoch}';
    callConversationId = conversation.id;
    callPeerName = conversation.titleFor(tokenStore.userid ?? '');
    callState = 'outgoing';
    callStatus = 'Dang goi...';
    callMuted = false;
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
    _cleanupCall();
  }

  void endOrCancelCall() {
    if (callId.isEmpty) return;
    _sendCallEvent(callState == 'active' ? 'call.end' : 'call.cancel');
    _cleanupCall();
  }

  void toggleCallMute() {
    callMuted = !callMuted;
    for (final track
        in _localCallStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !callMuted;
    }
    notifyListeners();
  }

  Future<void> _handleCallRealtimeEvent(RealtimeEvent event) async {
    final sender =
        event.fromUserid.isNotEmpty ? event.fromUserid : event.userid;
    if (sender == tokenStore.userid) return;

    if (event.type == 'call.invite') {
      if (callState != 'idle') {
        realtimeService.sendCallEvent({
          'type': 'call.busy',
          'conversationId': event.conversationId,
          'callId': event.callId,
        });
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
      _startCallTimeout();
      notifyListeners();
      return;
    }

    if (event.callId != callId || event.conversationId != callConversationId) {
      return;
    }

    switch (event.type) {
      case 'call.accept':
        if (callState != 'outgoing') return;
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

  void _sendCallEvent(String type, [Map<String, dynamic>? signal]) {
    if (callId.isEmpty || callConversationId == 0) return;
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
    callDuration = 0;
    _callStartedAt = null;
    notifyListeners();
  }
}

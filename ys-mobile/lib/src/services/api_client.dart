import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../models/models.dart';
import 'token_store.dart';

class ChatMessagePage {
  const ChatMessagePage({
    required this.messages,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
}

class ChatCatchUpPage {
  const ChatCatchUpPage({
    required this.messages,
    required this.hasMore,
    this.nextAfterMessageId = 0,
    this.nextAfterSequence = 0,
    this.unreadCount,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final int nextAfterMessageId;
  final int nextAfterSequence;
  final int? unreadCount;
}

class ChatMessageSearchPage {
  const ChatMessageSearchPage({
    required this.messages,
    required this.hasMore,
    this.nextBeforeId = 0,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final int nextBeforeId;
}

class ApiClient {
  ApiClient(String baseUrl, this._tokenStore)
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _dio =
            Dio(BaseOptions(baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''))) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _tokenStore.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final String baseUrl;
  final TokenStore _tokenStore;
  final Dio _dio;

  Future<Map<String, dynamic>> login(String userid, String password) async {
    final response = await _dio.post('/auth/login', data: {
      'userid': userid,
      'password': password,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> register({
    required String userid,
    required String fullname,
    required String password,
    required String idCardSuffix,
  }) async {
    await _dio.post('/auth/register', data: {
      'userid': userid,
      'fullname': fullname,
      'password': password,
      'idCardSuffix': idCardSuffix,
    });
  }

  Future<void> forgotPassword({
    required String userid,
    required String fullname,
    required String birthday,
    required String idCard,
  }) async {
    await _dio.post('/auth/forgot-password', data: {
      'userid': userid,
      'fullname': fullname,
      'birthday': birthday,
      'idCard': idCard,
    });
  }

  Future<ChatUser> profile() async {
    final response = await _dio.get('/profile');
    return ChatUser.fromJson(
        Map<String, dynamic>.from(response.data['user'] as Map));
  }

  Future<ChatUser> updateProfile(String fullname) async {
    final response = await _dio.put('/profile', data: {'fullname': fullname});
    return ChatUser.fromJson(
        Map<String, dynamic>.from(response.data['user'] as Map));
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await _dio.put('/profile/password', data: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<ChatUser> uploadAvatar(File file) async {
    final formData = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(file.path,
          filename: file.uri.pathSegments.last),
    });
    final response = await _dio.post('/profile/avatar', data: formData);
    return ChatUser.fromJson(
        Map<String, dynamic>.from(response.data['user'] as Map));
  }

  Future<List<ChatConversation>> conversations() async {
    final response = await _dio.get('/chat/conversations');
    return _maps(response.data['conversations'])
        .map(ChatConversation.fromJson)
        .toList();
  }

  Future<ChatConversation> updateConversationMemberNickname(
    int conversationId,
    String userid,
    String nickname,
  ) async {
    final response = await _dio.put(
      '/chat/conversations/$conversationId/members/${Uri.encodeComponent(userid)}/nickname',
      data: {'nickname': nickname},
    );
    return ChatConversation.fromJson(
      Map<String, dynamic>.from(response.data['conversation'] as Map),
    );
  }

  Future<ChatMessagePage> messages(int conversationId,
      {int limit = 50, int beforeId = 0}) async {
    final response = await _dio.get(
      '/chat/conversations/$conversationId/messages',
      queryParameters: {'limit': limit, if (beforeId > 0) 'beforeId': beforeId},
    );
    return ChatMessagePage(
      messages:
          _maps(response.data['messages']).map(ChatMessage.fromJson).toList(),
      hasMore: response.data['hasMore'] == true,
    );
  }

  Future<ChatMessage> sendMessage(
    int conversationId, {
    required String clientMessageId,
    required String type,
    String content = '',
    int replyToMessageId = 0,
    int forwardedFromMessageId = 0,
    List<ChatAttachment> attachments = const [],
  }) async {
    final response =
        await _dio.post('/chat/conversations/$conversationId/messages', data: {
      'clientMessageId': clientMessageId,
      'type': type,
      'content': content,
      'replyToMessageId': replyToMessageId,
      'forwardedFromMessageId': forwardedFromMessageId,
      'attachments':
          attachments.map((attachment) => attachment.toJson()).toList(),
    });
    return _messageFromResponse(response.data);
  }

  Future<ChatCatchUpPage> catchUpMessages(
    int conversationId, {
    int afterMessageId = 0,
    int afterSequence = 0,
    int limit = 100,
  }) async {
    final response = await _dio.get(
      '/chat/conversations/$conversationId/messages/catch-up',
      queryParameters: {
        'limit': limit,
        if (afterSequence > 0) 'afterSequence': afterSequence,
        if (afterSequence <= 0 && afterMessageId > 0)
          'afterMessageId': afterMessageId,
      },
    );
    final body = _body(response.data);
    final messages = _maps(body['messages']).map(ChatMessage.fromJson).toList();
    final last = messages.isEmpty ? null : messages.last;
    final rawCursor = body['nextCursor'];
    final nextCursor = rawCursor is Map
        ? Map<String, dynamic>.from(rawCursor)
        : const <String, dynamic>{};
    return ChatCatchUpPage(
      messages: messages,
      hasMore: body['hasMore'] == true,
      nextAfterMessageId:
          _asInt(nextCursor['afterMessageId'] ?? body['nextAfterMessageId']) > 0
              ? _asInt(
                  nextCursor['afterMessageId'] ?? body['nextAfterMessageId'])
              : last?.id ?? afterMessageId,
      nextAfterSequence:
          _asInt(nextCursor['afterSequence'] ?? body['nextAfterSequence']) > 0
              ? _asInt(nextCursor['afterSequence'] ?? body['nextAfterSequence'])
              : last?.serverSequence ?? afterSequence,
      unreadCount:
          body.containsKey('unreadCount') ? _asInt(body['unreadCount']) : null,
    );
  }

  Future<String> realtimeTicket() async {
    final response = await _dio.post('/chat/realtime/ticket');
    final body = _body(response.data);
    return '${body['ticket'] ?? ''}'.trim();
  }

  Future<List<Map<String, dynamic>>> iceServers() async {
    final response = await _dio.get('/chat/calls/ice-config');
    final body = _body(response.data);
    return _maps(body['iceServers']);
  }

  Future<Map<String, dynamic>> callState(String callId) async {
    final response = await _dio.get(
      '/chat/calls/${Uri.encodeComponent(callId)}',
    );
    final body = _body(response.data);
    final call = body['call'];
    return call is Map ? Map<String, dynamic>.from(call) : <String, dynamic>{};
  }

  Future<ConversationReadState> markConversationRead(
    int conversationId,
    int messageId,
  ) async {
    final response = await _dio.post(
      '/chat/conversations/$conversationId/read',
      data: {'lastReadMessageId': messageId},
    );
    final body = _body(response.data);
    final raw = body['readState'] ?? body['receipt'] ?? body;
    final json =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    json.putIfAbsent('conversationId', () => conversationId);
    json.putIfAbsent('lastReadMessageId', () => messageId);
    return ConversationReadState.fromJson(json);
  }

  Future<void> markMessageDelivered(int conversationId, int messageId) async {
    await _dio.post(
      '/chat/conversations/$conversationId/delivered',
      data: {'messageId': messageId},
    );
  }

  Future<void> setTyping(int conversationId, bool isTyping) async {
    await _dio.post(
      '/chat/conversations/$conversationId/typing',
      data: {'isTyping': isTyping},
    );
  }

  Future<ChatMessage> editMessage(
    int messageId, {
    required String content,
    required int version,
  }) async {
    final response = await _dio.patch('/chat/messages/$messageId', data: {
      'content': content,
      'version': version,
    });
    return _messageFromResponse(response.data);
  }

  Future<List<ChatMessageEditHistoryEntry>> getMessageEditHistory(
      int messageId) async {
    final response = await _dio.get('/chat/messages/$messageId/edit-history');
    final body = _body(response.data);
    final raw = body['history'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => ChatMessageEditHistoryEntry.fromJson(
            Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<ChatMessage> recallMessage(int messageId,
      {required int version}) async {
    final response = await _dio.post('/chat/messages/$messageId/recall', data: {
      'version': version,
    });
    return _messageFromResponse(response.data);
  }

  Future<void> deleteMessageForMe(int messageId) async {
    await _dio.delete('/chat/messages/$messageId');
  }

  Future<List<ChatReaction>> addReaction(int messageId, String emoji) async {
    final response = await _dio.put(
      '/chat/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}',
    );
    return _reactionListFromResponse(response.data);
  }

  Future<List<ChatReaction>> removeReaction(int messageId, String emoji) async {
    final response = await _dio.delete(
      '/chat/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}',
    );
    return _reactionListFromResponse(response.data);
  }

  Future<ConversationSettings> updateConversationSettings(
    int conversationId, {
    Object? muteUntil = _absent,
    Object? pinnedAt = _absent,
    Object? archivedAt = _absent,
  }) async {
    final data = <String, dynamic>{};
    if (!identical(muteUntil, _absent)) {
      data['muteUntil'] = (muteUntil as DateTime?)?.toUtc().toIso8601String();
    }
    if (!identical(pinnedAt, _absent)) {
      data['pinnedAt'] = (pinnedAt as DateTime?)?.toUtc().toIso8601String();
    }
    if (!identical(archivedAt, _absent)) {
      data['archivedAt'] = (archivedAt as DateTime?)?.toUtc().toIso8601String();
    }
    final response = await _dio.patch(
      '/chat/conversations/$conversationId/user-settings',
      data: data,
    );
    final body = _body(response.data);
    final raw = body['settings'] ?? body['userSettings'] ?? body;
    return ConversationSettings.fromJson(
      raw is Map ? Map<String, dynamic>.from(raw) : const {},
    );
  }

  Future<ChatMessage> createPoll(
    int conversationId, {
    required String question,
    required List<String> options,
    required bool allowCustomOptions,
    required bool allowMultiple,
    required bool showVoters,
  }) async {
    final response =
        await _dio.post('/chat/conversations/$conversationId/polls', data: {
      'question': question,
      'options': options,
      'allowCustomOptions': allowCustomOptions,
      'allowMultiple': allowMultiple,
      'showVoters': showVoters,
    });
    return ChatMessage.fromJson(
        Map<String, dynamic>.from(response.data['message'] as Map));
  }

  Future<ChatMessage> votePoll(
    int messageId, {
    required List<int> optionIds,
    String customOption = '',
  }) async {
    final response =
        await _dio.post('/chat/messages/$messageId/poll/votes', data: {
      'optionIds': optionIds,
      'customOption': customOption,
    });
    return ChatMessage.fromJson(
        Map<String, dynamic>.from(response.data['message'] as Map));
  }

  Future<ChatMessage> closePoll(int messageId) async {
    final response = await _dio.post('/chat/messages/$messageId/poll/close');
    return ChatMessage.fromJson(
        Map<String, dynamic>.from(response.data['message'] as Map));
  }

  Future<List<ChatAttachment>> uploadFiles(List<File> files) async {
    final formData = FormData();
    for (final file in files) {
      final filename = file.uri.pathSegments.last;
      formData.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(
            file.path,
            filename: filename,
            contentType: MediaType.parse(
                lookupMimeType(file.path) ?? 'application/octet-stream'),
          ),
        ),
      );
      formData.fields.add(MapEntry('relativePaths', filename));
    }
    final response = await _dio.post('/chat/uploads', data: formData);
    return _maps(response.data['attachments'])
        .map(ChatAttachment.fromJson)
        .toList();
  }

  Future<List<ChatUser>> contacts() async {
    final response = await _dio.get('/chat/contacts');
    return _maps(response.data['contacts']).map(ChatUser.fromJson).toList();
  }

  Future<ChatUser> addContact(String userid) async {
    final response = await _dio.post('/chat/contacts', data: {
      'userid': userid,
    });
    return ChatUser.fromJson(
        Map<String, dynamic>.from(response.data['contact'] as Map));
  }

  Future<ChatUser> updateContactNickname(String userid, String nickname) async {
    final response = await _dio.put(
      '/chat/contacts/${Uri.encodeComponent(userid)}/nickname',
      data: {'nickname': nickname},
    );
    return ChatUser.fromJson(
      Map<String, dynamic>.from(response.data['contact'] as Map),
    );
  }

  Future<List<ChatUser>> searchUsers(String keyword) async {
    final response =
        await _dio.get('/chat/users', queryParameters: {'keyword': keyword});
    return _maps(response.data['users']).map(ChatUser.fromJson).toList();
  }

  Future<ChatSearchResults> searchChat(
    String keyword,
    String scope, {
    int conversationId = 0,
    String senderUserid = '',
    DateTime? dateFrom,
    DateTime? dateTo,
    String attachmentType = '',
  }) async {
    final response = await _dio.get(
      '/chat/search',
      queryParameters: {
        'keyword': keyword,
        'scope': scope,
        if (conversationId > 0) 'conversationId': conversationId,
        if (senderUserid.isNotEmpty) 'senderUserid': senderUserid,
        if (dateFrom != null) 'dateFrom': dateFrom.toUtc().toIso8601String(),
        if (dateTo != null) 'dateTo': dateTo.toUtc().toIso8601String(),
        if (attachmentType.isNotEmpty) 'attachmentType': attachmentType,
      },
    );
    return ChatSearchResults.fromJson(
      Map<String, dynamic>.from(response.data['results'] as Map),
    );
  }

  Future<ChatMessageSearchPage> searchConversationMessages(
    int conversationId, {
    String keyword = '',
    String senderUserid = '',
    DateTime? from,
    DateTime? to,
    String attachmentType = '',
    int beforeId = 0,
    int limit = 50,
  }) async {
    final response = await _dio.get(
      '/chat/conversations/$conversationId/messages/search',
      queryParameters: {
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        if (senderUserid.trim().isNotEmpty) 'senderUserid': senderUserid.trim(),
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        if (attachmentType.trim().isNotEmpty)
          'attachmentType': attachmentType.trim(),
        if (beforeId > 0) 'beforeId': beforeId,
        'limit': limit,
      },
    );
    final body = _body(response.data);
    return ChatMessageSearchPage(
      messages: _maps(body['messages']).map(ChatMessage.fromJson).toList(),
      hasMore: body['hasMore'] == true,
      nextBeforeId: _asInt(body['nextBeforeId']),
    );
  }

  Future<ChatConversation> createDirectConversation(String userid) async {
    final response =
        await _dio.post('/chat/conversations/direct', data: {'userid': userid});
    return ChatConversation.fromJson(
        Map<String, dynamic>.from(response.data['conversation'] as Map));
  }

  Future<ChatConversation> createGroupConversation(
    String name,
    List<String> memberUserids,
  ) async {
    final response = await _dio.post('/chat/conversations/group', data: {
      'name': name,
      'memberUserids': memberUserids,
    });
    return ChatConversation.fromJson(
      Map<String, dynamic>.from(response.data['conversation'] as Map),
    );
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    required String deviceId,
  }) async {
    await _dio.post('/chat/devices', data: {
      'token': token,
      'platform': platform,
      'deviceId': deviceId,
    });
  }

  Future<void> unregisterDeviceToken({
    required String deviceId,
    String token = '',
  }) async {
    await _dio.delete('/chat/devices', data: {
      'token': token,
      'deviceId': deviceId,
    });
  }

  Future<void> sendCallControlEvent({
    required String type,
    required int conversationId,
    required String callId,
    required String deviceId,
    String token = '',
  }) async {
    await _dio.post('/chat/calls/events', data: {
      'type': type,
      'conversationId': conversationId,
      'callId': callId,
      'deviceId': deviceId,
      if (token.isNotEmpty) 'token': token,
    });
  }

  String absoluteUrl(String maybeRelativeUrl) {
    if (maybeRelativeUrl.startsWith('http://') ||
        maybeRelativeUrl.startsWith('https://')) {
      return maybeRelativeUrl;
    }
    final apiUri = Uri.parse(baseUrl);
    return apiUri.replace(path: maybeRelativeUrl).toString();
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _body(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  ChatMessage _messageFromResponse(Object? value) {
    final body = _body(value);
    final raw = body['message'] ?? body;
    if (raw is! Map) {
      throw const FormatException('Missing message in API response');
    }
    final message = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
    return body['idempotentReplay'] == true
        ? message.copyWith(idempotentReplay: true)
        : message;
  }

  List<ChatReaction> _reactionListFromResponse(Object? value) {
    final body = _body(value);
    return _maps(body['reactions']).map(ChatReaction.fromJson).toList();
  }
}

const _absent = Object();

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

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
    required String type,
    String content = '',
    int replyToMessageId = 0,
    int forwardedFromMessageId = 0,
    List<ChatAttachment> attachments = const [],
  }) async {
    final response =
        await _dio.post('/chat/conversations/$conversationId/messages', data: {
      'type': type,
      'content': content,
      'replyToMessageId': replyToMessageId,
      'forwardedFromMessageId': forwardedFromMessageId,
      'attachments':
          attachments.map((attachment) => attachment.toJson()).toList(),
    });
    return ChatMessage.fromJson(
        Map<String, dynamic>.from(response.data['message'] as Map));
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

  Future<List<ChatUser>> searchUsers(String keyword) async {
    final response =
        await _dio.get('/chat/users', queryParameters: {'keyword': keyword});
    return _maps(response.data['users']).map(ChatUser.fromJson).toList();
  }

  Future<ChatConversation> createDirectConversation(String userid) async {
    final response =
        await _dio.post('/chat/conversations/direct', data: {'userid': userid});
    return ChatConversation.fromJson(
        Map<String, dynamic>.from(response.data['conversation'] as Map));
  }

  Future<void> registerDeviceToken(String token, String platform) async {
    await _dio
        .post('/chat/devices', data: {'token': token, 'platform': platform});
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
}

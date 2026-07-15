import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class TokenStore {
  static const _tokenKey = 'user_token';
  static const _useridKey = 'userid';
  static const _fullnameKey = 'fullname';
  static const _accountIdKey = 'account_id';
  static const _languageKey = 'language_code';
  static const _deviceIdKey = 'device_id';
  static const _chatRuntimeKeyPrefix = 'chat_runtime_v1_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? token;
  String? userid;
  String? fullname;
  String? accountId;
  String? deviceId;
  String languageCode = 'vi';

  Future<void> load() async {
    try {
      token = await _storage.read(key: _tokenKey);
      userid = await _storage.read(key: _useridKey);
      fullname = await _storage.read(key: _fullnameKey);
      accountId = await _storage.read(key: _accountIdKey);
      deviceId = await _storage.read(key: _deviceIdKey);
      languageCode = await _storage.read(key: _languageKey) ?? 'vi';
      await ensureDeviceId();
    } catch (_) {
      await clearSession();
    }
  }

  Future<void> saveSession({
    required String token,
    required String userid,
    required String fullname,
    required Object? accountId,
  }) async {
    this.token = token;
    this.userid = userid;
    this.fullname = fullname;
    this.accountId = accountId?.toString();
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _useridKey, value: userid);
    await _storage.write(key: _fullnameKey, value: fullname);
    await _storage.write(key: _accountIdKey, value: this.accountId);
  }

  Future<void> clearSession({bool clearChatRuntime = false}) async {
    final previousUserid = userid?.trim() ?? '';
    token = null;
    userid = null;
    fullname = null;
    accountId = null;
    final keys = <String>[
      _tokenKey,
      _useridKey,
      _fullnameKey,
      _accountIdKey,
      if (clearChatRuntime && previousUserid.isNotEmpty)
        _chatRuntimeKey(previousUserid),
    ];
    for (final key in keys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // An unreadable restored Android keystore must not prevent attempts to
        // clear the remaining session and per-user runtime values.
      }
    }
  }

  Future<String> ensureDeviceId() async {
    final existing = deviceId?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    final generated = const Uuid().v4();
    deviceId = generated;
    try {
      await _storage.write(key: _deviceIdKey, value: generated);
    } catch (_) {}
    return generated;
  }

  Future<void> saveLanguage(String code) async {
    languageCode = code;
    await _storage.write(key: _languageKey, value: code);
  }

  Future<String?> readChatRuntime(String userid) async {
    final normalized = userid.trim();
    if (normalized.isEmpty) return null;
    return _storage.read(key: _chatRuntimeKey(normalized));
  }

  Future<void> writeChatRuntime(String userid, String value) async {
    final normalized = userid.trim();
    if (normalized.isEmpty) return;
    await _storage.write(key: _chatRuntimeKey(normalized), value: value);
  }

  Future<void> clearChatRuntime(String userid) async {
    final normalized = userid.trim();
    if (normalized.isEmpty) return;
    await _storage.delete(key: _chatRuntimeKey(normalized));
  }

  String _chatRuntimeKey(String userid) =>
      '$_chatRuntimeKeyPrefix${userid.trim().toLowerCase()}';
}

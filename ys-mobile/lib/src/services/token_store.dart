import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static const _tokenKey = 'user_token';
  static const _useridKey = 'userid';
  static const _fullnameKey = 'fullname';
  static const _accountIdKey = 'account_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? token;
  String? userid;
  String? fullname;
  String? accountId;

  Future<void> load() async {
    token = await _storage.read(key: _tokenKey);
    userid = await _storage.read(key: _useridKey);
    fullname = await _storage.read(key: _fullnameKey);
    accountId = await _storage.read(key: _accountIdKey);
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

  Future<void> clear() async {
    token = null;
    userid = null;
    fullname = null;
    accountId = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _useridKey);
    await _storage.delete(key: _fullnameKey);
    await _storage.delete(key: _accountIdKey);
  }
}

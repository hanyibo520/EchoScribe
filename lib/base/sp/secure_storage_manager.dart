import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储管理器
///
/// 使用 flutter_secure_storage 存储敏感数据：
/// - iOS: 存储在 Keychain
/// - Android: 存储在 EncryptedSharedPreferences
///
/// 主要用于存储 Token、用户敏感信息等
class SecureStorageManager {
  // 单例模式
  static final SecureStorageManager _instance =
      SecureStorageManager._internal();
  factory SecureStorageManager() => _instance;
  SecureStorageManager._internal();

  // FlutterSecureStorage 实例
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ==================== 存储键定义 ====================

  static const String _keyToken = 'current_token';
  static const String _keyUid = 'current_uid';
  static const String _keyLoginTime = 'login_time';

  // ==================== Token 管理 ====================

  /// 保存 Token
  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  /// 获取 Token
  Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  /// 清除 Token
  Future<void> clearToken() async {
    await _storage.delete(key: _keyToken);
  }

  /// 判断 Token 是否存在
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ==================== 用户 ID 管理 ====================

  /// 保存用户 ID
  Future<void> saveUid(String uid) async {
    await _storage.write(key: _keyUid, value: uid);
  }

  /// 获取用户 ID
  Future<String?> getUid() async {
    return await _storage.read(key: _keyUid);
  }

  /// 清除用户 ID
  Future<void> clearUid() async {
    await _storage.delete(key: _keyUid);
  }

  // ==================== 登录时间管理 ====================

  /// 保存登录时间（毫秒时间戳）
  Future<void> saveLoginTime(DateTime dateTime) async {
    await _storage.write(
      key: _keyLoginTime,
      value: dateTime.millisecondsSinceEpoch.toString(),
    );
  }

  /// 获取登录时间
  Future<DateTime?> getLoginTime() async {
    final timeStr = await _storage.read(key: _keyLoginTime);
    if (timeStr == null) return null;
    try {
      final timestamp = int.parse(timeStr);
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// 清除登录时间
  Future<void> clearLoginTime() async {
    await _storage.delete(key: _keyLoginTime);
  }

  /// 检查 Token 是否过期（15 天）
  Future<bool> isTokenExpired() async {
    final loginTime = await getLoginTime();
    if (loginTime == null) return true;

    final now = DateTime.now();
    final difference = now.difference(loginTime);

    // Token 有效期：15 天
    return difference.inDays >= 15;
  }

  // ==================== 清除所有数据 ====================

  /// 清除所有安全存储的数据
  Future<void> clearAll() async {
    await clearToken();
    await clearUid();
    await clearLoginTime();
  }

  // ==================== 自定义存储 ====================

  /// 通用写入方法
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// 通用读取方法
  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  /// 通用删除方法
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// 获取所有存储的键值对
  Future<Map<String, String>> readAll() async {
    return await _storage.readAll();
  }

  /// 删除所有数据（危险操作）
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 管理器
///
/// 用于存储非敏感的用户数据和应用配置
/// - 用户信息（非敏感部分）
/// - 设备绑定信息
/// - 应用设置选项
class SharedPreferencesManager {
  // 单例模式
  static final SharedPreferencesManager _instance =
      SharedPreferencesManager._internal();
  factory SharedPreferencesManager() => _instance;
  SharedPreferencesManager._internal();

  SharedPreferences? _prefs;

  /// 初始化 SharedPreferences
  /// 建议在应用启动时调用
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 获取 SharedPreferences 实例
  Future<SharedPreferences> get prefs async {
    if (_prefs == null) {
      await init();
    }
    return _prefs!;
  }

  // ==================== 存储键定义 ====================

  static const String _keyUserName = 'current_user_name';
  static const String _keyPhone = 'current_phone';
  static const String _keyIsActive = 'is_active';
  static const String _keyBindList = 'Bind_List';
  static const String _keyAutoSyncEnabled = 'AutoSync_Enabled';

  // ==================== 用户信息管理 ====================

  /// 保存用户名
  Future<bool> saveUserName(String userName) async {
    final sp = await prefs;
    return sp.setString(_keyUserName, userName);
  }

  /// 获取用户名
  Future<String?> getUserName() async {
    final sp = await prefs;
    return sp.getString(_keyUserName);
  }

  /// 保存手机号
  Future<bool> savePhone(String phone) async {
    final sp = await prefs;
    return sp.setString(_keyPhone, phone);
  }

  /// 获取手机号
  Future<String?> getPhone() async {
    final sp = await prefs;
    return sp.getString(_keyPhone);
  }

  /// 保存激活状态
  Future<bool> saveIsActive(bool isActive) async {
    final sp = await prefs;
    return sp.setBool(_keyIsActive, isActive);
  }

  /// 获取激活状态
  Future<bool> getIsActive() async {
    final sp = await prefs;
    return sp.getBool(_keyIsActive) ?? true;
  }

  /// 保存完整的用户信息（JSON 格式）
  Future<bool> saveUserInfo(Map<String, dynamic> userInfo) async {
    await saveUserName(userInfo['userName'] as String? ?? '');
    await savePhone(userInfo['phone'] as String? ?? '');
    await saveIsActive(userInfo['isActive'] as bool? ?? true);
    return true;
  }

  /// 获取完整的用户信息
  Future<Map<String, dynamic>?> getUserInfo() async {
    final userName = await getUserName();
    final phone = await getPhone();
    final isActive = await getIsActive();

    if (userName == null || phone == null) {
      return null;
    }

    return {
      'userName': userName,
      'phone': phone,
      'isActive': isActive,
    };
  }

  /// 清除用户信息
  Future<void> clearUserInfo() async {
    final sp = await prefs;
    await sp.remove(_keyUserName);
    await sp.remove(_keyPhone);
    await sp.remove(_keyIsActive);
  }

  // ==================== 设备绑定信息管理 ====================

  /// 保存设备绑定信息（JSON 字符串）
  Future<bool> saveBindInfo(Map<String, dynamic> bindInfo) async {
    final sp = await prefs;
    final jsonString = jsonEncode(bindInfo);
    return sp.setString(_keyBindList, jsonString);
  }

  /// 获取设备绑定信息
  Future<Map<String, dynamic>?> getBindInfo() async {
    final sp = await prefs;
    final jsonString = sp.getString(_keyBindList);
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 清除设备绑定信息
  Future<bool> clearBindInfo() async {
    final sp = await prefs;
    return sp.remove(_keyBindList);
  }

  /// 判断是否有绑定设备
  Future<bool> hasBindInfo() async {
    final bindInfo = await getBindInfo();
    return bindInfo != null;
  }

  // ==================== 应用设置管理 ====================

  /// 保存自动入库开关状态
  Future<bool> saveAutoSyncEnabled(bool enabled) async {
    final sp = await prefs;
    return sp.setBool(_keyAutoSyncEnabled, enabled);
  }

  /// 获取自动入库开关状态
  Future<bool> getAutoSyncEnabled() async {
    final sp = await prefs;
    return sp.getBool(_keyAutoSyncEnabled) ?? true; // 默认开启
  }

  // ==================== 通用存储方法 ====================

  /// 保存字符串
  Future<bool> setString(String key, String value) async {
    final sp = await prefs;
    return sp.setString(key, value);
  }

  /// 获取字符串
  Future<String?> getString(String key) async {
    final sp = await prefs;
    return sp.getString(key);
  }

  /// 保存整数
  Future<bool> setInt(String key, int value) async {
    final sp = await prefs;
    return sp.setInt(key, value);
  }

  /// 获取整数
  Future<int?> getInt(String key) async {
    final sp = await prefs;
    return sp.getInt(key);
  }

  /// 保存布尔值
  Future<bool> setBool(String key, bool value) async {
    final sp = await prefs;
    return sp.setBool(key, value);
  }

  /// 获取布尔值
  Future<bool?> getBool(String key) async {
    final sp = await prefs;
    return sp.getBool(key);
  }

  /// 保存双精度浮点数
  Future<bool> setDouble(String key, double value) async {
    final sp = await prefs;
    return sp.setDouble(key, value);
  }

  /// 获取双精度浮点数
  Future<double?> getDouble(String key) async {
    final sp = await prefs;
    return sp.getDouble(key);
  }

  /// 保存字符串列表
  Future<bool> setStringList(String key, List<String> value) async {
    final sp = await prefs;
    return sp.setStringList(key, value);
  }

  /// 获取字符串列表
  Future<List<String>?> getStringList(String key) async {
    final sp = await prefs;
    return sp.getStringList(key);
  }

  /// 删除指定键
  Future<bool> remove(String key) async {
    final sp = await prefs;
    return sp.remove(key);
  }

  /// 清除所有数据
  Future<bool> clear() async {
    final sp = await prefs;
    return sp.clear();
  }

  /// 判断键是否存在
  Future<bool> containsKey(String key) async {
    final sp = await prefs;
    return sp.containsKey(key);
  }

  /// 获取所有键
  Future<Set<String>> getKeys() async {
    final sp = await prefs;
    return sp.getKeys();
  }
}

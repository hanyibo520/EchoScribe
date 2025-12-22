import '../../base/net/api_client.dart';
import '../../base/net/api_exception.dart';
import '../../base/sp/secure_storage_manager.dart';
import '../../base/sp/shared_preferences_manager.dart';
import '../../config/api_config.dart';
import '../model/user_info.dart';

/// 登录服务
///
/// 负责所有用户认证相关的网络请求
class LoginService {
  final ApiClient _client = ApiClient();
  final SecureStorageManager _secureStorage = SecureStorageManager();
  final SharedPreferencesManager _sharedPreferences =
      SharedPreferencesManager();

  // ==================== 获取验证码 ====================

  /// 获取手机验证码
  ///
  /// [phone] 手机号（11 位）
  ///
  /// 返回 true 表示验证码发送成功
  /// 抛出 [ApiException] 当请求失败时
  ///
  /// 示例：
  /// ```dart
  /// try {
  ///   await loginService.getVerificationCode('13800138000');
  ///   print('验证码已发送');
  /// } on ApiException catch (e) {
  ///   print('发送失败: ${e.message}');
  /// }
  /// ```
  Future<bool> getVerificationCode(String phone) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiConfig.getCode,
      queryParameters: {'phone': phone},
    );

    if (response.isSuccess) {
      return true;
    } else {
      throw ApiException(
        type: ApiErrorType.serverError,
        message: response.message,
        code: response.code,
      );
    }
  }

  // ==================== 登录/注册 ====================

  /// 用户登录/注册
  ///
  /// [phone] 手机号
  /// [code] 验证码
  ///
  /// 返回 [UserInfo] 用户信息
  /// 抛出 [ApiException] 当登录失败时
  ///
  /// 功能：
  /// 1. 调用登录接口
  /// 2. 保存 Token 到安全存储
  /// 3. 保存用户信息到 SharedPreferences
  /// 4. 记录登录时间
  ///
  /// 示例：
  /// ```dart
  /// try {
  ///   final userInfo = await loginService.login('13800138000', '123456');
  ///   print('登录成功: ${userInfo.userName}');
  /// } on ApiException catch (e) {
  ///   if (e.type == ApiErrorType.unauthorized) {
  ///     print('验证码错误');
  ///   } else {
  ///     print('登录失败: ${e.message}');
  ///   }
  /// }
  /// ```
  Future<UserInfo> login(String phone, String code) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiConfig.login,
      data: {
        'phone': phone,
        'code': code,
      },
    );

    if (response.isSuccess && response.data != null) {
      // 解析用户信息
      final userInfo = UserInfo.fromJson(response.data!);

      // 保存数据到本地
      await _saveUserData(userInfo);

      return userInfo;
    } else {
      throw ApiException(
        type: ApiErrorType.serverError,
        message: response.message,
        code: response.code,
      );
    }
  }

  // ==================== 自动登录 ====================

  /// 检查自动登录
  ///
  /// 检查本地是否有有效的登录信息：
  /// 1. Token 存在
  /// 2. Token 未过期（15 天）
  ///
  /// 返回 true 表示可以自动登录
  ///
  /// 示例（在应用启动时调用）：
  /// ```dart
  /// final canAutoLogin = await loginService.checkAutoLogin();
  /// if (canAutoLogin) {
  ///   // 跳转到主页
  /// } else {
  ///   // 跳转到登录页
  /// }
  /// ```
  Future<bool> checkAutoLogin() async {
    // 检查 Token 是否存在
    final hasToken = await _secureStorage.hasToken();
    if (!hasToken) return false;

    // 检查 Token 是否过期
    final isExpired = await _secureStorage.isTokenExpired();
    if (isExpired) {
      // Token 已过期，清除数据
      await logout();
      return false;
    }

    // 检查用户信息是否完整
    final userInfo = await _sharedPreferences.getUserInfo();
    if (userInfo == null) {
      await logout();
      return false;
    }

    return true;
  }

  // ==================== 登出 ====================

  /// 用户登出
  ///
  /// 清除所有本地存储的用户数据：
  /// - Token（安全存储）
  /// - 用户信息（SharedPreferences）
  /// - 设备绑定信息（可选）
  ///
  /// [clearBindInfo] 是否同时清除设备绑定信息（默认 false）
  ///
  /// 示例：
  /// ```dart
  /// await loginService.logout();
  /// // 跳转到登录页
  /// Get.offAllNamed(WiseNoteRoutePath.login);
  /// ```
  Future<void> logout({bool clearBindInfo = false}) async {
    // 清除安全存储的数据
    await _secureStorage.clearAll();

    // 清除用户信息
    await _sharedPreferences.clearUserInfo();

    // 可选：清除设备绑定信息
    if (clearBindInfo) {
      await _sharedPreferences.clearBindInfo();
    }
  }

  // ==================== 私有方法 ====================

  /// 保存用户数据到本地
  Future<void> _saveUserData(UserInfo userInfo) async {
    // 1. 保存 Token 到安全存储
    await _secureStorage.saveToken(userInfo.token);

    // 2. 保存用户 ID
    await _secureStorage.saveUid(userInfo.uid);

    // 3. 记录登录时间
    await _secureStorage.saveLoginTime(userInfo.loginTime);

    // 4. 保存用户信息到 SharedPreferences
    await _sharedPreferences.saveUserInfo(userInfo.toJson());
  }
}

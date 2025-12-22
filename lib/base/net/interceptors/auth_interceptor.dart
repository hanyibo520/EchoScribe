import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import '../../sp/secure_storage_manager.dart';
import '../../../config/api_config.dart';
import '../../router/router_path.dart';

/// 认证拦截器
///
/// 负责自动管理请求的 Token 认证：
/// - 请求前：自动添加 Authorization header (Bearer token)
/// - 响应错误：检测 401 未授权错误，自动清理本地数据并跳转登录页
class AuthInterceptor extends Interceptor {
  final SecureStorageManager _storage = SecureStorageManager();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 从安全存储中读取 Token
    final token = await _storage.getToken();

    // 如果 Token 存在且不为空，添加到请求头
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] =
          '${ApiConfig.authorizationPrefix} $token';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 检测 401 未授权错误
    if (err.response?.statusCode == 401) {
      // Token 已过期或无效，清除本地所有认证数据
      await _clearAuthData();

      // 跳转到登录页（使用 GetX 路由）
      // offAllNamed 会清除所有路由栈并跳转到登录页
      Get.offAllNamed(WiseNoteRoutePath.login);
    }

    handler.next(err);
  }

  /// 清除所有认证相关数据
  Future<void> _clearAuthData() async {
    try {
      // 清除安全存储的数据（Token、UID、登录时间）
      await _storage.clearAll();

      // TODO: 如果需要，也可以清除 SharedPreferences 中的用户信息
      // final sp = SharedPreferencesManager();
      // await sp.clearUserInfo();
    } catch (e) {
      // 清除数据失败时也不影响跳转登录页
      print('清除认证数据失败: $e');
    }
  }
}

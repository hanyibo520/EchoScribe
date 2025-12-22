/// API 配置类
///
/// 管理所有 API 相关的配置，包括基础 URL、超时时间、端点路径等
class ApiConfig {
  // ==================== 环境配置 ====================

  /// API 基础 URL
  /// TODO: 替换为实际的服务器地址
  static const String baseUrl = 'https://api.wisenote.com';

  // ==================== 超时配置 ====================

  /// 连接超时时间
  static const Duration connectTimeout = Duration(seconds: 15);

  /// 接收数据超时时间
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// 发送数据超时时间
  static const Duration sendTimeout = Duration(seconds: 15);

  // ==================== 认证相关 ====================

  /// Token 有效期（15 天）
  static const Duration tokenExpiration = Duration(days: 15);

  /// Authorization header 前缀
  static const String authorizationPrefix = 'Bearer';

  // ==================== API 端点 ====================

  // 用户认证
  /// 获取验证码
  /// GET /phone/getcode?phone={phone}
  static const String getCode = '/phone/getcode';

  /// 登录/注册
  /// POST /login
  /// Body: { "phone": "...", "code": "..." }
  static const String login = '/login';

  // 反馈相关
  /// 提交反馈
  /// POST /api/feedback/submit
  /// Body: { "content": "...", "images": [...], "uid": "..." }
  static const String uploadFeedback = '/api/feedback/submit';

  // ==================== 常量定义 ====================

  /// 成功的业务状态码
  static const int successCode = 0;

  /// 最大重试次数
  static const int maxRetries = 3;

}

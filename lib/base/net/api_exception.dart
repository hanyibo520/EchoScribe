/// API 错误类型枚举
enum ApiErrorType {
  /// 服务器错误 (500, 502, etc.)
  serverError,

  /// JSON 解析错误
  parsingError,

  /// 无网络连接
  noInternet,

  /// 请求超时
  timeout,

  /// 未授权 (401)
  unauthorized,

  /// 禁止访问 (403)
  forbidden,

  /// 资源不存在 (404)
  notFound,

  /// 请求取消
  cancel,

  /// 未知错误
  unknown,
}

/// API 异常类
///
/// 统一封装所有网络请求相关的异常
class ApiException implements Exception {
  /// 错误类型
  final ApiErrorType type;

  /// 错误消息
  final String message;

  /// HTTP 状态码（可选）
  final int? code;

  /// 附加数据（可选）
  final dynamic data;

  /// 创建 API 异常
  ApiException({
    required this.type,
    required this.message,
    this.code,
    this.data,
  });

  /// 从异常类型获取用户友好的错误消息
  String getUserMessage() {
    switch (type) {
      case ApiErrorType.noInternet:
        return '网络连接失败，请检查网络设置';
      case ApiErrorType.timeout:
        return '请求超时，请稍后重试';
      case ApiErrorType.unauthorized:
        return '登录已过期，请重新登录';
      case ApiErrorType.forbidden:
        return '无权访问该资源';
      case ApiErrorType.notFound:
        return '请求的资源不存在';
      case ApiErrorType.serverError:
        return '服务器错误，请稍后重试';
      case ApiErrorType.parsingError:
        return '数据格式错误';
      case ApiErrorType.cancel:
        return '请求已取消';
      case ApiErrorType.unknown:
        return message;
    }
  }

  @override
  String toString() {
    return 'ApiException{type: $type, message: $message, code: $code}';
  }
}

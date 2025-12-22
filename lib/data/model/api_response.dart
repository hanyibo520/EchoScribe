/// 统一的 API 响应模型
///
/// 封装后端返回的标准响应格式：
/// ```json
/// {
///   "code": 0,
///   "message": "成功",
///   "data": {...}
/// }
/// ```
class ApiResponse<T> {
  /// 业务错误码 (0 = 成功)
  final int code;

  /// 提示信息
  final String message;

  /// 数据载荷（泛型）
  final T? data;

  /// 创建 API 响应实例
  ApiResponse({
    required this.code,
    required this.message,
    this.data,
  });

  /// 是否成功（业务层判断）
  bool get isSuccess => code == 0;

  /// 是否失败
  bool get isFailure => !isSuccess;

  /// 从 JSON 构造 ApiResponse
  ///
  /// [json] 原始 JSON 数据
  /// [dataParser] 可选的数据解析器，用于将 data 字段转换为特定类型 T
  factory ApiResponse.fromJson(
    Map<String, dynamic> json, {
    T Function(dynamic)? dataParser,
  }) {
    return ApiResponse<T>(
      code: json['code'] as int,
      message: json['message'] as String? ?? '',
      data: json['data'] != null && dataParser != null
          ? dataParser(json['data'])
          : json['data'] as T?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'data': data,
    };
  }

  @override
  String toString() {
    return 'ApiResponse{code: $code, message: $message, data: $data}';
  }
}

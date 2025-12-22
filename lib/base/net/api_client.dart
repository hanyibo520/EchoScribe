import 'package:dio/dio.dart';
import '../../config/api_config.dart';
import '../../data/model/api_response.dart';
import 'api_exception.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/log_interceptor.dart';

/// ApiClient 单例
///
/// 基于 Dio 封装的网络请求客户端，提供：
/// - 统一的请求方法（GET、POST、PUT、DELETE）
/// - 文件上传和下载
/// - 自动 Token 管理
/// - 统一错误处理
/// - 请求日志打印
class ApiClient {
  // 单例模式
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;

  /// 内部构造函数
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // 注册拦截器（顺序很重要）
    _dio.interceptors.addAll([
      AuthInterceptor(), 
      prettyDioLogger,
      ErrorInterceptor(), 
    ]);
  }

  /// 获取 Dio 实例（用于高级用法）
  Dio get dio => _dio;

  // ==================== GET 请求 ====================

  /// 发起 GET 请求
  ///
  /// [path] 请求路径（相对于 baseUrl）
  /// [queryParameters] URL 查询参数
  /// [options] 额外的请求选项
  /// [cancelTag] 用于取消请求的标识（可选）
  ///
  /// 返回 [ApiResponse<T>] 统一响应格式
  /// 抛出 [ApiException] 当请求失败时
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    String? cancelTag,
  }) async {
    try {
      CancelToken? cancelToken;
      if (cancelTag != null) {
        cancelToken = _getCancelToken(cancelTag);
      }

      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

      return _parseResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    } finally {
      if (cancelTag != null) {
        _removeCancelToken(cancelTag);
      }
    }
  }

  // ==================== POST 请求 ====================

  /// 发起 POST 请求
  ///
  /// [path] 请求路径
  /// [data] 请求体数据
  /// [queryParameters] URL 查询参数
  /// [options] 额外的请求选项
  /// [cancelTag] 用于取消请求的标识（可选）
  ///
  /// 返回 [ApiResponse<T>] 统一响应格式
  /// 抛出 [ApiException] 当请求失败时
  Future<ApiResponse<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    String? cancelTag,
  }) async {
    try {
      CancelToken? cancelToken;
      if (cancelTag != null) {
        cancelToken = _getCancelToken(cancelTag);
      }

      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

      return _parseResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    } finally {
      if (cancelTag != null) {
        _removeCancelToken(cancelTag);
      }
    }
  }

  // ==================== PUT 请求 ====================

  /// 发起 PUT 请求
  ///
  /// [path] 请求路径
  /// [data] 请求体数据
  /// [queryParameters] URL 查询参数
  /// [options] 额外的请求选项
  ///
  /// 返回 [ApiResponse<T>] 统一响应格式
  /// 抛出 [ApiException] 当请求失败时
  Future<ApiResponse<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );

      return _parseResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ==================== DELETE 请求 ====================

  /// 发起 DELETE 请求
  ///
  /// [path] 请求路径
  /// [queryParameters] URL 查询参数
  /// [options] 额外的请求选项
  ///
  /// 返回 [ApiResponse<T>] 统一响应格式
  /// 抛出 [ApiException] 当请求失败时
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        queryParameters: queryParameters,
        options: options,
      );

      return _parseResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ==================== 文件上传 ====================

  /// 上传文件
  ///
  /// [path] 上传接口路径
  /// [files] 文件列表，MapEntry<字段名, 文件路径>
  /// [data] 附加的表单数据
  /// [onProgress] 上传进度回调
  ///
  /// 返回 [ApiResponse<T>] 统一响应格式
  /// 抛出 [ApiException] 当请求失败时
  Future<ApiResponse<T>> upload<T>(
    String path, {
    required List<MapEntry<String, String>> files,
    Map<String, dynamic>? data,
    ProgressCallback? onProgress,
  }) async {
    try {
      // 构建 FormData
      final formDataMap = <String, dynamic>{
        ...?data,
      };

      // 添加文件
      for (var entry in files) {
        final file = await MultipartFile.fromFile(
          entry.value,
          filename: entry.value.split('/').last,
        );
        formDataMap[entry.key] = file;
      }

      final formData = FormData.fromMap(formDataMap);

      final response = await _dio.post(
        path,
        data: formData,
        onSendProgress: onProgress,
      );

      return _parseResponse<T>(response);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ==================== 文件下载 ====================

  /// 下载文件
  ///
  /// [url] 文件下载地址
  /// [savePath] 本地保存路径
  /// [onProgress] 下载进度回调
  ///
  /// 抛出 [ApiException] 当下载失败时
  Future<void> download(
    String url,
    String savePath, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ==================== 响应解析 ====================

  /// 统一解析响应数据
  ApiResponse<T> _parseResponse<T>(Response response) {
    try {
      final json = response.data as Map<String, dynamic>;
      return ApiResponse<T>(
        code: json['code'] as int,
        message: json['message'] as String? ?? '',
        data: json['data'] as T?,
      );
    } catch (e) {
      throw ApiException(
        type: ApiErrorType.parsingError,
        message: '数据解析失败: $e',
      );
    }
  }

  // ==================== 错误处理 ====================

  /// 统一处理 Dio 错误
  ApiException _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          type: ApiErrorType.timeout,
          message: '请求超时，请检查网络连接',
        );

      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 401) {
          return ApiException(
            type: ApiErrorType.unauthorized,
            message: '登录已过期，请重新登录',
            code: 401,
          );
        } else if (statusCode == 403) {
          return ApiException(
            type: ApiErrorType.forbidden,
            message: '无权访问',
            code: 403,
          );
        } else if (statusCode == 404) {
          return ApiException(
            type: ApiErrorType.notFound,
            message: '资源不存在',
            code: 404,
          );
        } else if (statusCode != null && statusCode >= 500) {
          return ApiException(
            type: ApiErrorType.serverError,
            message: '服务器错误 ($statusCode)',
            code: statusCode,
          );
        }
        return ApiException(
          type: ApiErrorType.serverError,
          message: '服务器错误 (${statusCode ?? 'unknown'})',
          code: statusCode,
        );

      case DioExceptionType.cancel:
        return ApiException(
          type: ApiErrorType.cancel,
          message: '请求已取消',
        );

      case DioExceptionType.connectionError:
        return ApiException(
          type: ApiErrorType.noInternet,
          message: '网络连接失败，请检查网络设置',
        );

      case DioExceptionType.badCertificate:
        return ApiException(
          type: ApiErrorType.serverError,
          message: 'SSL 证书验证失败',
        );

      case DioExceptionType.unknown:
        return ApiException(
          type: ApiErrorType.unknown,
          message: e.message ?? '未知错误',
        );
    }
  }

  // ==================== 请求取消 ====================

  // 用于存储取消令牌的 Map
  final Map<String, CancelToken> _cancelTokens = {};

  /// 获取或创建取消令牌
  CancelToken _getCancelToken(String tag) {
    _cancelTokens[tag] ??= CancelToken();
    return _cancelTokens[tag]!;
  }

  /// 移除取消令牌
  void _removeCancelToken(String tag) {
    _cancelTokens.remove(tag);
  }

  /// 取消指定标签的请求
  void cancelRequest(String tag) {
    final token = _cancelTokens[tag];
    if (token != null && !token.isCancelled) {
      token.cancel('用户取消');
    }
    _cancelTokens.remove(tag);
  }

  /// 取消所有请求
  void cancelAllRequests() {
    for (var token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('取消所有请求');
      }
    }
    _cancelTokens.clear();
  }
}

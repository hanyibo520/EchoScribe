import 'package:dio/dio.dart';

/// 错误拦截器
///
/// 统一处理网络请求错误，但不进行实际的错误转换
/// 主要用于记录错误日志或执行通用的错误处理逻辑
///
/// 注意：实际的错误转换在 ApiClient 中进行
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 这里可以添加通用的错误处理逻辑
    // 例如：记录错误日志、上报错误等

    // TODO: 可以集成错误上报服务（如 Sentry、Firebase Crashlytics）
    // _reportError(err);

    // 继续传递错误，让后续的拦截器或调用方处理
    handler.next(err);
  }

  /// 上报错误（示例）
  // void _reportError(DioException err) {
  //   try {
  //     // 上报到错误监控服务
  //     // Sentry.captureException(err, stackTrace: err.stackTrace);
  //   } catch (e) {
  //     // 上报失败也不影响正常流程
  //   }
  // }
}

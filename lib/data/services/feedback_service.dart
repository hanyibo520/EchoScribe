import '../../base/net/api_client.dart';
import '../../base/sp/secure_storage_manager.dart';
import '../../config/api_config.dart';

/// 反馈服务
///
/// 负责用户反馈相关的网络请求
class FeedbackService {
  final ApiClient _client = ApiClient();
  final SecureStorageManager _secureStorage = SecureStorageManager();

  // ==================== 提交反馈 ====================

  /// 提交用户反馈
  ///
  /// [content] 反馈内容（必填）
  /// [imagePaths] 图片本地路径列表（可选，最多 9 张）
  /// [onProgress] 上传进度回调（可选）
  ///
  /// 返回 true 表示提交成功
  /// 抛出 [ApiException] 当提交失败时
  ///
  /// 示例：
  /// ```dart
  /// try {
  ///   await feedbackService.submitFeedback(
  ///     content: '应用闪退问题',
  ///     imagePaths: ['/path/to/screenshot1.jpg', '/path/to/screenshot2.jpg'],
  ///     onProgress: (sent, total) {
  ///       final percent = (sent / total * 100).toStringAsFixed(0);
  ///       print('上传进度: $percent%');
  ///     },
  ///   );
  ///   print('反馈提交成功');
  /// } on ApiException catch (e) {
  ///   print('提交失败: ${e.message}');
  /// }
  /// ```
  Future<bool> submitFeedback({
    required String content,
    List<String>? imagePaths,
    Function(int sent, int total)? onProgress,
  }) async {
    // 获取用户 ID
    final uid = await _secureStorage.getUid();

    // 如果有图片，使用 upload 方法
    if (imagePaths != null && imagePaths.isNotEmpty) {
      // 限制图片数量
      final limitedPaths =
          imagePaths.length > 9 ? imagePaths.sublist(0, 9) : imagePaths;

      // 构建文件列表（字段名统一为 'images'）
      final files = limitedPaths
          .map((path) => MapEntry('images', path))
          .toList();

      final response = await _client.upload<Map<String, dynamic>>(
        ApiConfig.uploadFeedback,
        files: files,
        data: {
          'content': content,
          if (uid != null) 'uid': uid,
        },
        onProgress: onProgress,
      );

      return response.isSuccess;
    } else {
      // 没有图片，使用普通 POST 请求
      final response = await _client.post<Map<String, dynamic>>(
        ApiConfig.uploadFeedback,
        data: {
          'content': content,
          if (uid != null) 'uid': uid,
        },
      );

      return response.isSuccess;
    }
  }

  // ==================== 获取反馈历史（示例扩展）====================

  /// 获取用户的反馈历史记录
  ///
  /// [page] 页码（从 1 开始）
  /// [pageSize] 每页数量
  ///
  /// 返回反馈记录列表
  ///
  /// 注意：这是一个示例方法，实际 API 端点需要根据后端定义
  ///
  /// 示例：
  /// ```dart
  /// final feedbacks = await feedbackService.getFeedbackHistory(page: 1);
  /// for (var feedback in feedbacks) {
  ///   print('反馈内容: ${feedback['content']}');
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> getFeedbackHistory({
    int page = 1,
    int pageSize = 10,
  }) async {
    // TODO: 根据实际 API 端点修改
    final response = await _client.get<Map<String, dynamic>>(
      '/api/feedback/history',
      queryParameters: {
        'page': page,
        'pageSize': pageSize,
      },
    );

    if (response.isSuccess && response.data != null) {
      final list = response.data!['list'] as List<dynamic>?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    }

    return [];
  }
}

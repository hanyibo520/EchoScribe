import 'package:get/get.dart';
import 'texts.dart';

/// 文字主题控制器
///
/// 使用 GetX 管理文字主题状态，支持主题切换和响应式更新。
class TextStyleThemeController extends GetxController {
  // 响应式状态变量
  final Rx<WiseNoteTextTheme> _currentTheme = DefaultTextStyleTheme().obs;

  /// 获取当前主题
  WiseNoteTextTheme get currentTheme => _currentTheme.value;

  /// 获取当前文字主题方案
  ExtendedTextTheme get currentTextTheme => _currentTheme.value.textTheme;

  /// 切换文字主题
  ///
  /// 参数 [theme] 新的主题实例
  ///
  /// 使用示例：
  /// ```dart
  /// final controller = Get.find<TextStyleThemeController>();
  /// controller.switchTheme(LargeTextStyleTheme());
  /// ```
  void switchTheme(WiseNoteTextTheme theme) {
    _currentTheme.value = theme;
  }
}

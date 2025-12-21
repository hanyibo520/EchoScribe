import 'package:get/get.dart';
import 'colors.dart';

/// 主题控制器，使用 GetX 管理主题切换和暗黑模式
class ColorThemeController extends GetxController {
  // 使用响应式变量，支持 Obx 自动监听
  final Rx<ColorTheme> _currentTheme = DefaultColorTheme().obs;
  final RxBool _isDarkMode = false.obs;

  /// 获取当前主题
  ColorTheme get currentTheme => _currentTheme.value;

  /// 获取当前是否为暗黑模式
  bool get isDarkMode => _isDarkMode.value;

  /// 获取当前颜色方案（根据暗黑模式自动选择）
  ExtendedColorScheme get currentColorScheme =>
      _isDarkMode.value ? _currentTheme.value.dark : _currentTheme.value.light;

  /// 切换主题
  void switchTheme(ColorTheme theme) {
    _currentTheme.value = theme;
  }

  /// 切换暗黑模式
  void toggleDarkMode() {
    _isDarkMode.value = !_isDarkMode.value;
  }

  /// 设置暗黑模式
  void setDarkMode(bool isDark) {
    _isDarkMode.value = isDark;
  }
}


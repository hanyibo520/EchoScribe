import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'text_theme_controller.dart';

/// WiseNote 文字样式定义
///
/// 此类定义了应用中使用的所有原始文字样式常量。
/// 遵循 Material Design 3 规范，同时支持项目自定义样式。
abstract class WiseNoteTextStyles {
  // ===== Material Design 3 标准 TextTheme 样式 =====

  // Display 级别（最大字体）
  static const TextStyle displayLarge = TextStyle(
    fontSize: 57,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.25,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w400,
  );

  // Headline 级别
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w400,
  );

  // Title 级别
  static const TextStyle titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  // Body 级别
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
  );

  // Label 级别
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  // ===== 项目自定义文字样式 =====

  /// 自定义大标题样式
  static const TextStyle customLargeTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  /// 自定义副标题样式
  static const TextStyle customSubtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  /// 自定义说明文字样式
  static const TextStyle customCaption = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
  );
}

/// 扩展的文字主题类
///
/// 组合官方 [TextTheme] 和项目自定义样式，提供统一的访问接口。
/// 采用组合模式而非继承，便于扩展和维护。
class ExtendedTextTheme {
  /// 官方 TextTheme 实例（Material Design 3 标准样式）
  final TextTheme baseTextTheme;

  /// 自定义大标题样式
  final TextStyle customLargeTitle;

  /// 自定义副标题样式
  final TextStyle customSubtitle;

  /// 自定义说明文字样式
  final TextStyle customCaption;

  const ExtendedTextTheme({
    required this.baseTextTheme,
    required this.customLargeTitle,
    required this.customSubtitle,
    required this.customCaption,
  });

  // ===== 便捷访问器（代理 baseTextTheme 的属性）=====

  // Display 级别
  TextStyle get displayLarge => baseTextTheme.displayLarge!;
  TextStyle get displayMedium => baseTextTheme.displayMedium!;
  TextStyle get displaySmall => baseTextTheme.displaySmall!;

  // Headline 级别
  TextStyle get headlineLarge => baseTextTheme.headlineLarge!;
  TextStyle get headlineMedium => baseTextTheme.headlineMedium!;
  TextStyle get headlineSmall => baseTextTheme.headlineSmall!;

  // Title 级别
  TextStyle get titleLarge => baseTextTheme.titleLarge!;
  TextStyle get titleMedium => baseTextTheme.titleMedium!;
  TextStyle get titleSmall => baseTextTheme.titleSmall!;

  // Body 级别
  TextStyle get bodyLarge => baseTextTheme.bodyLarge!;
  TextStyle get bodyMedium => baseTextTheme.bodyMedium!;
  TextStyle get bodySmall => baseTextTheme.bodySmall!;

  // Label 级别
  TextStyle get labelLarge => baseTextTheme.labelLarge!;
  TextStyle get labelMedium => baseTextTheme.labelMedium!;
  TextStyle get labelSmall => baseTextTheme.labelSmall!;
}

/// 文字主题接口
///
/// 定义文字主题必须实现的规范，支持多套字体方案扩展。
abstract class WiseNoteTextTheme {
  /// 文字主题方案
  ExtendedTextTheme get textTheme;

  /// 主题名称（用于标识和UI展示）
  String get name;
}

/// 默认文字主题实现
///
/// 提供默认的字体样式方案，基于 Material Design 3 规范。
class DefaultTextStyleTheme implements WiseNoteTextTheme {
  @override
  String get name => 'Default';

  @override
  ExtendedTextTheme get textTheme {
    // 1. 创建基础 TextTheme
    final baseTheme = TextTheme(
      // Display 级别
      displayLarge: WiseNoteTextStyles.displayLarge,
      displayMedium: WiseNoteTextStyles.displayMedium,
      displaySmall: WiseNoteTextStyles.displaySmall,

      // Headline 级别
      headlineLarge: WiseNoteTextStyles.headlineLarge,
      headlineMedium: WiseNoteTextStyles.headlineMedium,
      headlineSmall: WiseNoteTextStyles.headlineSmall,

      // Title 级别
      titleLarge: WiseNoteTextStyles.titleLarge,
      titleMedium: WiseNoteTextStyles.titleMedium,
      titleSmall: WiseNoteTextStyles.titleSmall,

      // Body 级别
      bodyLarge: WiseNoteTextStyles.bodyLarge,
      bodyMedium: WiseNoteTextStyles.bodyMedium,
      bodySmall: WiseNoteTextStyles.bodySmall,

      // Label 级别
      labelLarge: WiseNoteTextStyles.labelLarge,
      labelMedium: WiseNoteTextStyles.labelMedium,
      labelSmall: WiseNoteTextStyles.labelSmall,
    );

    // 2. 包装为 ExtendedTextTheme
    return ExtendedTextTheme(
      baseTextTheme: baseTheme,
      customLargeTitle: WiseNoteTextStyles.customLargeTitle,
      customSubtitle: WiseNoteTextStyles.customSubtitle,
      customCaption: WiseNoteTextStyles.customCaption,
    );
  }
}

/// BuildContext 扩展方法
///
/// 提供便捷的文字主题访问方式，自动管理控制器生命周期。
///
/// 使用前需要导入：
/// ```dart
/// import 'package:flutter_wisenote/ui/core/themes/texts.dart';
/// ```
extension ExtendedTextThemeExtension on BuildContext {
  /// 获取当前文字主题
  ///
  /// 使用示例：
  /// ```dart
  /// Text('标题', style: context.wiseTextTheme.headlineLarge);
  /// Text('副标题', style: context.wiseTextTheme.customSubtitle);
  /// ```
  ExtendedTextTheme get wiseNoteTextTheme {
    // 获取或创建全局单例控制器
    final controller = Get.put(TextStyleThemeController(), permanent: true);
    return controller.currentTextTheme;
  }
}

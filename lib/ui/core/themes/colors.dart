//主题颜色
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'covert_dark.dart';
import 'color_theme_controller.dart';

/// 所有颜色原之值定义的地方，不能直接访问，统一通过主题访问
/// 这里单独定义其实和下面的是重复的，目的是为了其它主题或者暗黑模式下，可以通过算法基于原始值自动计算
/// 由于MD3的颜色规范比较复杂，我们只指定了5个好理解的基础色走ColorScheme，其它的以自定义属性存在
abstract class WiseNoteColors {
  // =====MD3命名的颜色规范=====
  // 主基色-主按钮背景
  static const Color primary = Color(0xFF1F2230);
  // 主基色上内容颜色-按钮上的文字颜色
  static const Color onPrimary = Color(0xFFFFFFFF);
  // 页面背景
  static const Color surface = Color(0xFFF7F7F7);
  // 错误提示颜色
  static const Color error = Color(0xFFF53F3F);
  // 内容文字颜色
  static const Color onSurface = Color(0xFF21242D);
  // =====基于项目设计命名的自定义颜色，对应扩展颜色属性=====
  // 一级标题文字颜色
  static const Color primaryTitle = Color(0xFF262626);
  // 二级标题文字颜色
  static const Color secondaryTitle = Color(0xFF8C8C8C);
  // 边框颜色
  static const Color border = Color(0xFFF3F3F5);
  // 分割线颜色
  static const Color divider = Color(0xFFE5E5E5);
  
  // 如果实在不好起名字，以colorFFxxxxxx方式命名
  static const Color colorFF000000 = Color(0xFF000000);
}
/// 扩展的 ColorScheme，添加自定义颜色属性，用于主题颜色规范
class ExtendedColorScheme {
  final ColorScheme baseScheme;

  // 一级标题文字颜色
  final Color primaryTitle;
  // 二级标题文字颜色
  final Color secondaryTitle;
  // 边框颜色
  final Color border;
  // 分割线颜色
  final Color divider;
  // 如果实在不好起名字，以colorFFxxxxxx方式命名
  final Color colorFF000000;

  ExtendedColorScheme({
    required this.baseScheme,
    required this.primaryTitle,
    required this.secondaryTitle,
    required this.border,
    required this.divider,
    required this.colorFF000000,
  });

  // 便捷访问器，直接访问 baseScheme 的属性,
  // 由于MD的定义规则不好理解，这里只指定几个通用的，其它的以自定义属性存在
  // 主基色-主按钮背景
  Color get primary => baseScheme.primary;

  // 主基色上内容颜色-按钮上的文字颜色
  Color get onPrimary => baseScheme.onPrimary;

  // 页面背景
  Color get surface => baseScheme.surface;

  // 页面文字颜色
  Color get onSurface => baseScheme.onSurface;

  // 错误提示颜色
  Color get error => baseScheme.error;
}

/// 主题颜色规范接口
abstract class WiseNoteColorTheme {
  /// 亮色模式的颜色方案
  ExtendedColorScheme get light;

  /// 暗色模式的颜色方案
  ExtendedColorScheme get dark;

  /// 主题名称
  String get name;
}

/// 默认主题实现
class DefaultColorTheme with CovertDarkMixin implements WiseNoteColorTheme {
  @override
  String get name => 'Default';

  @override
  ExtendedColorScheme get light {
    final baseScheme =
        ColorScheme.fromSeed(
          seedColor: WiseNoteColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: WiseNoteColors.primary,
          onPrimary: WiseNoteColors.onPrimary,
          surface: WiseNoteColors.surface,
          onSurface: WiseNoteColors.onSurface,
          error: WiseNoteColors.error,
        );

    return ExtendedColorScheme(
      baseScheme: baseScheme,
      primaryTitle: WiseNoteColors.primaryTitle,
      secondaryTitle: WiseNoteColors.secondaryTitle,
      border: WiseNoteColors.border,
      divider: WiseNoteColors.divider,
      colorFF000000: WiseNoteColors.colorFF000000,
    );
  }

  @override
  ExtendedColorScheme get dark {
    
    
    // 优先使用 ColorScheme.fromSeed 生成暗色模式的基础色
    final baseScheme =
        ColorScheme.fromSeed(
          seedColor: WiseNoteColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          // 使用转换函数转换基础色
          primary: convertToDark(WiseNoteColors.primary),
          onPrimary: convertToDark(WiseNoteColors.onPrimary, isTextColor: true),
          surface: convertToDark(WiseNoteColors.surface, isBackgroundColor: true),
          onSurface: convertToDark(WiseNoteColors.onSurface, isTextColor: true),
          error: convertToDark(WiseNoteColors.error),
        );

    return ExtendedColorScheme(
      baseScheme: baseScheme,
      // 暗色模式的扩展颜色：使用统一的转换函数
      primaryTitle: convertToDark(WiseNoteColors.primaryTitle, isTextColor: true),
      secondaryTitle: convertToDark(WiseNoteColors.secondaryTitle, isTextColor: true),
      border: convertToDark(WiseNoteColors.border),
      divider: convertToDark(WiseNoteColors.divider),
      colorFF000000: convertToDark(WiseNoteColors.colorFF000000, isTextColor: true),
    );
  }
}

/// BuildContext 扩展方法，方便在 Widget 中访问 ExtendedColorScheme
/// 
/// 使用前需要导入：
/// ```dart
/// import 'package:flutter_wisenote/ui/core/themes/colors.dart';
/// ```
/// 
/// 使用示例：
/// ```dart
/// // 在任意 Widget 的 build 方法中，通过 context.colorScheme 获取颜色方案
/// Widget build(BuildContext context) {
///   return Container(
///     decoration: BoxDecoration(
///       // 使用自定义颜色属性
///       border: Border.all(color: context.colorScheme.border),
///       color: context.colorScheme.surface,
///     ),
///     child: Column(
///       children: [
///         // 使用文字颜色
///         Text(
///           '一级标题',
///           style: TextStyle(color: context.colorScheme.primaryTitle),
///         ),
///         Text(
///           '二级标题',
///           style: TextStyle(color: context.colorScheme.secondaryTitle),
///         ),
///         // 使用 ColorScheme 标准颜色
///         ElevatedButton(
///           style: ElevatedButton.styleFrom(
///             backgroundColor: context.colorScheme.primary,
///             foregroundColor: context.colorScheme.onPrimary,
///           ),
///           onPressed: () {},
///           child: Text('按钮'),
///         ),
///         // 访问其他 ColorScheme 属性
///         Container(
///           color: context.colorScheme.baseScheme.secondary,
///         ),
///       ],
///     ),
///   );
/// }
/// ```
extension ExtendedColorSchemeExtension on BuildContext {
  /// 如果 ColorThemeController 尚未注册，会自动创建并注册（permanent: true 确保是全局单例）
  ExtendedColorScheme get wiseNoteColorScheme {
    final controller = Get.put(ColorThemeController(), permanent: true);
    return controller.currentColorScheme;
  }
}

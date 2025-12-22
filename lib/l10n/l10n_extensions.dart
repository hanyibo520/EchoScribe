import 'package:flutter/widgets.dart';
import 'package:flutter_wisenote/l10n/app_localizations.dart';

/// BuildContext 的扩展方法，用于简化本地化文本的访问
///
/// 使用示例：
/// ```dart
/// // 之前的写法：
/// AppLocalizations.of(context)!.appName
///
/// // 现在可以简化为：
/// context.l10n.appName
/// ```
extension LocalizationExtension on BuildContext {
  /// 获取 AppLocalizations 实例
  ///
  /// 这是一个便捷的 getter，用于替代 `AppLocalizations.of(context)!`
  ///
  /// 注意：这个方法假设 AppLocalizations 已经在 MaterialApp 中正确配置
  /// 如果没有配置，将抛出异常
  AppLocalizations get l10n {
    final localizations = AppLocalizations.of(this);
    assert(localizations != null, 'AppLocalizations not found in context. '
        'Make sure to configure localizationsDelegates in MaterialApp.');
    return localizations!;
  }
}

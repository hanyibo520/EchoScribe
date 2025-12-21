import 'package:flutter/material.dart';

mixin CovertDarkMixin {
  // 调整颜色亮度到目标值
    Color _adjustLuminance(Color color, double targetLuminance) {
      final currentLuminance = color.computeLuminance();
      if ((targetLuminance - currentLuminance).abs() < 0.01) {
        return color;
      }
      
      // 使用二分法调整颜色，直到达到目标亮度
      Color adjust(Color c, double factor) {
        final hsl = HSLColor.fromColor(c);
        final newLightness = (hsl.lightness * factor).clamp(0.0, 1.0);
        return hsl.withLightness(newLightness).toColor();
      }
      
      Color testColor = color;
      double factor = targetLuminance > currentLuminance ? 1.2 : 0.8;
      int iterations = 0;
      
      while (iterations < 20) {
        testColor = adjust(testColor, factor);
        final testLuminance = testColor.computeLuminance();
        
        if ((testLuminance - targetLuminance).abs() < 0.02) {
          return testColor;
        }
        
        if (testLuminance > targetLuminance) {
          factor *= 0.95;
        } else {
          factor *= 1.05;
        }
        iterations++;
      }
      
      return testColor;
    }
    
    // 统一的颜色转换函数：将亮色模式颜色转换为暗色模式
    // 参考 Material Design 3 和 Flutter ColorScheme.fromSeed 的转换规则
    Color convertToDark(Color lightColor, {bool isTextColor = false, bool isBackgroundColor = false}) {
      final luminance = lightColor.computeLuminance();
      
      // 如果是文字颜色（亮度较低），在暗色模式下需要变亮
      if (isTextColor || luminance < 0.3) {
        // 文字颜色：使用高对比度的亮色，确保在暗色背景上可读
        // 根据原始亮度调整，较暗的文字在暗色模式下变得更亮
        final targetLuminance = 0.85 + (luminance * 0.1); // 目标亮度 0.85-0.95
        return _adjustLuminance(lightColor, targetLuminance);
      }
      
      // 如果是背景颜色（亮度较高），在暗色模式下需要变暗
      if (isBackgroundColor || luminance > 0.7) {
        // 背景颜色：使用低亮度的暗色
        final targetLuminance = 0.08 + (luminance * 0.05); // 目标亮度 0.08-0.15
        return _adjustLuminance(lightColor, targetLuminance);
      }
      
      // 中等亮度的颜色（如边框、分割线），适度变暗
      final targetLuminance = 0.15 + (luminance * 0.1); // 目标亮度 0.15-0.25
      return _adjustLuminance(lightColor, targetLuminance);
    }
}
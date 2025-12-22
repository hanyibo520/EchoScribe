import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_wisenote/l10n/app_localizations.dart';
import 'package:flutter_wisenote/l10n/l10n_extensions.dart';
import 'package:flutter_wisenote/ui/core/themes/colors.dart';
import 'package:flutter_wisenote/ui/core/themes/color_theme_controller.dart';
import 'package:flutter_wisenote/ui/core/themes/texts.dart';
import 'package:flutter_wisenote/ui/core/themes/text_theme_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 确保控制器已注册
    final colorController = Get.put(ColorThemeController(), permanent: true);
    final textController = Get.put(TextStyleThemeController(), permanent: true);

    // 使用 Obx 自动监听主题和暗黑模式的变化
    return Obx(() {
      final colorScheme = colorController.currentColorScheme;
      final textTheme = textController.currentTextTheme;

      return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: colorScheme.baseScheme,
          textTheme: textTheme.baseTextTheme,
        ),
        darkTheme: ThemeData(
          colorScheme: colorController.currentTheme.dark.baseScheme,
          textTheme: textTheme.baseTextTheme,
        ),
        themeMode: colorController.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MyHomePage(title: 'Flutter Demo Home Page'),
      );
    });
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.wiseNoteColorScheme.primary,
        title: Text(
          widget.title,
          style: context.wiseNoteTextTheme.titleLarge.copyWith(
            color: context.wiseNoteColorScheme.onPrimary,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l10n.appName,
              style: context.wiseNoteTextTheme.bodyLarge,
            ),
            Text(
              '$_counter',
              style: context.wiseNoteTextTheme.displayMedium.copyWith(
                color: context.wiseNoteColorScheme.primary,
              ),
            ),
            Text(
              'Text Theme titleLarge',
              style: context.wiseNoteTextTheme.titleLarge.copyWith(
                color: context.wiseNoteColorScheme.primary,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_wisenote/l10n/app_localizations.dart';
import 'package:flutter_wisenote/ui/core/themes/colors.dart';
import 'package:flutter_wisenote/ui/core/themes/color_theme_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 确保控制器已注册
    final controller = Get.put(ColorThemeController(), permanent: true);
    
    // 使用 Obx 自动监听主题和暗黑模式的变化
    return Obx(() {
      final colorScheme = controller.currentColorScheme;
      return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: colorScheme.baseScheme,
        ),
        darkTheme: ThemeData(
          colorScheme: controller.currentTheme.dark.baseScheme,
        ),
        themeMode: controller.isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
        backgroundColor: context.colorScheme.primary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Text(AppLocalizations.of(context)!.appName),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
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

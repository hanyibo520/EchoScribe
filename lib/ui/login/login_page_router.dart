import 'package:go_router/go_router.dart';
import 'package:flutter_wisenote/base/router/router_path.dart';
import 'login_page.dart';

/// 登录页面的 GoRouter 配置
final loginRoute = GoRoute(
  path: WiseNoteRoutePath.login,
  builder: (context, state) => const LoginPage(),
);
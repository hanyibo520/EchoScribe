import 'package:go_router/go_router.dart';
import 'package:flutter_wisenote/base/router/router_path.dart';
import 'package:flutter_wisenote/ui/login/login_page_router.dart';
final GoRouter appRouter = GoRouter(
  initialLocation: WiseNoteRoutePath.root,
  routes: [
    loginRoute,
  ],
  redirect: (context, state) {
    // 全局重定向逻辑
    return WiseNoteRoutePath.login;
  },
);
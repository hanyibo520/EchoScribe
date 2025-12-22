# 路由定义规范

本文档说明如何在项目中定义和管理路由。

## 路由定义流程

在项目中添加新页面路由需要按照以下 4 个步骤进行：

### 1. 创建页面组件

首先创建页面文件，例如 `login_page.dart`，包含一个页面组件：

```dart
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
      ),
      body: const Center(
        child: Text('LoginPage'),
      ),
    );
  }
}
```

**文件位置**：`lib/ui/{模块名}/{页面名}_page.dart`

### 2. 在 router_path.dart 中定义路由常量

在 `lib/base/router/router_path.dart` 中添加路由路径常量：

```dart
class WiseNoteRoutePath {
  // ... 其他路由常量
  
  //登录页
  static const String login = '/login';
  
  // 新页面路由常量
  static const String newPage = '/newPage';
}
```

**命名规范**：
- 使用小驼峰命名（camelCase）
- 路径以 `/` 开头
- 添加清晰的注释说明页面用途

### 3. 创建业务层路由配置文件

在对应的业务模块目录下创建路由配置文件，例如 `lib/ui/login/login_page_router.dart`：

```dart
import 'package:go_router/go_router.dart';
import 'package:flutter_wisenote/base/router/router_path.dart';
import 'login_page.dart';

/// 登录页面的 GoRouter 配置
final loginRoute = GoRoute(
  path: WiseNoteRoutePath.login,
  builder: (context, state) => const LoginPage(),
);
```

**文件命名**：`{页面名}_router.dart`  
**文件位置**：与页面文件同级目录

**配置说明**：
- 使用 `GoRoute` 定义路由
- `path` 使用 `WiseNoteRoutePath` 中定义的常量
- `builder` 返回对应的页面组件
- 添加文档注释说明路由用途

### 4. 注册路由到 app_router.dart

在 `lib/base/router/app_router.dart` 中导入并注册路由：

```dart
import 'package:go_router/go_router.dart';
import 'package:flutter_wisenote/base/router/router_path.dart';
import 'package:flutter_wisenote/ui/login/login_page_router.dart';
// 导入新的路由配置
import 'package:flutter_wisenote/ui/new_module/new_page_router.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: WiseNoteRoutePath.root,
  routes: [
    loginRoute,
    newPageRoute, // 注册新路由
  ],
  redirect: (context, state) {
    // 全局重定向逻辑
    return null; // 返回 null 表示不重定向
  },
);
```

**注意事项**：
- 在文件顶部导入路由配置文件
- 在 `routes` 数组中添加路由配置
- 保持路由注册顺序清晰

## 完整示例

以登录页面为例，完整的路由定义流程：

### 步骤 1：创建页面
`lib/ui/login/login_page.dart`

```dart
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: const Center(child: Text('LoginPage')),
    );
  }
}
```

### 步骤 2：定义路由常量
`lib/base/router/router_path.dart`

```dart
class WiseNoteRoutePath {
  //登录页
  static const String login = '/login';
}
```

### 步骤 3：创建路由配置
`lib/ui/login/login_page_router.dart`

```dart
import 'package:go_router/go_router.dart';
import 'package:flutter_wisenote/base/router/router_path.dart';
import 'login_page.dart';

/// 登录页面的 GoRouter 配置
final loginRoute = GoRoute(
  path: WiseNoteRoutePath.login,
  builder: (context, state) => const LoginPage(),
);
```

### 步骤 4：注册路由
`lib/base/router/app_router.dart`

```dart
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
    return null;
  },
);
```

## 路由使用

### 导航到页面

```dart
// 使用 GoRouter 导航-替换前页
context.go(WiseNoteRoutePath.login);

// 或使用 push-入栈
context.push(WiseNoteRoutePath.login);
```

## 注意事项

1. **路由路径统一管理**：所有路由路径常量必须在 `router_path.dart` 中定义，不要硬编码路径字符串
2. **文件命名规范**：路由配置文件统一使用 `{页面名}_router.dart` 命名
3. **导入顺序**：在 `app_router.dart` 中保持导入顺序清晰，建议按模块分组
4. **路由注释**：为每个路由配置添加注释，说明路由用途
5. **全局重定向**：在 `app_router.dart` 的 `redirect` 回调中处理全局路由重定向逻辑（如登录验证）

## 项目结构

```
lib/
├── base/
│   └── router/
│       ├── app_router.dart          # 主路由配置
│       └── router_path.dart          # 路由路径常量
└── ui/
    └── login/
        ├── login_page.dart           # 页面组件
        └── login_page_router.dart    # 路由配置
```


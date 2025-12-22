# 百智 (WiseNote)

> 智能音频录制与管理平台，通过蓝牙录音设备实现专业级音频采集、云端同步、智能整理

## 📱 项目简介

百智（WiseNote）是一款基于 Flutter 开发的智能音频录制与管理应用，支持通过蓝牙设备进行专业级音频采集，并提供云端同步和智能整理功能。

### 核心功能

- 🎙️ **蓝牙设备管理** - BLE 设备扫描、配对、状态监控
- 🎵 **音频录制** - 实时录音控制，支持设备端和 App 端两种模式
- ☁️ **文件同步** - 音频文件增量同步，CRC16 数据校验
- 👤 **用户系统** - 手机号验证码登录，Token 认证
- ⚙️ **个人中心** - 设备管理、反馈提交、帮助与设置

## 🏗️ 项目架构

本项目采用**分层架构**设计，清晰划分各层职责：

```
lib/
├── base/              # 基础层
│   ├── db/           # 数据库相关
│   ├── log/          # 日志管理
│   ├── net/          # 网络请求封装
│   └── sp/           # 本地存储（SharedPreferences）
│
├── config/           # 配置管理
│
├── data/             # 数据层
│   ├── model/        # 数据模型
│   ├── repositories/ # 数据仓库
│   └── services/     # 业务服务
│
├── domain/           # 领域层
│   └── models/       # 领域模型
│
├── ui/               # UI 层
│   ├── core/         # 核心组件
│   │   ├── themes/   # 主题配置（颜色、文本样式）
│   │   └── ui/       # 通用 UI 组件
│   ├── home/         # 首页模块
│   │   ├── view_model/  # 视图模型
│   │   └── widgets/     # 组件
│   ├── login/        # 登录模块
│   │   ├── view_model/
│   │   └── widgets/
│   └── mine/         # 个人中心模块
│       ├── view_model/
│       └── widgets/
│
├── l10n/             # 国际化
│   ├── app_zh.arb    # 中文资源
│   └── app_en.arb    # 英文资源
│
├── utils/            # 工具类
│
└── main.dart         # 应用入口
```

### 架构说明

- **base 层**: 提供基础设施能力（数据库、日志、网络、存储）
- **data 层**: 负责数据获取和处理，包含数据模型、仓库和服务
- **domain 层**: 业务领域模型，独立于具体实现
- **ui 层**: 用户界面，按功能模块划分，采用 MVVM 模式
- **l10n**: 国际化支持，目前支持中文和英文

## 🛠️ 技术栈

### 核心框架

- **Flutter SDK**: ^3.10.4
- **GetX**: ^4.7.3 - 状态管理、路由管理、依赖注入

### 主要依赖

| 依赖包 | 版本 | 用途 |
|--------|------|------|
| `flutter_blue_plus` | ^2.0.2 | BLE 蓝牙通信 |
| `dio` | ^5.9.0 | HTTP 网络请求 |
| `shared_preferences` | ^2.5.4 | 本地键值存储 |
| `flutter_secure_storage` | ^10.0.0 | 安全存储（Token 等） |
| `path_provider` | ^2.1.5 | 文件路径获取 |
| `image_picker` | ^1.2.1 | 图片选择 |
| `cached_network_image` | ^3.4.1 | 网络图片缓存 |
| `flutter_svg` | ^2.2.3 | SVG 图片支持 |
| `fluttertoast` | ^9.0.0 | Toast 提示 |
| `easy_refresh` | ^3.4.0 | 下拉刷新/上拉加载 |
| `webview_flutter` | ^4.13.0 | WebView 支持 |
| `permission_handler` | ^12.0.1 | 权限管理 |
| `uuid` | ^4.5.1 | UUID 生成 |
| `logging` | ^1.3.0 | 日志记录 |
| `intl` | ^0.20.2 | 国际化支持 |

### 开发依赖

- `flutter_lints`: ^6.0.0 - 代码规范检查
- `freezed`: ^2.5.7 - 数据类生成
- `json_annotation`: ^4.9.0 - JSON 序列化注解
- `json_serializable`: ^6.9.5 - JSON 序列化代码生成
- `build_runner`: ^2.4.13 - 代码生成工具

## 🚀 快速开始

### 环境要求

- Flutter SDK: ^3.10.4
- Dart SDK: 与 Flutter SDK 配套
- iOS: 13.0+
- Android: API 21+

### 安装步骤

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd flutter_wisenote
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **生成代码**（如需要）
   ```bash
   flutter pub run build_runner build
   ```

4. **运行项目**
   ```bash
   flutter run
   ```

## 📁 目录结构说明

### base/ - 基础层

提供应用的基础能力：

- **db/**: 数据库操作封装
- **log/**: 日志管理，基于 `logging` 包
- **net/**: 网络请求封装，基于 `dio`
- **sp/**: SharedPreferences 封装

### data/ - 数据层

- **model/**: API 数据模型，使用 `json_serializable` 自动生成序列化代码
- **repositories/**: 数据仓库，统一数据访问接口
- **services/**: 业务服务层，处理具体业务逻辑

### domain/ - 领域层

- **models/**: 领域模型，定义业务实体

### ui/ - UI 层

采用 MVVM 模式，每个功能模块包含：

- **view_model/**: 视图模型，处理业务逻辑和状态管理
- **widgets/**: 模块内可复用组件

**core/themes/**: 主题配置
- `colors.dart`: 颜色定义，支持亮色/暗色主题
- `texts.dart`: 文本样式定义
- `color_theme_controller.dart`: 主题控制器（GetX）

## 🎨 主题系统

项目采用 Material Design 3 颜色规范，支持亮色和暗色主题切换。

### 颜色定义

- **MD3 规范颜色**: primary, onPrimary, surface, error, onSurface
- **自定义颜色**: primaryTitle, secondaryTitle, border, divider

### 主题切换

通过 `ColorThemeController` 管理主题，支持：
- 亮色/暗色模式切换
- 多主题色方案（可扩展）

## 🌐 国际化

项目支持多语言，目前包含：

- 中文（zh）
- 英文（en）

资源文件位于 `lib/l10n/` 目录，使用 `.arb` 格式。

## 📝 开发规范

### 代码风格

- 遵循 Flutter 官方代码规范
- 使用 `flutter_lints` 进行代码检查

### 命名规范

- 文件命名：使用下划线命名法（snake_case）
- 类命名：使用大驼峰命名法（PascalCase）
- 变量/方法命名：使用小驼峰命名法（camelCase）

### 架构规范

- UI 层不直接访问数据层，通过 ViewModel 处理
- 数据层通过 Repository 统一访问接口
- 使用 GetX 进行状态管理和依赖注入

## 🔧 构建说明

### 生成代码

项目使用代码生成工具，需要运行：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 代码检查

```bash
flutter analyze
```

### 运行测试

```bash
flutter test
```

## 📄 许可证

本项目为私有项目，不对外开源。

## 👥 贡献

本项目为内部项目，如有问题请联系开发团队。

## 📞 联系方式

如有问题或建议，请联系项目维护团队。

---

**版本**: 1.0.0+1  
**最后更新**: 2025-01-XX

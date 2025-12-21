# 百智（WiseNote）iOS 应用反向工程需求文档

> 本文档基于对 BaiZhi iOS 原生应用的完整代码分析，旨在为 Flutter 开发团队提供详尽的功能规格和实现细节，以便完整复现原应用的功能和用户体验。

**文档版本：** v1.0
**生成日期：** 2025-12-20
**目标平台：** Flutter (iOS + Android)

---

## 📑 目录

- [一、项目概述](#一项目概述)
- [二、技术架构](#二技术架构)
- [三、用户认证模块](#三用户认证模块)
- [四、首页模块（设备管理与录音文件）](#四首页模块设备管理与录音文件)
- [五、个人中心模块](#五个人中心模块)
- [六、录音模块](#六录音模块)
- [七、蓝牙设备通信协议（核心）](#七蓝牙设备通信协议核心)
- [八、数据模型汇总](#八数据模型汇总)
- [九、API 接口文档](#九api-接口文档)
- [十、特殊注意事项](#十特殊注意事项)
- [十一、平台差异说明](#十一平台差异说明)
- [附录](#附录)

---

## 一、项目概述

### 1.1 应用简介

**应用名称：** 百智（BaiZhi / WiseNote）
**应用定位：** 智能音频录制与管理平台
**核心价值：** "能听·能记·能写" - 通过蓝牙录音设备实现专业级音频采集、云端同步、智能整理

### 1.2 核心功能

1. **蓝牙设备管理**
   - BLE 设备扫描与配对
   - 设备状态实时监控
   - 设备信息查询（电量、存储、SN 码等）
   - 设备配置（WiFi、自动关机等）

2. **音频录制**
   - 实时录音控制（启动/暂停/恢复/停止）
   - 音频文件本地存储
   - 支持设备端主动录音和 App 端控制录音两种模式

3. **文件同步**
   - BLE 文件列表获取
   - 音频文件增量同步
   - CRC16 数据校验
   - 自动保存到本地

4. **用户系统**
   - 手机号 + 验证码登录
   - Token 认证
   - 用户信息管理

5. **个人中心**
   - 设备管理
   - 反馈提交
   - 帮助与设置

### 1.3 技术特点

- **最低 iOS 版本：** iOS 13.0
- **开发语言：** Swift
- **架构模式：** MVVM-like，基于 Manager 层的业务逻辑封装
- **依赖管理：** CocoaPods
- **网络框架：** Alamofire 5.10.2（支持 async/await）
- **蓝牙协议：** CoreBluetooth（BLE 4.0+）
- **音频格式：** Opus（无 Ogg 容器，直接保存原始 Opus 帧）

---

## 二、技术架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────┐
│                   Presentation Layer                 │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│   │  Login   │  │   Home   │  │ Profile  │  ...    │
│   │ Module   │  │  Module  │  │  Module  │         │
│   └──────────┘  └──────────┘  └──────────┘         │
├─────────────────────────────────────────────────────┤
│                   Business Layer                     │
│   ┌──────────────────┐  ┌────────────────────────┐ │
│   │ LoginManager     │  │ BluetoothDeviceManager │ │
│   ├──────────────────┤  ├────────────────────────┤ │
│   │ NetworkManager   │  │ VerificationCodeMgr    │ │
│   └──────────────────┘  └────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│                     Data Layer                       │
│   ┌──────────────┐  ┌──────────────┐               │
│   │ UserDefaults │  │ File System  │               │
│   └──────────────┘  └──────────────┘               │
├─────────────────────────────────────────────────────┤
│                   Network & BLE                      │
│   ┌──────────────┐  ┌──────────────┐               │
│   │   Alamofire  │  │ CoreBluetooth│               │
│   └──────────────┘  └──────────────┘               │
└─────────────────────────────────────────────────────┘
```

### 2.2 模块划分

| 模块名称 | 职责 | 关键类 |
|---------|------|--------|
| **Application** | 应用基础设施 | BaseViewController, TabBarController |
| **Login Module** | 用户认证 | LoginViewController, LoginManager |
| **Home Module** | 设备管理、文件列表 | HomeViewController, SearchDeviceViewController |
| **Profile Module** | 个人信息、设备管理 | ProfileViewController, MyDeviceViewController |
| **Record Module** | 实时录音 | RecordViewController |
| **Bluetooth Manager** | BLE 通信核心 | BluetoothDeviceManager (2200+ 行) |
| **Network Manager** | HTTP 请求封装 | NetworkManager, RequestInterceptor |
| **Utils** | 工具类 | Constants, DateUtils, ToastUtil |

### 2.3 设计模式

1. **单例模式** - 所有 Manager 类（LoginManager, NetworkManager, BluetoothDeviceManager 等）
2. **代理模式** - BluetoothDeviceManagerDelegate（40+ 回调方法）
3. **多播代理** - BluetoothDeviceManagerMulticastDelegate（支持多个监听者）
4. **模板方法** - BaseViewController（setupUI, setupConstraints, setupNavigation）
5. **观察者模式** - NotificationCenter（登录状态变化通知）

### 2.4 数据流向

```
用户交互 → ViewController → Manager → Network/BLE → 数据处理 → 回调 → UI 更新
```

### 2.5 第三方依赖

| 库名称 | 版本 | 用途 |
|--------|------|------|
| Alamofire | 5.10.2 | HTTP 网络请求 |
| SwiftyJSON | 5.0.0 | JSON 解析辅助 |
| SnapKit | 5.6.0 | 自动布局 |
| Kingfisher | 7.6.0 | 图片加载缓存 |
| Toast-Swift | 5.0.0 | 消息提示 |
| IQKeyboardManagerSwift | 6.5.0 | 键盘自动管理 |
| MJRefresh | 3.7.5 | 下拉刷新 |

---

## 三、用户认证模块

### 3.1 模块概述

用户认证模块负责应用的登录/注册流程，采用**手机号 + 验证码**的无密码登录方式。该模块包含登录界面、用户信息管理、登录状态持久化及自动登录功能。

**业务目标：**
- 降低用户注册门槛（无需设置密码）
- 确保手机号实名认证
- 维护用户会话（Token 机制）
- 支持自动登录（15 天有效期）

---

### 3.2 核心功能列表

1. **手机号验证码登录/注册**
2. **手机号格式实时校验**
3. **验证码倒计时**
4. **用户协议与隐私政策同意**
5. **登录状态管理**
6. **自动登录**
7. **Token 刷新**
8. **用户信息本地持久化**

---

### 3.3 详细功能描述与实现逻辑

#### 3.3.1 登录界面 (BZLoginViewController)

**UI 组件：**
- 手机号输入框
- 验证码输入框
- 获取验证码按钮（支持倒计时）
- 用户协议勾选框
- 登录按钮

**交互流程：**

```
1. 用户输入手机号
   ├─ 实时验证格式（11位，以1开头）
   ├─ 格式错误 → 边框显示红色
   └─ 格式正确 → 边框恢复正常

2. 用户点击"获取验证码"
   ├─ 前置校验：手机号格式必须正确
   ├─ 发送请求到后端
   ├─ 成功 → 显示60秒倒计时
   └─ 倒计时期间按钮禁用

3. 用户输入6位验证码
   └─ 仅允许数字，最多6位

4. 用户勾选用户协议
   └─ 可点击协议文字查看详情（WebView）

5. 用户点击"登录"按钮
   ├─ 校验手机号（11位，1开头）
   ├─ 校验验证码（6位）
   ├─ 校验协议勾选状态
   ├─ 全部通过 → 调用登录接口
   ├─ 登录成功 → 保存用户信息 → 跳转主界面
   └─ 登录失败 → 显示错误提示
```

**按钮状态控制：**

登录按钮启用条件（三个条件同时满足）：
1. 手机号格式正确（11位，以1开头）
2. 验证码格式正确（6位数字）
3. 已勾选用户协议

启用状态：蓝色背景 (`#165DFF`)
禁用状态：灰色背景 (`#F5F5F5`)

**输入限制：**

| 输入框 | 限制规则 |
|--------|---------|
| 手机号 | 仅数字，最多11位，第一位必须是1 |
| 验证码 | 仅数字，最多6位 |

**边框颜色反馈：**
- 正常状态：`#F7F8FA`
- 错误状态：`#FFE5E5`（红色）

---

#### 3.3.2 登录管理器 (BZLoginManager)

**设计模式：** 单例模式

**核心职责：**
1. 用户登录状态管理
2. 用户信息持久化（UserDefaults）
3. 自动登录检查
4. Token 管理
5. 登录状态通知

**登录状态枚举：**

```dart
// Flutter 等价实现
enum LoginState {
  loggedIn,     // 已登录
  loggedOut,    // 已登出
  expired,      // Token 已过期
}
```

**关键方法：**

| 方法名 | 参数 | 功能 |
|--------|------|------|
| `login(userInfo)` | BZUserInfo | 用户登录，保存信息 |
| `logout()` | - | 清除用户信息，更新状态 |
| `checkAutoLogin()` | - | 检查本地是否有有效登录信息 |
| `refreshToken(newToken)` | String | 更新Token |
| `updateUserInfo(...)` | userName, phone | 更新用户信息 |
| `isLoggedIn` | - | 当前是否已登录（只读属性） |

**登录流程：**

```
接收用户信息 → 保存到内存（currentUser） 
→ 保存到 UserDefaults 
→ 更新登录状态为 loggedIn 
→ 发送通知（loginStateChanged）
```

**自动登录检查逻辑：**

```
应用启动时调用
├─ 从 UserDefaults 读取：token, uid, userName, phone, loginTime
├─ 检查是否全部存在
├─ 检查 Token 是否过期（登录时间 + 15天）
│  ├─ 未过期 → 恢复登录状态
│  └─ 已过期 → 标记为 expired，返回 false
└─ 返回自动登录结果
```

**Token 过期时间：** 15 天（`15 * 24 * 60 * 60` 秒）

**UserDefaults 存储键：**

| 键名 | 说明 |
|------|------|
| `current_token` | 认证令牌 |
| `current_uid` | 用户唯一ID |
| `current_user_name` | 用户名 |
| `current_phone` | 手机号 |
| `login_time` | 登录时间（Date） |
| `is_active` | 是否激活 |

---

#### 3.3.3 验证码管理器 (BZVerificationCodeManager)

**设计模式：** 单例模式

**职责：**
- 管理多个验证码倒计时器
- 防止重复发送
- 倒计时实时更新

**关键方法：**

```dart
// Flutter 等价实现
class VerificationCodeManager {
  // 启动倒计时
  void startCountdown({
    required String key,           // 标识符（如手机号）
    int duration = 60,             // 倒计时秒数
    required Function(int) onUpdate,    // 每秒回调
    required VoidCallback onComplete,   // 完成回调
  });
  
  // 停止倒计时
  void stopCountdown(String key);
  
  // 获取剩余时间
  int getRemainingTime(String key);
  
  // 是否正在倒计时
  bool isCountingDown(String key);
}
```

**倒计时按钮状态：**
- 正常状态：`获取验证码`（蓝色）
- 倒计时中：`60s 后重新获取`（灰色，禁用）
- 倒计时结束：恢复正常状态

---

#### 3.3.4 用户协议组件 (BZAgreementView)

**功能：**
- 显示勾选框 + 协议文字
- 支持多个协议链接
- 点击协议文字跳转 WebView

**数据结构：**

```dart
class Agreement {
  final String id;           // 协议ID
  final String title;        // 协议标题
  final String url;          // 协议链接
  final bool isRequired;     // 是否必选
}
```

**iOS 实现的协议列表：**

| 协议名称 | URL（示例） | 是否必选 |
|---------|------------|----------|
| 用户服务协议 | https://www.baidu.com | 是 |
| 隐私政策 | https://example.com/privacy-policy | 是 |

**交互逻辑：**
- 点击勾选框 → 切换选中状态 → 触发回调更新登录按钮状态
- 点击协议文字 → 打开全屏 WebView 显示协议详情
- WebView 支持导航栏（标题 + 关闭按钮）

---

### 3.4 涉及的接口/API

#### 3.4.1 获取验证码

| 字段 | 值 |
|------|---|
| 接口名称 | 获取手机验证码 |
| 路径 | `/phone/getcode` |
| HTTP 方法 | GET |
| 请求参数 | `phone`: String（手机号） |

**请求示例：**
```http
GET /phone/getcode?phone=13800138000
```

**响应示例（成功）：**
```json
{
  "code": 0,
  "message": "验证码已发送",
  "data": {
    "expireTime": 300  // 过期时间（秒）
  }
}
```

**错误码：**
- `1001`: 手机号格式错误
- `1002`: 发送频繁，请稍后再试
- `1003`: 验证码服务异常

---

#### 3.4.2 登录/注册

| 字段 | 值 |
|------|---|
| 接口名称 | 用户登录/注册 |
| 路径 | `/login` |
| HTTP 方法 | POST |
| Content-Type | application/json |

**请求参数：**

| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| phone | String | 是 | 手机号 |
| code | String | 是 | 验证码 |

**请求示例：**
```json
{
  "phone": "13800138000",
  "code": "123456"
}
```

**响应示例（成功）：**
```json
{
  "code": 0,
  "message": "登录成功",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "uid": "1001",
    "userName": "用户_13800138000",
    "phone": "13800138000"
  }
}
```

**错误码：**
- `2001`: 验证码错误
- `2002`: 验证码已过期
- `2003`: 账号已被禁用

---

### 3.5 数据模型

#### 3.5.1 BZUserInfo（用户信息）

```dart
class UserInfo {
  final String token;         // 认证令牌
  final String uid;           // 用户唯一ID
  final String userName;      // 用户名
  final String phone;         // 手机号
  bool isActive;              // 是否激活（默认 true）
  final DateTime loginTime;   // 登录时间
  
  UserInfo({
    required this.token,
    required this.uid,
    required this.userName,
    required this.phone,
    this.isActive = true,
    DateTime? loginTime,
  }) : loginTime = loginTime ?? DateTime.now();
  
  // 从 JSON 构造
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      token: json['token'] as String,
      uid: json['uid'] as String,
      userName: json['userName'] as String,
      phone: json['phone'] as String,
    );
  }
  
  // 转为 JSON
  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'uid': uid,
      'userName': userName,
      'phone': phone,
      'isActive': isActive,
      'loginTime': loginTime.millisecondsSinceEpoch,
    };
  }
}
```

---

### 3.6 特殊注意事项

#### 3.6.1 iOS 特定实现

**自动键盘管理：**
- 使用 `IQKeyboardManagerSwift` 库自动处理键盘遮挡问题
- Flutter 端需要手动实现或使用类似插件（如 `keyboard_actions`）

**文本输入限制：**
- iOS 通过 `UITextFieldDelegate` 的 `shouldChangeCharactersIn` 方法实时限制输入
- Flutter 使用 `TextInputFormatter` 实现相同效果

#### 3.6.2 用户体验细节

**手机号输入优化：**
1. 键盘类型：数字键盘（`keyboardType: .numberPad`）
2. 第一位自动填充"1"或强制以"1"开头
3. 实时格式校验，错误时边框变红

**验证码输入优化：**
1. 键盘类型：数字键盘
2. 输入长度限制：6位
3. 建议：输入完成后自动提交（可选）

**协议文本样式：**
- 前缀文字：`同意`（常规黑色）
- 协议名称：蓝色，可点击
- 连接词：`和`（常规黑色）

示例：`同意《用户服务协议》和《隐私政策》`

#### 3.6.3 安全注意事项

**Token 存储：**
- iOS 使用 `UserDefaults`（不加密）
- Flutter 建议使用 `flutter_secure_storage`（iOS 端存储在 Keychain）

**Token 传递：**
- 所有需要认证的接口，在 HTTP Header 中添加：
  ```
  Authorization: Bearer <token>
  ```

**自动登录风险：**
- 仅在用户主动登出时清除本地信息
- 设备重置或应用卸载会丢失登录状态
- 建议添加生物识别（TouchID/FaceID）增强安全性

#### 3.6.4 登录状态通知

**通知机制：**
- iOS 使用 `NotificationCenter`
- Flutter 使用 `ChangeNotifier` 或状态管理方案（如 Provider、Riverpod）

**通知名称：** `loginStateChanged`

**监听示例（Flutter）：**
```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginManager(),
      child: Consumer<LoginManager>(
        builder: (context, loginManager, child) {
          if (loginManager.isLoggedIn) {
            return MainPage();
          } else {
            return LoginPage();
          }
        },
      ),
    );
  }
}
```

---


## 七、蓝牙设备通信协议（核心）

### 7.1 模块概述

蓝牙设备通信模块是整个应用的**技术核心**，负责与智能录音设备（M1 设备）进行 BLE（Bluetooth Low Energy）通信。该模块包含超过 2200 行代码，实现了从设备扫描、配对绑定、信息查询、配置管理到音频文件同步和实时录音的完整功能链路。

**技术特点：**
- 基于 CoreBluetooth 框架
- 自定义二进制通信协议
- CRC16 数据校验
- 支持多种消息类型（40+ 种）
- 多播代理模式（支持多个监听者）

**业务价值：**
- 实现 App 与硬件设备的无缝对接
- 保证音频数据传输的完整性和可靠性
- 支持设备远程配置和管理

---

### 7.2 核心功能列表

#### 7.2.1 设备连接管理
1. BLE 设备扫描（支持绑定扫描和连接扫描）
2. 设备配对绑定（UUID 握手验证）
3. 自动重连机制
4. 设备解绑
5. 连接状态监听

#### 7.2.2 设备信息查询
1. 获取设备 SN 码
2. 获取电池电量
3. 获取麦克风增益
4. 获取存储空间信息
5. 获取自动关机时间
6. 获取拨动开关状态

#### 7.2.3 设备配置控制
1. 时间同步
2. WiFi 开关控制
3. 设置自动关机时间
4. 监听拨动开关状态变化

#### 7.2.4 文件同步
1. 开启/关闭 BLE 同步状态
2. 获取设备端文件列表
3. 音频文件增量同步
4. CRC16 完整性校验

#### 7.2.5 实时录音
1. 启动实时录音（App 主动 / 设备主动）
2. 暂停/恢复录音
3. 停止录音并保存
4. 实时音频数据接收

---

### 7.3 BLE 通信基础

#### 7.3.1 BLE 服务与特征值

**设备名称：** `M1(BLE)`

**Service UUID：** `00001910-0000-1000-8000-00805f9b34fb`

**Characteristics：**

| 特征值名称 | UUID | 属性 | 用途 |
|-----------|------|------|------|
| Write Characteristic | `00001912-0000-1000-8000-00805f9b34fb` | Write | App → 设备发送指令 |
| Notify Characteristic | `00001911-0000-1000-8000-00805f9b34fb` | Notify | 设备 → App 推送数据 |

**通信模式：**
- App 通过 Write Characteristic 发送指令
- 设备通过 Notify Characteristic 返回响应和推送数据
- 所有通信均为二进制数据（`Data` 类型）

---

#### 7.3.2 消息协议格式

**基本格式：**

```
[消息头 3 字节] + [数据载荷 N 字节]
```

**消息头结构：**

```
Byte 0: 0x01（指令） / 0x02（数据）
Byte 1: 功能码（如 0x04 = 时间同步）
Byte 2: 0x00（保留）
```

**示例：**

- 同步时间请求：`[0x01, 0x04, 0x00, <时间字符串>]`
- 获取电量请求：`[0x01, 0x09, 0x00]`
- 音频数据帧：`[0x02, 0x1C, 0x00, indexL, indexH, <audio data>]`

---

#### 7.3.3 完整消息头定义表

| 功能 | 消息头（Hex） | 说明 |
|------|--------------|------|
| **设备握手** | `01 01 00 00` | 发送 JSON（time + uuid） |
| **握手响应** | `01 01 00 02` | 设备返回验证结果 |
| **时间同步** | `01 04 00` | 附加时间字符串（yyyyMMddHHmmss） |
| **获取电量** | `01 09 00` | 无数据载荷 |
| **获取麦增益** | `01 6A 00` | 无数据载荷 |
| **获取 SN 码** | `01 02 00` | 无数据载荷 |
| **获取存储** | `01 06 00` | 返回 JSON |
| **解绑设备** | `01 05 00` | 附加 1 字节（是否删除音频） |
| **获取自关机** | `01 6C 00` | 返回 2 字节（分钟数） |
| **设置自关机** | `01 6B 00` | 附加 2 字节（分钟数，小端序） |
| **获取开关状态** | `01 6E 00` | 返回 1 字节（0/1） |
| **打开 WiFi** | `01 0A 00` | 返回结果码 |
| **关闭 WiFi** | `01 0B 00` | 返回结果码 |
| **BLE 同步开关** | `01 74 00` | 附加 1 字节（0=关闭，1=开启） |
| **获取文件列表** | `01 1B 00` | 返回多条 JSON |
| **音频同步请求** | `01 1C 00` | 附加文件名 |
| **音频同步停止** | `01 1D 00` | 返回 CRC（2 字节） |
| **音频数据帧** | `02 1C 00` | indexL + indexH + audio |
| **启动实时录音** | `01 14 00` | 返回 JSON |
| **暂停实时录音** | `01 15 00` | 返回结果码 |
| **恢复实时录音** | `01 16 00` | 返回结果码 |
| **停止实时录音** | `01 17 00` | 返回 CRC（2 字节） |
| **实时音频数据** | `02 14 00` | indexL + indexH + audio |

---

### 7.4 详细功能实现

#### 7.4.1 设备扫描与配对

**绑定扫描流程：**

```
1. 调用 startBindScanning()
   ├─ 检查蓝牙状态（必须为 .poweredOn）
   ├─ 开始扫描周围所有 BLE 设备
   ├─ 启动 10 秒倒计时器
   │
2. 发现设备（didDiscover peripheral）
   ├─ 过滤设备名称：必须为 "M1(BLE)"
   ├─ 提取 SN 码（从 advertisementData 的 ManufacturerData）
   ├─ 去重：同一设备只添加一次
   └─ 添加到 bindScanDevices 列表
   │
3. 倒计时结束
   ├─ 停止扫描
   ├─ 返回发现的设备列表给代理
   └─ 用户选择设备后调用 startBinding(device)
```

**绑定流程（Handshake）：**

```
1. App 调用 startBinding(device)
   ├─ 保存设备信息（name, sn, peripheral）
   ├─ 生成 App UUID（随机 UUID）
   └─ 连接设备
   │
2. 连接成功（didConnect）
   ├─ 发现服务（Service UUID）
   ├─ 发现特征值（Write + Notify）
   └─ 订阅 Notify 特征值
   │
3. 订阅成功
   └─ 等待设备主动发送 Handshake 消息
   │
4. 收到设备 UUID（[0x01, 0x01, 0x00, 0x00] + JSON）
   ├─ 解析 JSON：{"uuid": "device_uuid"}
   ├─ 保存 device_uuid
   └─ 发送绑定请求：[0x01, 0x01, 0x00, 0x00] + {"time": timestamp, "uuid": "app_uuid"}
   │
5. 收到绑定响应（[0x01, 0x01, 0x00, 0x02] + resultCode + JSON）
   ├─ resultCode == 0x00 → 绑定成功
   │  ├─ 保存 BindInfo 到内存和 UserDefaults
   │  ├─ 保存设备信息 JSON 到 connectedDeviceInfo
   │  ├─ 更新连接状态 isConnected = true
   │  └─ 通知代理：didCompleteBinding(success: true)
   │
   └─ resultCode != 0x00 → 绑定失败
      ├─ 断开连接
      └─ 通知代理：didCompleteBinding(success: false, error: errorCode)
```

**BindInfo 数据结构：**

```dart
class BindInfo {
  final String deviceName;    // 设备名称（如 "M1(BLE)"）
  final String deviceSn;      // 设备 SN 码
  final String deviceUuid;    // 设备 UUID（首次握手获取）
  final String appUuid;       // App UUID（本地生成）
}
```

---

#### 7.4.2 已绑定设备连接流程

```
1. App 启动 / 用户手动连接
   ├─ 检查是否有保存的 BindInfo
   ├─ 有 → 调用 connect()
   └─ 无 → 提示"未绑定设备"
   │
2. 开始扫描（10 秒超时）
   ├─ 过滤设备名称 == bindInfo.deviceName
   ├─ 过滤 SN 码 == bindInfo.deviceSn
   └─ 匹配成功 → 连接设备
   │
3. 连接成功后
   ├─ 等待设备发送 Handshake
   ├─ 验证 device_uuid == bindInfo.deviceUuid
   │  ├─ 匹配 → 发送验证请求：{"time": timestamp, "uuid": bindInfo.appUuid}
   │  └─ 不匹配 → 断开连接，报错 deviceNotBound
   │
4. 验证成功（resultCode == 0x00）
   ├─ 保存设备信息 JSON
   ├─ isConnected = true
   └─ 通知代理：didUpdateConnectionState(true)
```

---

#### 7.4.3 设备信息查询

**通用流程：**

```
发送查询指令 → 设置标志位（如 isGettingBattery = true）
→ 接收响应 → 解析数据 → 通知代理 → 重置标志位
```

**示例：获取电池电量**

```swift
// Flutter 等价实现
void getBatteryLevel() async {
  if (!isConnected) {
    throw BluetoothError(message: '未连接设备');
  }
  
  _isGettingBattery = true;
  final data = [0x01, 0x09, 0x00];
  await _writeCharacteristic.write(data, withoutResponse: true);
  
  // 等待响应（通过 Notify 接收）
  // 响应格式：[0x01, 0x09, 0x00, batteryLevel]
}

// 接收响应
void _handleBatteryLevelResponse(List<int> data) {
  if (!_isGettingBattery) return;
  _isGettingBattery = false;
  
  if (data.length >= 4) {
    int batteryLevel = data[3];
    _delegate.didGetBatteryLevel(batteryLevel);
  }
}
```

**电量值范围：** 0-100（百分比）

---

**其他查询指令：**

| 功能 | 响应数据格式 | 值范围/说明 |
|------|-------------|-----------|
| 获取麦增益 | `[header, gainValue]` | 0-19 |
| 获取 SN 码 | `[header, <SN 字符串>]` | UTF-8 编码 |
| 获取存储 | `[header, <JSON>]` | `{"total": 16GB, "used": 8GB, "free": 8GB}` |
| 获取自关机时间 | `[header, minutesL, minutesH]` | 小端序，单位：分钟 |
| 获取拨动开关状态 | `[header, status]` | 0=双硅麦，1=骨传导+硅麦 |

---

#### 7.4.4 设备配置操作

**时间同步：**

```
发送数据：[0x01, 0x04, 0x00, <时间字符串>]
时间格式：yyyyMMddHHmmss（14 位数字，如 "20251220153045"）

响应：设备回显相同数据表示成功
```

**设置自动关机：**

```
输入：分钟数（Int）
转换：UInt16 小端序（低字节在前）

示例：设置 30 分钟
  30 → 0x001E → [0x1E, 0x00]
  发送：[0x01, 0x6B, 0x00, 0x1E, 0x00]

响应：设备回显相同数据表示成功
```

**WiFi 控制：**

- 打开 WiFi：`[0x01, 0x0A, 0x00]` → 响应：`[header, 0x00]`（成功）
- 关闭 WiFi：`[0x01, 0x0B, 0x00]` → 响应同上
- 注意：关闭 WiFi 后设备可能需要 5 秒内响应，超时需要处理

---

#### 7.4.5 音频文件同步（核心功能）

**前置条件：**
1. 设备必须已连接
2. 开启 BLE 同步状态：`[0x01, 0x74, 0x00, 0x01]`

**完整流程：**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第一步：开启 BLE 同步
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
openBLESync()
  ├─ 发送：[0x01, 0x74, 0x00, 0x01]
  └─ 响应：回显相同数据 → isBLESyncEnabled = true

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第二步：获取设备文件列表
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
getFileList()
  ├─ 发送：[0x01, 0x1B, 0x00]
  │
  ├─ 响应1：{"FileNum": 5}  // 文件总数
  │
  ├─ 响应2-6：文件详情 JSON（每个文件一条）
  │   {
  │     "file": "20251220_150000.opus",
  │     "size": 1024000,
  │     "date": "2025-12-20 15:00:00"
  │   }
  │
  └─ 完成：返回汇总结果
      {
        "FileNum": 5,
        "List": [...]
      }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第三步：同步单个文件
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
syncAudioFile(fileName: "20251220_150000.opus")
  ├─ 校验文件名：必须以 .opus 结尾
  ├─ 检查本地是否已存在：Documents/<SN>/文件名
  │
  ├─ 发送：[0x01, 0x1C, 0x00, <文件名 UTF-8>]
  │
  ├─ 开始接收数据帧（循环）：
  │   格式：[0x02, 0x1C, 0x00, indexL, indexH, <audio_data>]
  │   
  │   每帧处理：
  │   ├─ 提取 index（2 字节小端序）
  │   ├─ 提取 audio_data（第 6 字节起）
  │   ├─ 追加到文件缓冲区
  │   └─ 更新 CRC16 校验值（累加）
  │
  ├─ 接收停止帧：[0x01, 0x1D, 0x00, crcL, crcH]
  │   ├─ 提取设备端 CRC（2 字节小端序）
  │   ├─ 对比本地计算的 CRC
  │   ├─ 不匹配 → 报错 crcCheckFailed
  │   └─ 匹配 → 保存文件
  │
  └─ 保存文件：Documents/<SN>/<fileName>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第四步：关闭 BLE 同步
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
closeBLESync()
  ├─ 发送：[0x01, 0x74, 0x00, 0x00]
  └─ 响应：回显相同数据 → isBLESyncEnabled = false
```

**CRC16 算法：**

```dart
// Flutter 实现
int crc16Compute(List<int> data, {int initialCrc = 0xFFFF}) {
  int crc = initialCrc;
  
  for (int byte in data) {
    // 交换高低字节
    int high = (crc >> 8) & 0xFF;
    int low = crc & 0xFF;
    crc = (low << 8) | high;
    
    // 异或操作
    crc ^= byte;
    crc ^= ((crc & 0xFF) >> 4);
    crc ^= ((crc << 8) << 4);
    crc ^= (((crc & 0xFF) << 4) << 1);
    
    crc &= 0xFFFF;  // 保持 16 位
  }
  
  return crc;
}
```

**文件存储路径：**

```
Documents/
  └─ <设备 SN 码>/
      ├─ 20251220_150000.opus
      ├─ 20251220_160000.opus
      └─ ...
```

---

#### 7.4.6 实时录音功能

**两种录音模式：**
1. **App 主动启动：** 用户在 App 中点击录音按钮
2. **设备主动启动：** 用户按下设备上的物理按键

**App 主动启动流程：**

```
startRealtimeRecording()
  ├─ 检查是否已连接
  ├─ 检查是否已在录音（不允许重复启动）
  │
  ├─ 发送：[0x01, 0x14, 0x00]
  │
  ├─ 响应：JSON
  │   成功：{"file": "realtime_xxx.opus", "time": "..."}
  │   失败：{"RecordStartErr": "错误原因"}
  │
  ├─ 成功后：
  │   ├─ isRealtimeRecording = true
  │   ├─ 保存启动信息（realtimeStartInfo）
  │   ├─ 确定存储目录：Documents/<SN>/
  │   ├─ 初始化音频缓冲区和 CRC
  │   └─ 开始接收音频数据帧
  │
  └─ 持续接收：[0x02, 0x14, 0x00, indexL, indexH, <audio>]
      ├─ 追加到 realtimeAudioData
      └─ 更新 realtimeAudioCRC
```

**暂停/恢复录音：**

| 操作 | 指令 | 前置条件 | 响应 |
|------|------|---------|------|
| 暂停 | `[0x01, 0x15, 0x00]` | 正在录音 && 未暂停 | `[header, 0x01]` 成功 |
| 恢复 | `[0x01, 0x16, 0x00]` | 正在录音 && 已暂停 | `[header, 0x01]` 成功 |

**停止录音并保存：**

```
stopRealtimeRecording()
  ├─ 发送：[0x01, 0x17, 0x00]
  │
  ├─ 响应：[0x01, 0x17, 0x00, crcL, crcH]
  │   ├─ 提取设备 CRC
  │   ├─ 对比本地 CRC
  │   ├─ 不匹配 → 报错 crcCheckFailed
  │   └─ 匹配 → 保存文件
  │
  ├─ 保存：Documents/<SN>/<fileName>
  │
  └─ 重置状态：
      ├─ isRealtimeRecording = false
      ├─ isRealtimePaused = false
      ├─ 清空音频缓冲区
      └─ 通知代理：didDeviceStopRecording(filePath, startInfo)
```

**设备主动录音的区别：**

- 设备端按下物理按键后，直接推送录音启动通知（App 被动接收）
- App 端仍然按照相同流程接收音频数据
- 停止时，设备端主动推送停止通知
- 通过 `isRealtimeStartByApp` 和 `isRealtimeStopByApp` 标志区分主动方

---

### 7.5 错误处理

#### 7.5.1 错误码表

| 错误码 | 错误名称 | 说明 |
|--------|---------|------|
| 1000 | alreadyConnected | 当前已连接设备 |
| 1001 | noBindInfo | 无绑定信息 |
| 1002 | bluetoothNotEnabled | 蓝牙未开启 |
| 1003 | notConnected | 未连接设备 |
| 1004 | scanTimeout | 扫描超时 |
| 1005 | deviceNotConnected | 设备未连接 |
| 1006 | deviceNotBound | 设备未绑定 |
| 1007 | verificationFailed | 验证失败 |
| 1008 | bluetoothPoweredOff | 蓝牙已关闭 |
| 1009 | bluetoothUnauthorized | 蓝牙未授权 |
| 1010 | bluetoothUnsupported | 设备不支持蓝牙 |
| 1011 | connectionFailed | 连接失败 |
| 1012 | noDevicesFound | 未扫描到设备 |
| 1013 | bleSyncNotEnabled | 设备未处于 BLE 同步状态 |
| 1014 | fileNameEmpty | 文件名不能为空 |
| 1015 | fileNameFormatError | 文件名必须以 .opus 结尾 |
| 1016 | gettingFileList | 正在获取文件列表 |
| 1017 | fileAlreadyExists | 文件已存在 |
| 1018 | audioSyncFailed | 音频同步失败 |
| 1019 | crcCheckFailed | CRC 校验失败 |
| 1024 | cannotGetSN | 无法获取设备 SN 码 |
| 1025 | recordingNotStarted | 设备未处于录音状态 |
| 1026 | recordingNotPaused | 当前录音未暂停 |
| 1027 | recordingAlreadyInProgress | 当前已处于录音状态 |

---

### 7.6 代理方法（BluetoothDeviceManagerDelegate）

**必须实现的关键回调：**

```dart
// Flutter 抽象类
abstract class BluetoothDeviceManagerDelegate {
  // 连接状态变化
  void didUpdateConnectionState(bool isConnected);
  
  // 绑定流程
  void didDiscoverDevices(List<BindDeviceInfo> devices);
  void didCompleteBinding(bool success, {String? error});
  void didSaveBindInfo(BindInfo bindInfo);
  void didRemoveBindInfo();
  
  // 设备信息查询
  void didGetBatteryLevel(int? level, {String? error});
  void didGetSN(String? sn, {String? error});
  void didGetStorage(Map<String, dynamic>? storage, {String? error});
  
  // 文件同步
  void didOpenBLESync(bool success, {String? error});
  void didGetFileList(Map<String, dynamic>? fileList, {String? error});
  
  // 实时录音
  void didDeviceStartRecording(bool success, Map<String, dynamic>? info, {String? error});
  void didDeviceStopRecording(bool success, String? filePath, Map<String, dynamic>? info, {String? error});
  
  // 设备主动断开
  void didDisconnectFromDevice();
}
```

---

### 7.7 特殊注意事项

#### 7.7.1 多播代理模式

**iOS 实现：**
```swift
// 允许多个对象同时监听蓝牙事件
BluetoothDeviceManagerMulticastDelegate.shared.addDelegate(self)
BluetoothDeviceManagerMulticastDelegate.shared.removeDelegate(self)
```

**Flutter 实现建议：**
- 使用 Stream / StreamController
- 或使用 ChangeNotifier + Provider

**示例：**
```dart
class BluetoothDeviceManager with ChangeNotifier {
  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  
  void _updateConnectionState(bool isConnected) {
    _isConnected = isConnected;
    _connectionStateController.add(isConnected);
    notifyListeners();
  }
}
```

---

#### 7.7.2 线程安全

**iOS 使用：**
- `NSHashTable`（弱引用，自动清理）
- `DispatchQueue`（串行队列保证线程安全）

**Flutter 注意：**
- BLE 操作必须在主 Isolate 进行
- 避免在 `compute()` 中操作蓝牙

---

#### 7.7.3 权限要求

**iOS（Info.plist）：**
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>需要蓝牙权限以连接录音设备</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>需要蓝牙权限以连接录音设备</string>
```

**Flutter：**
```yaml
# pubspec.yaml
dependencies:
  flutter_blue_plus: ^1.17.0

# Android: AndroidManifest.xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

---

#### 7.7.4 数据持久化

**BindInfo 存储位置（iOS）：**
- **不存储**：iOS 代码中 BindInfo 仅保存在内存中
- **需要外部管理**：由上层调用者（如 LoginManager）负责持久化

**Flutter 建议：**
```dart
// 使用 shared_preferences 或 Hive
class BindInfoStorage {
  static const _key = 'bind_info';
  
  Future<void> save(BindInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(info.toJson()));
  }
  
  Future<BindInfo?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return null;
    return BindInfo.fromJson(jsonDecode(jsonStr));
  }
  
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
```

---

#### 7.7.5 音频格式说明

**重要：** 同步的音频文件为**裸 Opus 帧数据**，不包含 Ogg 容器。

**播放方式：**
1. 直接使用支持 Opus 的播放器（需要指定 codec）
2. 或在本地封装为 Ogg/Opus 格式后播放

**Ogg 封装参考：**
```dart
// 需要使用第三方库或手动实现 Ogg 封装
// iOS 原代码中移除了 Ogg 封装逻辑，直接保存原始数据
```

---

## 四、首页模块（设备管理与录音文件）

### 4.1 模块概述

首页模块是应用的核心入口,承担设备连接管理、录音文件列表展示、文件同步传输等核心功能。该模块通过蓝牙技术实现与智能录音设备的连接,并提供录音文件的管理界面。

**主要职责:**
- 管理蓝牙录音设备的连接状态
- 展示录音文件列表,按时间分组
- 提供文件传输进度监控与快传功能
- 支持录音文件的查看、删除等操作
- 处理设备未连接时的引导流程

**涉及的视图控制器:**
- `BZHomeViewController`: 首页主控制器
- `BZSearchDeviceViewController`: 设备搜索与连接页面

**核心UI组件:**
- `BZTransferCardView`: 文件传输卡片视图
- `BZQuickTransferProgressView`: 快传进度弹窗

---

### 4.2 核心功能列表

| 功能模块 | 功能点 | 优先级 |
|---------|--------|--------|
| **设备管理** | 蓝牙设备自动连接 | P0 |
| | 设备连接状态显示 | P0 |
| | 设备搜索与绑定 | P0 |
| | 设备连接状态实时更新 | P1 |
| | 历史设备列表 | P2 |
| **录音列表** | 按日期分组展示录音 | P0 |
| | 录音文件类型标识(语音/电话) | P0 |
| | 录音状态显示(已入库/传输中/总结中) | P0 |
| | 下拉刷新列表 | P1 |
| | 空状态提示 | P1 |
| | 滑动删除录音 | P1 |
| **文件传输** | 文件传输进度显示 | P0 |
| | 快传功能 | P1 |
| | 传输速度显示 | P1 |
| | 暂停/结束传输 | P2 |

---

### 4.3 详细功能描述

#### 4.3.1 设备连接管理

**业务流程:**

1. **应用启动时自动连接**
   - 从本地存储(`UserDefaults`)加载绑定信息
   - 检查是否存在已绑定设备
   - 如果有绑定设备,自动启动蓝牙扫描并尝试连接
   - 连接状态通过多播代理模式实时通知所有监听者

2. **设备状态显示逻辑**
   - **未连接状态**: 显示灰色图标 `no_reconnect`,文字"未连接"
   - **已连接状态**: 显示绿色图标 `device_reconnected`,文字"已连接",文字颜色变为成功绿色
   - 状态视图可点击,点击后跳转到设备搜索页面

3. **设备绑定信息持久化**
   - 绑定信息使用JSON格式存储在`UserDefaults`
   - 存储键为 `"Bind_List"`
   - 数据结构为 `BindInfo` 对象,包含设备名称、SN序列号等信息

**iOS特定实现:**
- 使用CoreBluetooth框架进行蓝牙设备扫描与连接
- 采用多播代理模式(`BluetoothDeviceManagerMulticastDelegate`)避免代理冲突
- 在`viewWillAppear`时注册代理,`viewWillDisappear`时移除代理,避免内存泄漏

**Flutter迁移建议:**
- Android使用 `flutter_blue_plus` 或类似蓝牙插件
- 实现类似的单例管理器模式管理蓝牙连接
- 使用Stream或ChangeNotifier实现状态变化的响应式更新

---

#### 4.3.2 设备搜索与绑定

**用户交互流程:**

1. **进入搜索页面**
   - 点击首页设备状态区域
   - 页面顶部显示搜索动画和提示文字"扫描附近设备"
   - 自动开始10秒倒计时扫描

2. **设备列表展示**
   - 列表分为两个区域:
     - **历史设备区域**: 显示曾经连接过的设备(模拟数据)
     - **可用设备区域**: 显示扫描到的可连接设备
   - 每个设备显示:设备图标、设备名称、SN序列号、连接按钮

3. **空状态处理**
   - 如果可用设备列表为空,显示空状态提示"暂无可用设备"
   - 页面底部提供使用提示:
     - 提示1: 打开设备电源(长按录音按键开机)
     - 提示2: 确保手机蓝牙已开启

4. **设备连接流程**
   - 点击设备的"连接"按钮
   - 显示连接中提示
   - 连接成功后自动返回首页,状态更新为"已连接"
   - 绑定信息保存到本地存储

**扫描机制:**
- 扫描时长为10秒倒计时
- 支持手动点击刷新按钮重新扫描
- 扫描期间显示Loading提示
- 如果扫描超时未找到设备,使用模拟数据展示UI

**iOS特定实现:**
- 使用Timer实现倒计时功能
- 扫描结果通过代理回调 `didDiscoverDevices` 返回
- 使用 `CBPeripheral` 对象表示蓝牙设备,为避免内存问题,转换为`DeviceItem`结构体存储

---

#### 4.3.3 录音文件列表

**数据结构:**

```swift
struct RecordingItem {
    let id: String              // 唯一标识
    let title: String           // 录音标题
    let date: String            // 录音日期 (yyyy-MM-dd)
    let time: String            // 录音时间 (HH:mm)
    let duration: String        // 录音时长 (如"45分钟")
    let type: RecordingType     // 类型: voice(语音) / phone(电话)
    let status: RecordingStatus // 状态: completed/uploading/summarizing/none
}
```

**状态类型说明:**

| 状态 | 含义 | 显示文案 | 图标 | 颜色 |
|------|------|---------|------|------|
| `none` | 普通录音文件 | 无状态标签 | - | - |
| `completed` | 已同步并入库 | "已入库" | `store_suc` | 绿色(成功色) |
| `uploading` | 正在上传传输 | "正在传输..." | 上箭头圆圈 | 蓝色(主题色) |
| `summarizing` | AI总结处理中 | "总结中..." | `summarying` | 蓝色(主题色) |

**列表展示规则:**

1. **分组逻辑**
   - 按日期分组,如"今天"、"2025年10月"等
   - 每个分组有独立的Section Header
   - Section内按时间倒序排列

2. **单元格布局**
   - 卡片式设计,白色背景,圆角16px
   - 顶部显示录音标题(粗体16号字)
   - 左下角显示类型图标 + 日期时间
   - 右下角显示录音时长
   - 右上角显示状态标签(如果有)

3. **类型图标区分**
   - 语音输入: `file_type_audio` 图标
   - 电话录音: `file_type_phone` 图标

**交互操作:**

1. **下拉刷新**
   - 使用MJRefresh库实现
   - 刷新文案: "下拉刷新" / "松开刷新" / "正在刷新..."
   - 刷新成功后显示Toast提示
   - 隐藏最后更新时间标签

2. **点击事件**
   - 点击录音Item跳转到详情页(待实现)

3. **滑动删除**
   - 左滑显示红色删除按钮,自定义图标 `file_delete`
   - 点击删除后弹出二次确认弹窗
   - 确认标题: "删除后无法恢复"
   - 确认内容: "此文件将永久删除,无法找回,确定继续?"
   - 取消按钮: "取消" / 确认按钮: "永久删除"
   - 删除后从数据源移除,如果Section为空则删除整个Section
   - 使用fade动画效果

**空状态处理:**
- 当所有Section的items都为空时显示空状态
- 空状态图标: `home_empty`
- 提示文案: "暂无录音文件,快来记录吧~"
- 隐藏TableView,显示空状态视图

**iOS特定实现:**
- 使用UITableView的分组样式(grouped)
- Cell高度固定为84px,Header高度为28px
- iOS 11+的滑动操作API: `trailingSwipeActionsConfigurationForRowAt`
- Cell使用自定义视图,背景透明,内部添加圆角容器视图

---

### 4.4 数据模型

#### 4.4.1 RecordingItem(录音条目)

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `id` | String | 唯一标识符 | "1" |
| `title` | String | 录音标题 | "用户体验研究访谈" |
| `date` | String | 录音日期 | "2025-11-23" |
| `time` | String | 录音时间 | "15:02" |
| `duration` | String | 录音时长 | "45分钟" |
| `type` | RecordingType | 录音类型枚举 | `.voice` / `.phone` |
| `status` | RecordingStatus | 录音状态枚举 | `.completed` / `.uploading` 等 |

#### 4.4.2 DeviceItem(设备信息)

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `name` | String | 设备名称 | "百智录音卡 T240" |
| `sn` | String | 设备序列号 | "352401241100999" |
| `isHistory` | Bool | 是否为历史设备 | true / false |

---

## 五、个人中心模块

### 5.1 模块概述

个人中心模块是百智应用的核心功能区域之一,为用户提供个人信息展示、设备管理、客户支持等服务入口。该模块包含三个主要界面:个人中心主界面、我的设备界面、反馈提交界面。

### 5.2 核心功能列表

- 用户信息展示(头像、手机号、用户类型)
- 我的设备入口
- 设备连接状态实时显示
- 设备信息查看(设备名称、SN码、电量、存储空间)
- 自动入库开关设置
- 设备解绑
- 问题反馈提交(文字+图片)
- 客服联系方式展示
- 用户协议和隐私政策查看
- 退出登录

### 5.3 特殊注意事项

- 设备信息从 `UserDefaults` 的 `"Bind_List"` 键读取
- 连接状态通过蓝牙设备管理器实时监测
- 代理注册与移除必须在页面显示/消失时执行
- 退出登录调用 `BZLoginManager.shared.logout()` 清除登录状态
- Token 建议后续改用 Keychain 存储提高安全性

---

## 六、录音模块

### 6.1 模块概述

录音模块负责实时录音控制与管理，通过蓝牙与硬件设备通信，实现远程录音控制、实时音频数据接收、本地文件保存等功能。

### 6.2 核心功能列表

1. 启动实时录音(APP 主动 / 设备主动)
2. 停止实时录音
3. 暂停录音
4. 恢复录音
5. 录音状态查询
6. 设备端主动录音监听

### 6.3 关键技术点

**CRC 校验算法:**
- 采用标准 CRC-16 算法
- 初始值为 `0xFFFF`
- 支持累积计算(适合流式数据)

**文件存储路径:**
- `Documents/<设备SN码>/<文件名>.opus`
- 音频格式: Opus (无 Ogg 容器封装)

**蓝牙指令集:**
- 启动: `0x01 0x14 0x00`
- 暂停: `0x01 0x15 0x00`
- 恢复: `0x01 0x16 0x00`
- 停止: `0x01 0x17 0x00`

---

## 八、数据模型汇总

### 8.1 用户相关

#### BZUserInfo
```dart
class UserInfo {
  final String token;         // 认证令牌
  final String uid;           // 用户ID
  final String userName;      // 用户名
  final String phone;         // 手机号
  bool isActive;              // 是否激活
  final DateTime loginTime;   // 登录时间
}
```

### 8.2 设备相关

#### BindInfo
```dart
class BindInfo {
  final String deviceName;    // 设备名称
  final String deviceSn;      // 设备SN码
  final String deviceUuid;    // 设备UUID
  final String appUuid;       // App UUID
}
```

#### BluetoothError
```dart
class BluetoothError {
  final int code;             // 错误码(1000-1038)
  final String message;       // 错误描述
}
```

### 8.3 录音相关

#### RecordingItem
```dart
class RecordingItem {
  final String id;            // 唯一标识
  final String title;         // 录音标题
  final String date;          // 录音日期
  final String time;          // 录音时间
  final String duration;      // 录音时长
  final RecordingType type;   // voice / phone
  final RecordingStatus status; // completed / uploading / summarizing
}
```

---

## 九、API 接口文档

### 9.1 认证接口

#### 获取验证码

| 字段 | 值 |
|------|---|
| 路径 | `/phone/getcode` |
| 方法 | GET |
| 参数 | `phone`: 手机号 |

**响应示例:**
```json
{
  "code": 0,
  "message": "验证码已发送",
  "data": {
    "expireTime": 300
  }
}
```

#### 登录/注册

| 字段 | 值 |
|------|---|
| 路径 | `/login` |
| 方法 | POST |
| Content-Type | application/json |

**请求体:**
```json
{
  "phone": "13800138000",
  "code": "123456"
}
```

**响应示例:**
```json
{
  "code": 0,
  "message": "登录成功",
  "data": {
    "token": "eyJhbG...",
    "uid": "1001",
    "userName": "用户_13800138000",
    "phone": "13800138000"
  }
}
```

### 9.2 反馈接口(待实现)

| 字段 | 值 |
|------|---|
| 路径 | `/api/feedback/submit` |
| 方法 | POST |
| Content-Type | application/json |

**请求体:**
```json
{
  "content": "问题说明",
  "images": ["图片URL1", "图片URL2"],
  "uid": "用户ID",
  "deviceInfo": {}
}
```

---

## 十、特殊注意事项

### 10.1 蓝牙通信

**权限要求(iOS):**
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>需要蓝牙权限以连接录音设备</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>需要蓝牙权限以连接录音设备</string>
```

**Flutter 配置:**
```yaml
dependencies:
  flutter_blue_plus: ^1.17.0
```

**UUID 定义:**
- Service: `00001910-0000-1000-8000-00805f9b34fb`
- Write: `00001912-0000-1000-8000-00805f9b34fb`
- Notify: `00001911-0000-1000-8000-00805f9b34fb`

### 10.2 数据存储

**UserDefaults 存储键:**
- `current_token` - 登录令牌
- `current_uid` - 用户ID
- `current_user_name` - 用户名
- `current_phone` - 手机号
- `login_time` - 登录时间
- `is_active` - 激活状态
- `Bind_List` - 设备绑定信息(JSON)
- `AutoSync_Enabled` - 自动入库开关

**音频文件存储:**
- 路径: `Documents/<设备SN>/文件名.opus`
- 格式: Opus (原始帧数据，无 Ogg 容器)

### 10.3 线程安全

**蓝牙回调:**
- 所有 UI 更新必须在主线程执行
- 使用 `DispatchQueue.main.async` 切换线程

**代理管理:**
- 页面显示时注册代理
- 页面消失时移除代理
- 使用 `[weak self]` 防止循环引用

### 10.4 Token 管理

**当前实现:**
- 存储在 `UserDefaults`(不加密)

**建议改进:**
- iOS: 使用 Keychain
- Flutter: 使用 `flutter_secure_storage`

**有效期:**
- 15 天自动过期
- 过期后需重新登录

### 10.5 CRC 校验

**算法:**
- CRC-16 标准算法
- 初始值: `0xFFFF`
- 累积计算支持

**应用场景:**
- 音频文件同步
- 实时录音数据传输

### 10.6 错误处理

**蓝牙错误码范围:**
- 1000-1010: 连接和权限类错误
- 1011-1020: 文件同步类错误
- 1021-1038: 实时录音类错误

**网络错误类型:**
- `serverError`: 服务器错误
- `parsingError`: 解析错误
- `noInternet`: 无网络连接
- `timeout`: 请求超时

---

## 十一、平台差异说明

### 11.1 蓝牙功能

| 功能 | iOS | Android/Flutter |
|------|-----|-----------------|
| 蓝牙权限 | Info.plist 配置 | AndroidManifest.xml + 运行时权限 |
| 蓝牙扫描 | CoreBluetooth | flutter_blue_plus |
| 后台蓝牙 | 需配置 UIBackgroundModes | 需配置 Service |

**Flutter 蓝牙插件:**
```yaml
flutter_blue_plus: ^1.17.0
```

**Android 权限:**
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### 11.2 数据存储

| 存储类型 | iOS | Flutter |
|---------|-----|---------|
| 简单数据 | UserDefaults | shared_preferences |
| 安全数据 | Keychain | flutter_secure_storage |
| 文件存储 | Documents | path_provider |

### 11.3 图片选择

| 功能 | iOS | Flutter |
|------|-----|---------|
| 图片选择器 | PHPicker (iOS 14+) / UIImagePicker | image_picker |
| 相机权限 | Info.plist 配置 | AndroidManifest.xml + 运行时权限 |

### 11.4 网络请求

| 框架 | iOS | Flutter |
|------|-----|---------|
| HTTP 库 | Alamofire | dio / http |
| 异步处理 | async/await | Future / async/await |
| 拦截器 | RequestInterceptor | Interceptors |

### 11.5 UI 组件

| 组件 | iOS | Flutter |
|------|-----|---------|
| 列表 | UITableView | ListView |
| 刷新 | MJRefresh | RefreshIndicator |
| Toast | Toast-Swift | fluttertoast |
| 键盘 | IQKeyboardManager | keyboard_actions |
| 布局 | SnapKit | Widgets |

---

## 附录

### A. 目录结构

```
BaiZhi/
├── Application/              # 应用基础设施
│   ├── Base/                # 基类
│   ├── Common/              # 通用组件
│   └── Tabbar/              # 标签栏
├── Modules/                 # 功能模块
│   ├── Home/               # 首页
│   ├── Login/              # 登录
│   ├── Profile/            # 个人中心
│   └── Record/             # 录音
├── Manager/                # 业务管理器
│   ├── Networking/         # 网络
│   ├── Login/              # 登录管理
│   └── BluetoothDeviceManager/  # 蓝牙
└── Utils/                  # 工具类
```

### B. 依赖版本

| 库 | 版本 | 用途 |
|----|------|------|
| Alamofire | 5.10.2 | 网络请求 |
| SwiftyJSON | 5.0.0 | JSON 解析 |
| SnapKit | 5.6.0 | 自动布局 |
| Kingfisher | 7.6.0 | 图片加载 |
| Toast-Swift | 5.0.0 | 消息提示 |
| IQKeyboardManagerSwift | 6.5.0 | 键盘管理 |
| MJRefresh | 3.7.5 | 下拉刷新 |

### C. 颜色规范

| 名称 | Hex | 用途 |
|------|-----|------|
| 主背景 | #F8F9FE | 页面背景色 |
| 文字标题 | #262626 | 标题文字 |
| 文字正常 | #8C8C8C | 普通文字 |
| 主蓝色 | #165DFF | 主题色、按钮 |
| 成功绿 | #34C759 | 成功状态 |
| 错误红 | #F53F3F | 错误、删除 |

### D. 常见问题

**Q: 蓝牙连接失败怎么办?**
A: 检查蓝牙权限、设备电量、距离范围。查看错误码确定具体原因。

**Q: 音频文件无法播放?**
A: 确认格式为 Opus，使用支持 Opus 的播放器。如需封装为 Ogg/Opus 再播放。

**Q: Token 过期如何处理?**
A: 自动登录检测到过期后返回登录页，用户需重新登录。

**Q: CRC 校验失败怎么办?**
A: 表示数据传输不完整，建议重新同步文件。检查蓝牙信号强度。

**Q: 设备端主动录音如何处理?**
A: 通过代理方法 `didDeviceStartRecording` 和 `didDeviceStopRecording` 接收通知，自动保存文件。

---

## 文档变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|---------|------|
| v1.0 | 2025-12-20 | 初始版本，完整需求文档 | Claude Code |

---

**文档结束**


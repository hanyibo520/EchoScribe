/// 用户信息模型
///
/// 对应后端登录接口返回的用户数据
class UserInfo {
  /// 认证令牌
  final String token;

  /// 用户唯一 ID
  final String uid;

  /// 用户名
  final String userName;

  /// 手机号
  final String phone;

  /// 是否激活（默认 true）
  bool isActive;

  /// 登录时间
  final DateTime loginTime;

  /// 创建用户信息实例
  UserInfo({
    required this.token,
    required this.uid,
    required this.userName,
    required this.phone,
    this.isActive = true,
    DateTime? loginTime,
  }) : loginTime = loginTime ?? DateTime.now();

  /// 从 JSON 构造用户信息
  ///
  /// 示例 JSON:
  /// ```json
  /// {
  ///   "token": "eyJhbG...",
  ///   "uid": "1001",
  ///   "userName": "用户_13800138000",
  ///   "phone": "13800138000"
  /// }
  /// ```
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      token: json['token'] as String,
      uid: json['uid'] as String,
      userName: json['userName'] as String,
      phone: json['phone'] as String,
      isActive: json['isActive'] as bool? ?? true,
      loginTime: json['loginTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['loginTime'] as int)
          : null,
    );
  }

  /// 转换为 JSON
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

  /// Token 是否过期（15 天）
  bool get isTokenExpired {
    final now = DateTime.now();
    final difference = now.difference(loginTime);
    return difference.inDays >= 15;
  }

  /// 复制并更新字段
  UserInfo copyWith({
    String? token,
    String? uid,
    String? userName,
    String? phone,
    bool? isActive,
    DateTime? loginTime,
  }) {
    return UserInfo(
      token: token ?? this.token,
      uid: uid ?? this.uid,
      userName: userName ?? this.userName,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      loginTime: loginTime ?? this.loginTime,
    );
  }

  @override
  String toString() {
    return 'UserInfo{uid: $uid, userName: $userName, phone: $phone, isActive: $isActive}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserInfo && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}

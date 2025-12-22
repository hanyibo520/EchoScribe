/// 设备绑定信息模型
///
/// 用于存储蓝牙设备的绑定信息
class BindInfo {
  /// 设备名称（如 "M1(BLE)"）
  final String deviceName;

  /// 设备序列号（SN 码）
  final String deviceSn;

  /// 设备 UUID（首次握手时从设备获取）
  final String deviceUuid;

  /// App UUID（本地生成）
  final String appUuid;

  /// 创建设备绑定信息实例
  BindInfo({
    required this.deviceName,
    required this.deviceSn,
    required this.deviceUuid,
    required this.appUuid,
  });

  /// 从 JSON 构造设备绑定信息
  ///
  /// 示例 JSON:
  /// ```json
  /// {
  ///   "deviceName": "M1(BLE)",
  ///   "deviceSn": "352401241100999",
  ///   "deviceUuid": "uuid-from-device",
  ///   "appUuid": "uuid-from-app"
  /// }
  /// ```
  factory BindInfo.fromJson(Map<String, dynamic> json) {
    return BindInfo(
      deviceName: json['deviceName'] as String,
      deviceSn: json['deviceSn'] as String,
      deviceUuid: json['deviceUuid'] as String,
      appUuid: json['appUuid'] as String,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'deviceName': deviceName,
      'deviceSn': deviceSn,
      'deviceUuid': deviceUuid,
      'appUuid': appUuid,
    };
  }

  /// 复制并更新字段
  BindInfo copyWith({
    String? deviceName,
    String? deviceSn,
    String? deviceUuid,
    String? appUuid,
  }) {
    return BindInfo(
      deviceName: deviceName ?? this.deviceName,
      deviceSn: deviceSn ?? this.deviceSn,
      deviceUuid: deviceUuid ?? this.deviceUuid,
      appUuid: appUuid ?? this.appUuid,
    );
  }

  @override
  String toString() {
    return 'BindInfo{deviceName: $deviceName, deviceSn: $deviceSn}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BindInfo &&
        other.deviceSn == deviceSn &&
        other.deviceUuid == deviceUuid;
  }

  @override
  int get hashCode => deviceSn.hashCode ^ deviceUuid.hashCode;
}

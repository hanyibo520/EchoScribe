// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '百智';

  @override
  String get login => '登录';

  @override
  String get phoneNumber => '手机号';

  @override
  String get verificationCode => '验证码';

  @override
  String get getCode => '获取验证码';

  @override
  String get loginButton => '登录';

  @override
  String get logout => '退出登录';

  @override
  String get home => '首页';

  @override
  String get mine => '我的';

  @override
  String get deviceConnected => '已连接';

  @override
  String get deviceDisconnected => '未连接';

  @override
  String get scanningDevices => '扫描附近设备';

  @override
  String get noDevicesFound => '暂无可用设备';

  @override
  String get deleteRecording => '删除录音';

  @override
  String get deleteConfirmTitle => '删除后无法恢复';

  @override
  String get deleteConfirmMessage => '此文件将永久删除，无法找回，确定继续？';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get delete => '删除';

  @override
  String get uploading => '正在传输...';

  @override
  String get summarizing => '总结中...';

  @override
  String get completed => '已入库';

  @override
  String get noRecordings => '暂无录音文件，快来记录吧~';

  @override
  String get pullToRefresh => '下拉刷新';

  @override
  String get releaseToRefresh => '松开刷新';

  @override
  String get refreshing => '正在刷新...';

  @override
  String get phoneFormatError => '手机号格式错误';

  @override
  String get codeFormatError => '验证码格式错误';

  @override
  String get codeSent => '验证码已发送';

  @override
  String get codeExpired => '验证码已过期';

  @override
  String get loginSuccess => '登录成功';

  @override
  String get loginFailed => '登录失败';

  @override
  String get agreementRequired => '请先同意用户协议';

  @override
  String get userAgreement => '用户服务协议';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get agreeAnd => '同意';

  @override
  String get and => '和';
}

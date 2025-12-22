import 'package:get/get.dart';

/// 登录页面视图模型
/// 
/// 使用 GetX 管理登录页面的状态和业务逻辑
class LoginViewModel extends GetxController {
  // 手机号
  final RxString phone = ''.obs;
  
  // 验证码
  final RxString code = ''.obs;
  
  // 获取验证码倒计时（秒）
  final RxInt countdown = 0.obs;
  
  // 是否正在获取验证码
  final RxBool isGettingCode = false.obs;
  
  // 是否正在登录
  final RxBool isLoggingIn = false.obs;

  /// 更新手机号
  void updatePhone(String value) {
    phone.value = value;
  }

  /// 更新验证码
  void updateCode(String value) {
    code.value = value;
  }

  /// 获取验证码
  Future<void> getVerificationCode() async {
    if (phone.value.isEmpty) {
      // TODO: 显示提示：请输入手机号
      return;
    }
    
    if (phone.value.length != 11) {
      // TODO: 显示提示：手机号格式不正确
      return;
    }
    
    if (countdown.value > 0) {
      // 倒计时中，不允许重复获取
      return;
    }
    
    try {
      isGettingCode.value = true;
      // TODO: 调用获取验证码接口
      // await _loginService.getVerificationCode(phone.value);
      
      // 开始倒计时（60秒）
      countdown.value = 60;
      _startCountdown();
    } catch (e) {
      // TODO: 显示错误提示
    } finally {
      isGettingCode.value = false;
    }
  }

  /// 开始倒计时
  void _startCountdown() {
    if (countdown.value > 0) {
      Future.delayed(const Duration(seconds: 1), () {
        countdown.value--;
        if (countdown.value > 0) {
          _startCountdown();
        }
      });
    }
  }

  /// 登录
  Future<void> login() async {
    if (phone.value.isEmpty) {
      // TODO: 显示提示：请输入手机号
      return;
    }
    
    if (phone.value.length != 11) {
      // TODO: 显示提示：手机号格式不正确
      return;
    }
    
    if (code.value.isEmpty) {
      // TODO: 显示提示：请输入验证码
      return;
    }
    
    if (code.value.length != 6) {
      // TODO: 显示提示：验证码格式不正确
      return;
    }
    
    try {
      isLoggingIn.value = true;
      // TODO: 调用登录接口
      // await _loginService.login(phone.value, code.value);
      
      // TODO: 登录成功后跳转
    } catch (e) {
      // TODO: 显示错误提示
    } finally {
      isLoggingIn.value = false;
    }
  }

  /// 验证手机号格式
  bool get isPhoneValid => phone.value.length == 11;

  /// 验证验证码格式
  bool get isCodeValid => code.value.length == 6;

  /// 是否可以登录
  bool get canLogin => isPhoneValid && isCodeValid && !isLoggingIn.value;
}


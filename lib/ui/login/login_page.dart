import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../core/themes/colors.dart';
import 'view_model/login_vm.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final LoginViewModel viewModel;
  late final TextEditingController phoneController;
  late final TextEditingController codeController;

  @override
  void initState() {
    super.initState();
    // 初始化 ViewModel
    viewModel = Get.put(LoginViewModel());
    
    // 创建 TextEditingController
    phoneController = TextEditingController();
    codeController = TextEditingController();
    
    // 监听 ViewModel 状态变化，同步到输入框（用于外部设置值的情况）
    ever(viewModel.phone, (value) {
      if (phoneController.text != value) {
        phoneController.text = value;
      }
    });
    
    ever(viewModel.code, (value) {
      if (codeController.text != value) {
        codeController.text = value;
      }
    });
  }

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.wiseNoteColorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          '登录',
          style: TextStyle(
            color: colorScheme.primaryTitle,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              // 手机号输入框
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                onChanged: viewModel.updatePhone,
                decoration: InputDecoration(
                  labelText: '手机号',
                  hintText: '请输入手机号',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  labelStyle: TextStyle(color: colorScheme.secondaryTitle),
                  hintStyle: TextStyle(color: colorScheme.secondaryTitle),
                ),
                style: TextStyle(color: colorScheme.primaryTitle),
              ),
              const SizedBox(height: 20),
              // 验证码输入框和获取验证码按钮
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: viewModel.updateCode,
                      decoration: InputDecoration(
                        labelText: '验证码',
                        hintText: '请输入验证码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        labelStyle: TextStyle(color: colorScheme.secondaryTitle),
                        hintStyle: TextStyle(color: colorScheme.secondaryTitle),
                      ),
                      style: TextStyle(color: colorScheme.primaryTitle),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Obx(() => SizedBox(
                    width: 100,
                    child: OutlinedButton(
                      onPressed: viewModel.countdown.value > 0 || viewModel.isGettingCode.value
                          ? null
                          : viewModel.getVerificationCode,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colorScheme.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        viewModel.countdown.value > 0
                            ? '${viewModel.countdown.value}秒'
                            : '获取验证码',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )),
                ],
              ),
              const Spacer(),
              // 登录按钮
              Obx(() => SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: viewModel.canLogin && !viewModel.isLoggingIn.value
                      ? viewModel.login
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    disabledBackgroundColor: colorScheme.primary.withOpacity(0.5),
                    disabledForegroundColor: colorScheme.onPrimary.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: viewModel.isLoggingIn.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '登录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              )),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

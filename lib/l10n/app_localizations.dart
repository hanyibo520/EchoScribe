import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 应用名称
  ///
  /// In zh, this message translates to:
  /// **'百智'**
  String get appName;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @phoneNumber.
  ///
  /// In zh, this message translates to:
  /// **'手机号'**
  String get phoneNumber;

  /// No description provided for @verificationCode.
  ///
  /// In zh, this message translates to:
  /// **'验证码'**
  String get verificationCode;

  /// No description provided for @getCode.
  ///
  /// In zh, this message translates to:
  /// **'获取验证码'**
  String get getCode;

  /// No description provided for @loginButton.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginButton;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @home.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get home;

  /// No description provided for @mine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get mine;

  /// No description provided for @deviceConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get deviceConnected;

  /// No description provided for @deviceDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get deviceDisconnected;

  /// No description provided for @scanningDevices.
  ///
  /// In zh, this message translates to:
  /// **'扫描附近设备'**
  String get scanningDevices;

  /// No description provided for @noDevicesFound.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用设备'**
  String get noDevicesFound;

  /// No description provided for @deleteRecording.
  ///
  /// In zh, this message translates to:
  /// **'删除录音'**
  String get deleteRecording;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除后无法恢复'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'此文件将永久删除，无法找回，确定继续？'**
  String get deleteConfirmMessage;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @uploading.
  ///
  /// In zh, this message translates to:
  /// **'正在传输...'**
  String get uploading;

  /// No description provided for @summarizing.
  ///
  /// In zh, this message translates to:
  /// **'总结中...'**
  String get summarizing;

  /// No description provided for @completed.
  ///
  /// In zh, this message translates to:
  /// **'已入库'**
  String get completed;

  /// No description provided for @noRecordings.
  ///
  /// In zh, this message translates to:
  /// **'暂无录音文件，快来记录吧~'**
  String get noRecordings;

  /// No description provided for @pullToRefresh.
  ///
  /// In zh, this message translates to:
  /// **'下拉刷新'**
  String get pullToRefresh;

  /// No description provided for @releaseToRefresh.
  ///
  /// In zh, this message translates to:
  /// **'松开刷新'**
  String get releaseToRefresh;

  /// No description provided for @refreshing.
  ///
  /// In zh, this message translates to:
  /// **'正在刷新...'**
  String get refreshing;

  /// No description provided for @phoneFormatError.
  ///
  /// In zh, this message translates to:
  /// **'手机号格式错误'**
  String get phoneFormatError;

  /// No description provided for @codeFormatError.
  ///
  /// In zh, this message translates to:
  /// **'验证码格式错误'**
  String get codeFormatError;

  /// No description provided for @codeSent.
  ///
  /// In zh, this message translates to:
  /// **'验证码已发送'**
  String get codeSent;

  /// No description provided for @codeExpired.
  ///
  /// In zh, this message translates to:
  /// **'验证码已过期'**
  String get codeExpired;

  /// No description provided for @loginSuccess.
  ///
  /// In zh, this message translates to:
  /// **'登录成功'**
  String get loginSuccess;

  /// No description provided for @loginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败'**
  String get loginFailed;

  /// No description provided for @agreementRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先同意用户协议'**
  String get agreementRequired;

  /// No description provided for @userAgreement.
  ///
  /// In zh, this message translates to:
  /// **'用户服务协议'**
  String get userAgreement;

  /// No description provided for @privacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get privacyPolicy;

  /// No description provided for @agreeAnd.
  ///
  /// In zh, this message translates to:
  /// **'同意'**
  String get agreeAnd;

  /// No description provided for @and.
  ///
  /// In zh, this message translates to:
  /// **'和'**
  String get and;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

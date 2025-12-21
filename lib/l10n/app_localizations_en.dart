// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'WiseNote';

  @override
  String get login => 'Login';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get verificationCode => 'Verification Code';

  @override
  String get getCode => 'Get Code';

  @override
  String get loginButton => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get home => 'Home';

  @override
  String get mine => 'Mine';

  @override
  String get deviceConnected => 'Connected';

  @override
  String get deviceDisconnected => 'Disconnected';

  @override
  String get scanningDevices => 'Scanning devices';

  @override
  String get noDevicesFound => 'No devices found';

  @override
  String get deleteRecording => 'Delete Recording';

  @override
  String get deleteConfirmTitle => 'Cannot be recovered after deletion';

  @override
  String get deleteConfirmMessage =>
      'This file will be permanently deleted and cannot be recovered. Are you sure?';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get delete => 'Delete';

  @override
  String get uploading => 'Uploading...';

  @override
  String get summarizing => 'Summarizing...';

  @override
  String get completed => 'Completed';

  @override
  String get noRecordings => 'No recordings yet, start recording now~';

  @override
  String get pullToRefresh => 'Pull to refresh';

  @override
  String get releaseToRefresh => 'Release to refresh';

  @override
  String get refreshing => 'Refreshing...';

  @override
  String get phoneFormatError => 'Invalid phone number format';

  @override
  String get codeFormatError => 'Invalid verification code format';

  @override
  String get codeSent => 'Verification code sent';

  @override
  String get codeExpired => 'Verification code expired';

  @override
  String get loginSuccess => 'Login successful';

  @override
  String get loginFailed => 'Login failed';

  @override
  String get agreementRequired => 'Please agree to the user agreement first';

  @override
  String get userAgreement => 'User Agreement';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get agreeAnd => 'Agree to';

  @override
  String get and => 'and';
}

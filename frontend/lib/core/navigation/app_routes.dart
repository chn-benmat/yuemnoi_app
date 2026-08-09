import 'package:flutter/material.dart';

import '../../features/auth/presentation/pages/change_password.dart';
import '../../features/auth/presentation/pages/forget_password.dart';
import '../../features/auth/presentation/pages/login.dart';
import '../../features/auth/presentation/pages/one_time_verification.dart';
import '../../features/auth/presentation/pages/register.dart';
import '../../features/home/presentation/pages/home.dart';

abstract final class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const otpVerification = '/otp-verification';
  static const changePassword = '/change-password';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return _fadeRoute<void>(settings, const LoginScreen());
      case home:
        return _fadeRoute<void>(settings, const HomeScreen());
      case register:
        return _materialRoute<bool>(settings, const RegisterScreen());
      case forgotPassword:
        return _materialRoute<void>(settings, const ForgetPasswordScreen());
      case otpVerification:
        return _materialRoute<void>(
          settings,
          OneTimeVerificationScreen(
            email: _requiredStringArgument(settings, 'email'),
          ),
        );
      case changePassword:
        return _materialRoute<void>(
          settings,
          ChangePasswordScreen(
            accessToken: _requiredStringArgument(settings, 'accessToken'),
          ),
        );
      default:
        return null;
    }
  }

  static void goToHome(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(home, (_) => false);
  }

  static Future<bool?> openRegister(BuildContext context) {
    return Navigator.of(context).pushNamed<bool>(register);
  }

  static Future<void> openForgotPassword(BuildContext context) {
    return Navigator.of(context).pushNamed<void>(forgotPassword);
  }

  static Future<void> openOtpVerification(
    BuildContext context, {
    required String email,
  }) {
    return Navigator.of(
      context,
    ).pushNamed<void>(otpVerification, arguments: email);
  }

  static Future<void> openChangePassword(
    BuildContext context, {
    required String accessToken,
  }) {
    return Navigator.of(
      context,
    ).pushNamed<void>(changePassword, arguments: accessToken);
  }

  static MaterialPageRoute<T> _materialRoute<T>(
    RouteSettings settings,
    Widget page,
  ) {
    return MaterialPageRoute<T>(settings: settings, builder: (_) => page);
  }

  static PageRouteBuilder<T> _fadeRoute<T>(
    RouteSettings settings,
    Widget page,
  ) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, animation, secondaryAnimation) => page,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 600),
    );
  }

  static String _requiredStringArgument(
    RouteSettings settings,
    String argumentName,
  ) {
    final argument = settings.arguments;
    if (argument is String && argument.isNotEmpty) return argument;

    throw ArgumentError.value(
      argument,
      argumentName,
      'Route ${settings.name} requires a non-empty String argument.',
    );
  }
}

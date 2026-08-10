import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/responsive_app_bar_title.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/otp_input_fields.dart';
import '../widgets/otp_resend_section.dart';

class OneTimeVerificationScreen extends StatefulWidget {
  const OneTimeVerificationScreen({super.key, required this.email});

  final String email;

  @override
  State<OneTimeVerificationScreen> createState() =>
      _OneTimeVerificationScreenState();
}

class _OneTimeVerificationScreenState extends State<OneTimeVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  Timer? _timer;
  int _secondsRemaining = 60;
  bool _canResend = false;
  bool _isResending = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startTimer();
      }
    });
  }

  void _startTimer() {
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canResend = true;
          _timer?.cancel();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _submitOtp() {
    if (_isVerifying || _isResending) return;

    final otp = _controllers.map((controller) => controller.text).join();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('กรุณากรอกรหัส OTP ให้ครบ 6 หลัก'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
          AuthVerifyOtpRequested(
            email: widget.email,
            otpCode: otp,
          ),
        );
  }

  void _resendOtp() {
    if (!_canResend || _isResending || _isVerifying) return;
    context.read<AuthBloc>().add(AuthSendOtpRequested(email: widget.email));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is VerifyOtpLoading) {
          setState(() {
            _isVerifying = true;
          });
        } else if (state is VerifyOtpSuccess) {
          setState(() {
            _isVerifying = false;
          });
          AppRoutes.openChangePassword(
            context,
            accessToken: state.tokens.accessToken,
          );
        } else if (state is VerifyOtpFailure) {
          setState(() {
            _isVerifying = false;
          });
          _showError(
            otpVerificationMessageForDisplay(
              state.message,
              hasExpired: _secondsRemaining <= 0,
            ),
          );
        } else if (state is SendOtpLoading) {
          setState(() {
            _isResending = true;
          });
        } else if (state is SendOtpSuccess) {
          setState(() {
            _isResending = false;
          });
          for (final controller in _controllers) {
            controller.clear();
          }
          _focusNodes.first.requestFocus();
          _startTimer();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('ส่งรหัส OTP อีกครั้งแล้ว กรุณาตรวจสอบอีเมล'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        } else if (state is SendOtpFailure) {
          setState(() {
            _isResending = false;
          });
          _showError(state.message);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: const ResponsiveAppBarTitle('เปลี่ยนรหัสผ่าน'),
        ),
        body: ResponsivePageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // ภาพ Smartphone Illustration
              Center(
                child: Container(
                  height: 200,
                  width: 200,
                  decoration: const BoxDecoration(color: Colors.transparent),
                  child: Image.asset(
                    'assets/images/smartphone.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              // หัวข้อหลัก
              Text(
                'ยืนยันรหัสOTP',
                style: theme.textTheme.headlineLarge?.copyWith(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ) ??
                    const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // คำอธิบายเพิ่มเติม
              Text(
                'กรุณากรอกรหัส OTP ที่ส่งไปยังอีเมลของคุณ',
                style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                      fontSize: 16,
                    ) ??
                    const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // ช่องกรอกรหัส OTP 6 หลัก
              OtpInputFields(
                controllers: _controllers,
                focusNodes: _focusNodes,
              ),
              const SizedBox(height: 32),
              // นับเวลาถอยหลังส่งรหัสใหม่ / ปุ่มส่งรหัสอีกครั้ง
              OtpResendSection(
                canResend: _canResend,
                isResending: _isResending,
                secondsRemaining: _secondsRemaining,
                onResend: _resendOtp,
              ),
              const SizedBox(height: 48),
              // ปุ่มกดยืนยันการอัปเดตรหัสผ่าน
              AppPrimaryButton(
                text: 'ยืนยัน',
                isLoading: _isVerifying,
                onPressed: _submitOtp,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

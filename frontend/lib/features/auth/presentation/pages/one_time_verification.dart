import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/colors.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../widgets/custom_button.dart';
import 'change_password.dart';

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
  final _authRemoteDataSource = AuthRemoteDataSource();

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
    _authRemoteDataSource.close();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _submitOtp() async {
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
    setState(() => _isVerifying = true);

    try {
      final tokens = await _authRemoteDataSource.verifyOtp(
        email: widget.email,
        otpCode: otp,
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ChangePasswordScreen(accessToken: tokens.accessToken),
        ),
      );
    } on AuthApiException catch (error) {
      if (!mounted) return;
      _showError(
        otpVerificationMessageForDisplay(
          error.message,
          hasExpired: _secondsRemaining <= 0,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend || _isResending || _isVerifying) return;

    setState(() => _isResending = true);
    try {
      await _authRemoteDataSource.sendOtp(email: widget.email);

      if (!mounted) return;
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
    } on AuthApiException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
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

    return Scaffold(
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
        title: const Text(
          'เปลี่ยนรหัสผ่าน',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
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
                style:
                    theme.textTheme.headlineLarge?.copyWith(
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
                style:
                    theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                      fontSize: 16,
                    ) ??
                    const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // ช่องกรอกรหัส OTP 6 หลัก
              Row(
                children: [
                  for (var index = 0; index < 6; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.bgFieldColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              if (index < 5) {
                                _focusNodes[index + 1].requestFocus();
                              } else {
                                _focusNodes[index].unfocus();
                              }
                            } else {
                              if (index > 0) {
                                _focusNodes[index - 1].requestFocus();
                              }
                            }
                          },
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                            hintText: '-',
                            hintStyle: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.hintTextColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 32),
              // นับเวลาถอยหลังส่งรหัสใหม่ / ปุ่มส่งรหัสอีกครั้ง
              Center(
                child: _canResend
                    ? TextButton(
                        onPressed: _isResending ? null : _resendOtp,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: _isResending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'ส่งรหัสอีกครั้ง',
                                style: TextStyle(
                                  color: AppColors.primaryColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      )
                    : Text(
                        'ส่งรหัส OTP ใหม่ในอีก ${_secondsRemaining}s',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              const SizedBox(height: 48),
              // ปุ่มกดยืนยันการอัปเดตรหัสผ่าน
              CustomButton(
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

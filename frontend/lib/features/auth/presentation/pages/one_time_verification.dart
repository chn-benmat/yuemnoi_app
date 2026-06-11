import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/colors.dart';
import '../widgets/custom_button.dart';
import 'change_password.dart';

class OneTimeVerificationScreen extends StatefulWidget {
  const OneTimeVerificationScreen({super.key});

  @override
  State<OneTimeVerificationScreen> createState() =>
      _OneTimeVerificationScreenState();
}

class _OneTimeVerificationScreenState extends State<OneTimeVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  Timer? _timer;
  int _secondsRemaining = 45;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    setState(() {
      _secondsRemaining = 45;
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
    // เช็กว่ากรอก OTP ครบ 4 หลักหรือไม่
    String otp = _controllers.map((c) => c.text).join();
    if (otp.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'กรุณากรอกรหัส OTP ให้ครบ 4 หลัก',
            style: TextStyle(fontFamily: 'Kanit'),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // เมื่อกรอกครบถ้วน ให้นำทางไปยังหน้าเปลี่ยนรหัสผ่าน
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.maincolor,
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
            fontFamily: 'Kanit',
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
                      fontFamily: 'Kanit',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // คำอธิบายเพิ่มเติม
              Text(
                'กรุณากรอกรหัสOTPที่ส่งไปในsms',
                style:
                    theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                      fontSize: 16,
                    ) ??
                    const TextStyle(
                      fontFamily: 'Kanit',
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // ช่องกรอกรหัส OTP 4 หลัก
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) {
                  return Container(
                    width: 70,
                    height: 75,
                    decoration: BoxDecoration(
                      color: AppColors.textinput,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          if (index < 3) {
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
                        fontFamily: 'Kanit',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        hintText: '-',
                        hintStyle: TextStyle(
                          fontFamily: 'Kanit',
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              // นับเวลาถอยหลังส่งรหัสใหม่ / ปุ่มส่งรหัสอีกครั้ง
              Center(
                child: _canResend
                    ? TextButton(
                        onPressed: _startTimer,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: const Text(
                          'ส่งรหัสอีกครั้ง',
                          style: TextStyle(
                            fontFamily: 'Kanit',
                            color: AppColors.maincolor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Text(
                        'ส่งรหัสใหม่ในอีก ${_secondsRemaining}s',
                        style: const TextStyle(
                          fontFamily: 'Kanit',
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              const SizedBox(height: 48),
              // ปุ่มกดยืนยันการอัปเดตรหัสผ่าน
              CustomButton(text: 'อัปเดตรหัสผ่าน', onPressed: _submitOtp),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

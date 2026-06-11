import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_button.dart';
import 'one_time_verification.dart';

class ForgetPasswordScreen extends StatefulWidget {
  const ForgetPasswordScreen({super.key});

  @override
  State<ForgetPasswordScreen> createState() => _ForgetPasswordScreenState();
}

class _ForgetPasswordScreenState extends State<ForgetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailPhoneController = TextEditingController();

  @override
  void dispose() {
    _emailPhoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // นำทางไปยังหน้า OTP Verification
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const OneTimeVerificationScreen(),
        ),
      );
    }
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
          'ลืมรหัสผ่าน',
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  'กู้คืนรหัสผ่าน',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: Colors.black,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ) ?? const TextStyle(
                    fontFamily: 'Kanit',
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'กรุณากรอกอีเมลหรือเบอร์โทรศัพท์ของคุณเพื่อรับรหัส OTP สำหรับตั้งค่ารหัสผ่านใหม่',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.black54,
                    fontSize: 15,
                  ) ?? const TextStyle(
                    fontFamily: 'Kanit',
                    fontSize: 15,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                CustomTextField(
                  label: 'อีเมล / เบอร์โทรศัพท์',
                  hintText: 'กรอกอีเมล หรือ เบอร์โทรศัพท์',
                  controller: _emailPhoneController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'กรุณากรอกอีเมลหรือเบอร์โทรศัพท์';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 48),
                CustomButton(
                  text: 'ส่งรหัส OTP',
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

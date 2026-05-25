import 'package:flutter/material.dart';

class ForgetPasswordScreen extends StatelessWidget {
  const ForgetPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ลืมรหัสผ่าน'),
      ),
      body: const Center(
        child: Text(
          'หน้าลืมรหัสผ่าน',
          style: TextStyle(fontFamily: 'Kanit', fontSize: 18),
        ),
      ),
    );
  }
}

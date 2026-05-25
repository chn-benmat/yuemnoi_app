import 'package:flutter/material.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สมัครสมาชิก'),
      ),
      body: const Center(
        child: Text(
          'หน้าสมัครสมาชิก',
          style: TextStyle(fontFamily: 'Kanit', fontSize: 18),
        ),
      ),
    );
  }
}

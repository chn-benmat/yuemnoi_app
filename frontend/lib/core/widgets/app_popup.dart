import 'package:flutter/material.dart';

void showAppPopup(BuildContext context, {required Widget content}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  // รอให้การปิดหน้าหรือเปลี่ยนหน้าของผู้เรียกเสร็จก่อนเปิด popup
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) return;
    showDialog<void>(
      context: navigator.context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('พบปัญหา'),
        content: SingleChildScrollView(child: content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

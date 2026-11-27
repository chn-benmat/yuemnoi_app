import 'package:flutter/material.dart';

import '../../domain/rental_verification.dart';

enum RentalVerificationStep { idCard, contactPhone }

Future<RentalVerificationStep?> showRentalVerificationDialog(
  BuildContext context, {
  required RentalVerification verification,
  required String action,
}) {
  return showDialog<RentalVerificationStep>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text('ยืนยันข้อมูลก่อน$action'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!verification.idCardApproved)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: Text(
                verification.identityPending
                    ? 'บัตรประชาชนอยู่ระหว่างตรวจสอบ'
                    : 'ยืนยันบัตรประชาชน',
              ),
              subtitle: Text(
                verification.identityPending
                    ? 'รอเจ้าหน้าที่อนุมัติ'
                    : 'ส่งข้อมูลให้เจ้าหน้าที่ตรวจสอบ',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.pop(dialogContext, RentalVerificationStep.idCard),
            ),
          if (!verification.contactPhoneSaved)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_outlined),
              title: const Text('เพิ่มเบอร์โทรศัพท์'),
              subtitle: const Text('บันทึกเบอร์ในข้อมูลติดต่อของคุณ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(
                dialogContext,
                RentalVerificationStep.contactPhone,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}

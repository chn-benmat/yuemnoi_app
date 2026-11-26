import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../data/chat_rental_safety_preferences.dart';
import '../../domain/entities/chat_conversation.dart';

Future<void> showChatRentalSafetyReminder(
  BuildContext context, {
  required String accountId,
  required ChatParticipantRole role,
  ChatRentalSafetyPreferences preferences = const ChatRentalSafetyPreferences(),
}) async {
  if (await preferences.isHiddenToday(accountId, role) || !context.mounted) {
    return;
  }
  if (ModalRoute.of(context)?.isCurrent != true) return;

  final hideToday = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChatRentalSafetyDialog(role: role),
  );
  if (hideToday == true) await preferences.hideToday(accountId, role);
}

class _ChatRentalSafetyDialog extends StatefulWidget {
  const _ChatRentalSafetyDialog({required this.role});

  final ChatParticipantRole role;

  @override
  State<_ChatRentalSafetyDialog> createState() =>
      _ChatRentalSafetyDialogState();
}

class _ChatRentalSafetyDialogState extends State<_ChatRentalSafetyDialog> {
  bool _hideToday = false;

  @override
  Widget build(BuildContext context) {
    final (title, tips) = switch (widget.role) {
      ChatParticipantRole.owner => (
        'คำเตือนก่อนปล่อยเช่าอุปกรณ์',
        const [
          'ถ่ายรูปสภาพอุปกรณ์และอุปกรณ์เสริมก่อนส่งมอบและหลังรับคืน',
          'ตกลงค่าเช่า วันคืน และเงื่อนไขกรณีเสียหายหรือสูญหายในแชท',
          'หากชำระด้วยการโอน ให้เช็กยอดเงินเข้าจริงก่อนส่งมอบ และอย่าเปิดเผย OTP',
        ],
      ),
      ChatParticipantRole.renter => (
        'คำเตือนก่อนเช่าอุปกรณ์',
        const [
          'ตรวจสอบโปรไฟล์ผู้ปล่อยเช่า ค่าเช่า และเงื่อนไขก่อนจ่ายเงิน',
          'ถ่ายรูปอุปกรณ์และตรวจสอบก่อนใช้งานทุกครั้ง',
          'ระวังการเร่งให้โอนเงิน ลิงก์ชำระเงินแปลก ๆ และการขอรหัส OTP',
        ],
      ),
    };

    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFFFF1D6),
            foregroundColor: Color(0xFF934D00),
            child: Icon(Icons.gpp_maybe_outlined, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primaryColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip)),
                ],
              ),
            ),
          const Divider(),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primaryColor,
            title: const Text('ไม่ต้องแสดงอีกในวันนี้'),
            value: _hideToday,
            onChanged: (value) => setState(() => _hideToday = value ?? false),
          ),
        ],
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_hideToday),
          child: const Text('รับทราบ'),
        ),
      ],
    );
  }
}

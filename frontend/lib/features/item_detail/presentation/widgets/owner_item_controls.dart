import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

class OwnerItemVisibility extends StatelessWidget {
  const OwnerItemVisibility({
    super.key,
    required this.hidden,
    required this.busy,
    required this.onChanged,
  });
  final bool hidden;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFECE4F4)),
    ),
    child: SwitchListTile.adaptive(
      key: const ValueKey('owner-item-visibility'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      secondary: const Icon(
        Icons.visibility_outlined,
        color: Color(0xFF302A48),
        size: 22,
      ),
      activeTrackColor: AppColors.primaryColor,
      value: !hidden,
      onChanged: busy ? null : onChanged,
      title: const Text(
        'แสดงในหน้าร้าน',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          hidden ? 'คุณสามารถเปิดเพื่อแสดงสินค้า' : 'ปิดเพื่อซ่อนจากการค้นหา',
          style: const TextStyle(
            fontSize: 12,
            height: 1.6,
            color: Color(0xFF716A7E),
          ),
        ),
      ),
    ),
  );
}

class OwnerItemDeleteButton extends StatelessWidget {
  const OwnerItemDeleteButton({
    super.key,
    required this.busy,
    required this.deleting,
    required this.onPressed,
  });
  final bool busy;
  final bool deleting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      key: const ValueKey('owner-delete-item'),
      onPressed: busy ? null : onPressed,
      icon: deleting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline_rounded, size: 20),
      label: Text(deleting ? 'กำลังลบอุปกรณ์…' : 'ลบอุปกรณ์'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFD92E36),
        backgroundColor: const Color(0xFFFFF0F1),
        side: const BorderSide(color: Color(0xFFF15A64)),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

Future<bool> confirmItemDeletion(BuildContext context, String itemName) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('ลบอุปกรณ์นี้?'),
          content: Text('“$itemName” จะถูกลบอย่างถาวรและกู้คืนไม่ได้'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              key: const ValueKey('confirm-delete-item'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB9383D),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ลบอุปกรณ์'),
            ),
          ],
        ),
      ) ??
      false;
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

// คำอธิบาย: วิดเจ็ตสำหรับแสดงและเลือกรูปภาพโปรไฟล์ในหน้าสมัครสมาชิก
class RegisterProfileImagePicker extends StatelessWidget {
  final Uint8List? profileImageBytes;
  final VoidCallback onTap;

  const RegisterProfileImagePicker({
    super.key,
    required this.profileImageBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.bgFieldColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE2E5E7),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: profileImageBytes == null
                      ? const Icon(
                          Icons.person_outline_rounded,
                          size: 56,
                          color: AppColors.labelColor,
                        )
                      : Image.memory(profileImageBytes!, fit: BoxFit.cover),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      profileImageBytes == null ? Icons.add : Icons.edit,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'เพิ่มรูปโปรไฟล์',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF555555),
            ),
          ),
        ],
      ),
    );
  }
}

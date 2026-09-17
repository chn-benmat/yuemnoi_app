import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/rental_return_session.dart';
import '../cubit/rental_return_cubit.dart';
import '../cubit/rental_return_state.dart';

class LiveCameraCaptureSheet extends StatelessWidget {
  const LiveCameraCaptureSheet({super.key});

  Future<void> _capturePhoto(
    BuildContext context,
    String angleKey,
  ) async {
    final picker = ImagePicker();

    try {
      // โหมดถ่ายรูปจากกล้องสดเท่านั้น ป้องกันการเลือกภาพจากอัลบั้ม 100%
      // ไม่อนุญาตให้เลือกจาก Gallery หรือ Album ไม่ว่าจะเปิดจากเครื่องใด
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1600,
        imageQuality: 85,
      );

      if (photo != null && context.mounted) {
        context.read<RentalReturnCubit>().updatePhoto(
              angleKey: angleKey,
              photoPath: photo.path,
            );
      }
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            icon: const Icon(
              Icons.no_photography_rounded,
              color: Color(0xFFDC2626),
              size: 44,
            ),
            title: const Text(
              'บังคับถ่ายภาพสดจากกล้องเท่านั้น',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'มาตรการความปลอดภัยขั้นสูง (Anti-Fraud Policy):',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFFDC2626),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'เพื่อป้องกันการนำรูปเก่ามาใช้ซ้ำและการปลอมแปลงสภาพเครื่อง ระบบไม่อนุญาตให้เลือกภาพจากอัลบั้มหรือคลังภาพในทุกกรณี ไม่ว่าจะเปิดใช้งานจากโทรศัพท์ แท็บเล็ต หรือคอมพิวเตอร์\n\nหากเครื่องนี้ไม่มีกล้อง หรือถูกปิดกั้นสิทธิ์กล้อง กรุณาเปิดแอปผ่านสมาร์ตโฟนที่มีกล้องเพื่อถ่ายภาพส่งมอบเครื่องจริง',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    color: Color(0xFF475569),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: const Text(
                  'รับทราบและปฏิบัติตาม',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RentalReturnCubit, RentalReturnState>(
      builder: (context, state) {
        final session = state.session;
        final cubit = context.read<RentalReturnCubit>();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Security Warning Banner (เน้นย้ำความปลอดภัย ห้ามเลือกจากอัลบั้มเด็ดขาด) ──
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.security_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'มาตรการบังคับถ่ายภาพสด (Camera Only)',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• ห้ามเลือกรูปจากอัลบั้มหรือคลังภาพโดยเด็ดขาดในทุกกรณี\n'
                      '• ต้องใช้กล้องถ่ายภาพเครื่องจริง ณ จุดส่งมอบเท่านั้น (เปิดจากเครื่องไหนก็ต้องถ่ายสด)\n'
                      '• โปรดถ่ายให้ติดรหัสยืนยันความปลอดภัยในภาพเพื่อป้องกันการนำภาพเก่ามาใช้ซ้ำ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        color: Color(0xFF7F1D1D),
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // หัวข้อและการป้องกันการโกง
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: AppColors.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ถ่ายภาพตรวจสอบสภาพเครื่อง (กล้องสด)',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E2022),
                          ),
                        ),
                        Text(
                          'ระบบล็อกการทำงาน: กล้องถ่ายภาพสดเท่านั้น ไม่อนุญาตให้อัปโหลดไฟล์ภาพ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // รหัสสุ่มความปลอดภัยประจำรอบ (Dynamic Challenge Code)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF475569)),
                        SizedBox(width: 8),
                        Text(
                          'รหัสยืนยันภาพถ่ายสด:',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        session.dynamicChallengeCode,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ช่องถ่ายรูป 3 มุมบังคับ
              Column(
                children: session.photos.map((photo) {
                  return _AnglePhotoTile(
                    photo: photo,
                    onTap: () => _capturePhoto(context, photo.angleKey),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE2E8F0)),
              const SizedBox(height: 10),

              // Checklist สภาพเครื่อง
              const Text(
                'รายการยืนยันสภาพอุปกรณ์โดยผู้เช่า',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),

              _ChecklistCheckbox(
                title: 'เครื่องเปิดติดและทำงานได้ตามปกติ',
                value: session.checklist['power_on'] ?? false,
                onChanged: (val) => cubit.toggleChecklist('power_on', val),
              ),
              _ChecklistCheckbox(
                title: 'ไม่มีรอยแตกร้าวหรือความเสียหายใหม่',
                value: session.checklist['no_new_cracks'] ?? false,
                onChanged: (val) => cubit.toggleChecklist('no_new_cracks', val),
              ),
              _ChecklistCheckbox(
                title: 'อุปกรณ์เสริม สายชาร์จ และกล่องครบถ้วน',
                value: session.checklist['accessories_complete'] ?? false,
                onChanged: (val) => cubit.toggleChecklist('accessories_complete', val),
              ),

              const SizedBox(height: 20),

              // ปุ่มส่งผลตรวจสภาพ
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: state.isSubmitting
                      ? null
                      : () => cubit.submitLiveConditionVerification(),
                  icon: state.isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  label: Text(
                    state.isSubmitting ? 'กำลังส่งข้อมูล...' : 'ส่งภาพถ่ายยืนยันให้ร้านค้า',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnglePhotoTile extends StatelessWidget {
  final ReturnInspectionPhoto photo;
  final VoidCallback onTap;

  const _AnglePhotoTile({
    required this.photo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = photo.hasPhoto;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasImage ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasImage ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          // ภาพตัวอย่างหรือปุ่มเปิดกล้อง
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: 64,
                height: 64,
                color: hasImage ? Colors.black87 : const Color(0xFFE2E8F0),
                child: hasImage && photo.localPath != null
                    ? (kIsWeb
                        ? Image.network(
                            photo.localPath!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
                          )
                        : Image.file(
                            File(photo.localPath!),
                            fit: BoxFit.cover,
                          ))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 24,
                            color: hasImage ? Colors.white : const Color(0xFF64748B),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'ถ่ายรูป',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 10,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // รายละเอียดมุม
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  photo.angleTitle,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E2022),
                  ),
                ),
                const SizedBox(height: 3),
                if (hasImage) ...[
                  Row(
                    children: [
                      const Icon(Icons.verified_rounded, size: 13, color: Color(0xFF16A34A)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'ถ่ายสดจากกล้อง: ${photo.formattedTime}',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'รหัสยืนยัน: ${photo.challengeCode} (ตรวจสอบแล้ว)',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 10,
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'กล้องสดเท่านั้น • ห้ามใช้อัลบั้ม',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 9.5,
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'กดที่นี่เพื่อเปิดกล้องถ่ายภาพพร้อมรหัส ${photo.challengeCode}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ปุ่ม Action
          IconButton(
            onPressed: onTap,
            icon: Icon(
              hasImage ? Icons.cached_rounded : Icons.photo_camera_rounded,
              color: hasImage ? const Color(0xFF16A34A) : AppColors.primaryColor,
              size: 22,
            ),
            tooltip: hasImage
                ? 'ถ่ายใหม่ด้วยกล้องสด'
                : 'เปิดกล้องถ่ายภาพสด (ห้ามเลือกจากอัลบั้ม)',
          ),
        ],
      ),
    );
  }
}

class _ChecklistCheckbox extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ChecklistCheckbox({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

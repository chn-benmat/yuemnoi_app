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

  Future<void> _capturePhoto(BuildContext context, String angleKey) async {
    final picker = ImagePicker();

    try {
      // โหมดถ่ายรูปจากกล้องสดเท่านั้น ป้องกันการเลือกภาพจากอัลบั้ม 100%
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
              Icons.camera_alt_outlined,
              color: Color(0xFFDC2626),
              size: 40,
            ),
            title: const Text(
              'ต้องถ่ายภาพสดจากกล้อง',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'เพื่อความปลอดภัยและป้องกันข้อพิพาท ระบบเปิดใช้งานเฉพาะกล้องถ่ายสดเท่านั้น กรุณาอนุญาตสิทธิ์การเข้าถึงกล้องเพื่อดำเนินการต่อ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: Color(0xFF475569),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
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
                ),
                child: const Text(
                  'รับทราบ',
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
        final submitted = ![
          RentalReturnStep.inProgress,
          RentalReturnStep.nearReturnAlert,
          RentalReturnStep.liveVerification,
        ].contains(session.step);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── หัวข้อพร้อมรหัสยืนยัน ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: AppColors.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ถ่ายภาพตรวจสอบสภาพ (กล้องสด)',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'ถ่าย 3 มุมเพื่อป้องกันข้อพิพาท ณ จุดส่งมอบ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // รหัส Challenge Code ขนาดกะทัดรัด
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tag_rounded,
                          size: 13,
                          color: Color(0xFF64748B),
                        ),
                        Text(
                          session.dynamicChallengeCode,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── ตารางถ่ายภาพ 3 มุม (3-Slot Grid สไตล์โมเดิร์น) ──
              Row(
                children: session.photos.map((photo) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _CompactPhotoSlot(
                        photo: photo,
                        onTap: submitted
                            ? null
                            : () => _capturePhoto(context, photo.angleKey),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 12),

              // ── รายการ Checklist สภาพอุปกรณ์ ──
              const Text(
                'ตรวจสอบสภาพอุปกรณ์เบื้องต้น',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),

              _ChecklistTile(
                title: 'เครื่องเปิดติดและทำงานได้ตามปกติ',
                value: session.checklist['power_on'] ?? false,
                onChanged: submitted
                    ? null
                    : (val) => cubit.toggleChecklist('power_on', val),
              ),
              _ChecklistTile(
                title: 'ไม่มีรอยแตกร้าวหรือความเสียหายใหม่',
                value: session.checklist['no_new_cracks'] ?? false,
                onChanged: submitted
                    ? null
                    : (val) => cubit.toggleChecklist('no_new_cracks', val),
              ),
              _ChecklistTile(
                title: 'อุปกรณ์เสริม สายชาร์จ และกล่องครบถ้วน',
                value: session.checklist['accessories_complete'] ?? false,
                onChanged: submitted
                    ? null
                    : (val) =>
                          cubit.toggleChecklist('accessories_complete', val),
              ),

              const SizedBox(height: 14),

              // ── ปุ่มส่งข้อมูลยืนยัน ──
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: state.isSubmitting || submitted
                      ? null
                      : () => cubit.submitLiveConditionVerification(),
                  icon: state.isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                  label: Text(
                    state.isSubmitting
                        ? 'กำลังส่งข้อมูล...'
                        : submitted
                        ? 'ส่งภาพเรียบร้อยแล้ว'
                        : 'ส่งภาพยืนยันให้ร้านค้า',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

class _CompactPhotoSlot extends StatelessWidget {
  final ReturnInspectionPhoto photo;
  final VoidCallback? onTap;

  const _CompactPhotoSlot({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = photo.hasPhoto;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: hasImage ? Colors.black : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasImage
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFE2E8F0),
                width: hasImage ? 1.5 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo.imageUrl != null && photo.imageUrl!.isNotEmpty)
                    Image.network(photo.imageUrl!, fit: BoxFit.cover)
                  else if (hasImage && photo.localPath != null)
                    (kIsWeb
                        ? Image.network(
                            photo.localPath!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.grey,
                                ),
                          )
                        : Image.file(File(photo.localPath!), fit: BoxFit.cover))
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 26,
                          color: AppColors.primaryColor.withValues(alpha: 0.8),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'แตะถ่ายสด',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),

                  // ตราประทับเมื่อถ่ายแล้ว
                  if (hasImage)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFF16A34A),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 11,
                        ),
                      ),
                    ),

                  // ปุ่มถ่ายใหม่ขนาดเล็กเมื่อมีรูปแล้ว
                  if (hasImage && onTap != null)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            photo.angleTitle,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              fontWeight: hasImage ? FontWeight.bold : FontWeight.w500,
              color: hasImage
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ChecklistTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (v) => onChanged!(v ?? false),
                activeColor: AppColors.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: value
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF64748B),
                  fontWeight: value ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

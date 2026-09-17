import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/rental_return_session.dart';
import '../cubit/rental_return_cubit.dart';
import '../cubit/rental_return_state.dart';

class LenderInspectionView extends StatefulWidget {
  const LenderInspectionView({super.key});

  @override
  State<LenderInspectionView> createState() => _LenderInspectionViewState();
}

class _LenderInspectionViewState extends State<LenderInspectionView> {
  bool _isPhysicallyChecked = false;

  void _showImageDialog(BuildContext context, ReturnInspectionPhoto photo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    photo.angleTitle,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            InteractiveViewer(
              child: photo.localPath != null
                  ? (kIsWeb
                      ? Image.network(
                          photo.localPath!,
                          fit: BoxFit.contain,
                        )
                      : Image.file(
                          File(photo.localPath!),
                          fit: BoxFit.contain,
                        ))
                  : CachedNetworkImage(
                      imageUrl: photo.imageUrl ?? '',
                      fit: BoxFit.contain,
                      placeholder: (c, u) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorWidget: (c, u, e) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'ถ่ายสดเมื่อ: ${photo.formattedTime} | รหัส: ${photo.challengeCode}',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RentalReturnCubit, RentalReturnState>(
      builder: (context, state) {
        final session = state.session;
        final cubit = context.read<RentalReturnCubit>();
        final hasPhotos = session.photos.any((p) => p.hasPhoto);

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
              // หัวข้อฝั่งร้านค้า
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.verified_outlined,
                      color: Color(0xFF10B981),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ตรวจสอบเครื่องคืน (ฝ่ายผู้ให้เช่า)',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E2022),
                          ),
                        ),
                        Text(
                          'ตรวจสอบสภาพจริงเปรียบเทียบกับภาพสดที่ลูกค้าส่งมา',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (!hasPhotos) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, color: Color(0xFF94A3B8)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'รอลูกค้าถ่ายภาพสดส่งเข้ามาเพื่อตรวจสภาพก่อนส่งมอบ...',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ตะแกรงภาพถ่ายสดที่ลูกค้าส่งมา
                const Text(
                  'ภาพถ่ายสภาพเครื่องสดที่ลูกค้าส่งมา:',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: session.photos.map((photo) {
                    final hasPic = photo.hasPhoto;
                    return Expanded(
                      child: GestureDetector(
                        onTap: hasPic ? () => _showImageDialog(context, photo) : null,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 85,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: hasPic
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      photo.localPath != null
                                          ? (kIsWeb
                                              ? Image.network(
                                                  photo.localPath!,
                                                  fit: BoxFit.cover,
                                                )
                                              : Image.file(
                                                  File(photo.localPath!),
                                                  fit: BoxFit.cover,
                                                ))
                                          : CachedNetworkImage(
                                              imageUrl: photo.imageUrl ?? '',
                                              fit: BoxFit.cover,
                                            ),
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(
                                            Icons.zoom_in_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : const Center(
                                    child: Icon(Icons.image_outlined, color: Colors.grey),
                                  ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),

                // ข้อมูล Challenge Code
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'รหัสตรวจสอบถ่ายสด:',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF166534),
                        ),
                      ),
                      Text(
                        session.dynamicChallengeCode,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE2E8F0)),
              const SizedBox(height: 12),

              // กล่องติ๊กยืนยันของร้านค้า
              InkWell(
                onTap: () {
                  setState(() {
                    _isPhysicallyChecked = !_isPhysicallyChecked;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isPhysicallyChecked
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isPhysicallyChecked
                          ? const Color(0xFF10B981)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _isPhysicallyChecked,
                        onChanged: (val) {
                          setState(() {
                            _isPhysicallyChecked = val ?? false;
                          });
                        },
                        activeColor: const Color(0xFF10B981),
                      ),
                      const Expanded(
                        child: Text(
                          'ข้าพเจ้าได้รับเครื่องคืนแล้ว และตรวจสอบสภาพเรียบร้อยทุกอย่างสมบูรณ์',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E2022),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ปุ่มยืนยันเพื่อสร้าง QR Code
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: !_isPhysicallyChecked || state.isSubmitting
                      ? null
                      : () => cubit.confirmLenderInspection(),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20, color: Colors.white),
                  label: const Text(
                    'ยืนยันรับเครื่อง & แสดง QR Code',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
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

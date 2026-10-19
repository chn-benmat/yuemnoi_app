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
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
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
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            InteractiveViewer(
              child: photo.localPath != null
                  ? (kIsWeb
                        ? Image.network(photo.localPath!, fit: BoxFit.contain)
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
                'บันทึกเมื่อ: ${photo.formattedTime} | รหัส: ${photo.challengeCode}',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: Colors.white70,
                  fontSize: 11.5,
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
              // ── หัวข้อฝั่งร้านค้า ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.verified_outlined,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ตรวจสอบสภาพเครื่อง (ร้านค้า)',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'เทียบภาพถ่ายสดของลูกค้ากับตัวเครื่องจริง',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Order Number Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.receipt_long_rounded,
                          size: 13,
                          color: Color(0xFF15803D),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '# ${session.orderNumber}',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              if (!hasPhotos) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_empty_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'รอลูกค้าถ่ายภาพสดส่งเข้ามาตรวจสอบสภาพ...',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => cubit.loadSession(
                          rentalId: session.rentalId,
                          isLender: true,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                size: 14,
                                color: Color(0xFF0284C7),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'รีเฟรช',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ภาพถ่ายสดจากลูกค้า (3 มุม)',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    InkWell(
                      onTap: () => cubit.loadSession(
                        rentalId: session.rentalId,
                        isLender: true,
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          SizedBox(width: 3),
                          Text(
                            'รีเฟรชภาพ',
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
                const SizedBox(height: 8),
                // ตารางแสดงภาพถ่าย 3 มุม
                Row(
                  children: session.photos.map((photo) {
                    final hasPic = photo.hasPhoto;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: hasPic
                              ? () => _showImageDialog(context, photo)
                              : null,
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            children: [
                              Container(
                                height: 90,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: hasPic
                                        ? const Color(0xFF86EFAC)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
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
                                                          File(
                                                            photo.localPath!,
                                                          ),
                                                          fit: BoxFit.cover,
                                                        ))
                                                : CachedNetworkImage(
                                                    imageUrl:
                                                        photo.imageUrl ?? '',
                                                    fit: BoxFit.cover,
                                                  ),
                                            Positioned(
                                              right: 4,
                                              bottom: 4,
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: const Icon(
                                                  Icons.zoom_in_rounded,
                                                  size: 13,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Center(
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: Color(0xFFCBD5E1),
                                            size: 26,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                photo.angleTitle,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 12),

              // กล่องติ๊กยืนยันของร้านค้า
              InkWell(
                onTap: () {
                  setState(() {
                    _isPhysicallyChecked = !_isPhysicallyChecked;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isPhysicallyChecked
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isPhysicallyChecked
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _isPhysicallyChecked,
                          onChanged: (val) {
                            setState(() {
                              _isPhysicallyChecked = val ?? false;
                            });
                          },
                          activeColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'ได้รับเครื่องคืนแล้ว และตรวจสภาพครบถ้วนสมบูรณ์',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ปุ่มยืนยันเพื่อสร้าง QR Code
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed:
                      !hasPhotos || !_isPhysicallyChecked || state.isSubmitting
                      ? null
                      : () => cubit.confirmLenderInspection(),
                  icon: const Icon(
                    Icons.qr_code_2_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'ยืนยันรับเครื่อง & แสดง QR Code',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
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

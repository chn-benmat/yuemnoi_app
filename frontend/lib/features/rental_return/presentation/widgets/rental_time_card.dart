import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/rental_return_session.dart';

class RentalTimeCard extends StatelessWidget {
  final RentalReturnSession session;
  final VoidCallback? onChatTap;
  final VoidCallback? onCallTap;

  const RentalTimeCard({
    super.key,
    required this.session,
    this.onChatTap,
    this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final isNear = session.isNearDeadline;
    final isOverdue = session.isOverdue;
    final isCompleted = session.step == RentalReturnStep.completed;

    Color badgeBgColor;
    Color badgeTextColor;
    String statusText;

    if (isCompleted) {
      badgeBgColor = const Color(0xFFD1FAE5);
      badgeTextColor = const Color(0xFF059669);
      statusText = 'คืนอุปกรณ์สำเร็จ';
    } else if (isOverdue) {
      badgeBgColor = const Color(0xFFFEE2E2);
      badgeTextColor = const Color(0xFFDC2626);
      statusText = 'เกินกำหนดคืน';
    } else if (isNear) {
      badgeBgColor = const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFFD97706);
      statusText = 'ใกล้ถึงเวลาคืน';
    } else {
      badgeBgColor = const Color(0xFFEDE9FE);
      badgeTextColor = AppColors.primaryColor;
      statusText = 'กำลังใช้งาน';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          // ── หัวการ์ด: ข้อมูลเครื่องและแท็กสถานะ ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 76,
                    height: 76,
                    color: const Color(0xFFF3F4F6),
                    child: CachedNetworkImage(
                      imageUrl: session.itemImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBgColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isCompleted
                                      ? Icons.check_circle_rounded
                                      : isNear
                                          ? Icons.warning_amber_rounded
                                          : Icons.schedule_rounded,
                                  size: 13,
                                  color: badgeTextColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: badgeTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '#${session.rentalId}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11,
                              color: AppColors.hintTextColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        session.itemName,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E2022),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'หมวดหมู่: ${session.category}',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF757778),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F2F4)),

          // ── กล่องสรุปเวลาเช่าและเวลาคืน (เข้าใจง่ายตามที่ผู้ใช้ต้องการ) ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isNear
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isNear
                            ? const Color(0xFFFEF3C7)
                            : AppColors.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isNear ? Icons.alarm_on_rounded : Icons.access_time_filled_rounded,
                        color: isNear ? const Color(0xFFD97706) : AppColors.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'เช่าได้ถึง: ${session.endAtFormatted}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E2022),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            session.deadlineSummary,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isNear ? const Color(0xFFD97706) : AppColors.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ป้ายบอกเวลาคงเหลือ
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isNear
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        session.remainingDurationText,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isNear ? const Color(0xFFB45309) : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // จุดนัดรับ-ส่งคืน
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'จุดนัดส่งคืน: ${session.pickupLocation}',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

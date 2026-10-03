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
      badgeBgColor = const Color(0xFFECFDF5);
      badgeTextColor = const Color(0xFF059669);
      statusText = 'คืนอุปกรณ์สำเร็จ';
    } else if (isOverdue) {
      badgeBgColor = const Color(0xFFFEF2F2);
      badgeTextColor = const Color(0xFFDC2626);
      statusText = 'เกินกำหนดคืน';
    } else if (isNear) {
      badgeBgColor = const Color(0xFFFFFBEB);
      badgeTextColor = const Color(0xFFD97706);
      statusText = 'ใกล้ถึงเวลาคืน';
    } else {
      badgeBgColor = const Color(0xFFF3E8FF);
      badgeTextColor = AppColors.primaryColor;
      statusText = 'กำลังใช้งาน';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          // ── ส่วนข้อมูลอุปกรณ์ ──
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: const Color(0xFFF8FAFC),
                    child: CachedNetworkImage(
                      imageUrl: session.itemImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.devices_rounded,
                        color: Color(0xFF94A3B8),
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBgColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: badgeTextColor,
                              ),
                            ),
                          ),
                          Text(
                            '#${session.orderNumber}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        session.itemName,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.category,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // ── กำหนดเวลาคืนและจุดส่งมอบ ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // แถวเวลาและ Countdown
                Row(
                  children: [
                    Icon(
                      isNear ? Icons.alarm_rounded : Icons.schedule_rounded,
                      size: 16,
                      color: isNear ? const Color(0xFFD97706) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12.5,
                            color: Color(0xFF475569),
                          ),
                          children: [
                            const TextSpan(text: 'กำหนดคืน: '),
                            TextSpan(
                              text: session.endAtFormatted,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isNear
                            ? const Color(0xFFFEF3C7)
                            : isOverdue
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        session.remainingDurationText,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isNear
                              ? const Color(0xFFB45309)
                              : isOverdue
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // แถวจุดนัดส่งมอบ
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'จุดส่งมอบ: ${session.pickupLocation}',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

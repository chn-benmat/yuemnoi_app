import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/domain/entities/rental_booking.dart';

/// Modal Bottom Sheet สำหรับแสดงการแจ้งเตือนเวลาเช่าอุปกรณ์ (Rental Expiration & Overdue Notifications)
/// ออกแบบตามแนวคิด Swiss Style & Clean SaaS:
/// - ใช้ 2 สีหลัก (ม่วง Yuemnoi สำหรับ Active, แดง สำหรับ Overdue) + Slate Neutrals
/// - ข้อมูลชัดเจน ครบถ้วน ไม่รกตา
/// - แตะเพื่อนำทางไปยังหน้า "สถานะการเช่า" (Rental Status) ทันที
class RentalNotificationBottomSheet extends StatelessWidget {
  final List<RentalBooking> activeRentals;
  final VoidCallback? onRefresh;

  const RentalNotificationBottomSheet({
    super.key,
    required this.activeRentals,
    this.onRefresh,
  });

  static Future<void> show(
    BuildContext context, {
    required List<RentalBooking> activeRentals,
    VoidCallback? onRefresh,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RentalNotificationBottomSheet(
        activeRentals: activeRentals,
        onRefresh: onRefresh,
      ),
    );
  }

  void _navigateToRentalStatus(BuildContext context) {
    Navigator.of(context).pop();
    AppRoutes.openRentalStatus(context);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag Handle & Header Bar ──
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'การแจ้งเตือนเวลาเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (activeRentals.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFDDD6FE),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${activeRentals.length} รายการ',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Color(0xFF94A3B8),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.8, color: Color(0xFFF1F5F9)),

            // ── รายการการแจ้งเตือน หรือสถานะว่าง ──
            Flexible(
              child: activeRentals.isEmpty
                  ? _buildEmptyState(context)
                  : _buildNotificationList(context),
            ),

            // ── ปุ่มนำทางด้านล่างไปยังหน้า สถานะการเช่า ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => _navigateToRentalStatus(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'ไปที่สถานะการเช่าทั้งหมด',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF94A3B8),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'ไม่มีอุปกรณ์ที่ใกล้หมดเวลาในขณะนี้',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'เมื่อคุณเช่าอุปกรณ์ ระบบจะแจ้งเตือนเวลากำหนดส่งคืนและเวลาที่เหลือที่นี่',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(BuildContext context) {
    final now = DateTime.now();

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: activeRentals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final item = activeRentals[index];
        final end = item.endDate ?? now.add(const Duration(hours: 24));
        final bool isOverdue = now.isAfter(end);

        final Duration diff = isOverdue
            ? now.difference(end)
            : end.difference(now);

        final String timeText;
        if (isOverdue) {
          final hours = diff.inHours;
          final mins = diff.inMinutes % 60;
          timeText = hours > 0
              ? 'เกินกำหนดมาแล้ว $hours ชม. $mins นาที'
              : 'เกินกำหนดมาแล้ว $mins นาที';
        } else {
          final days = diff.inDays;
          final hours = diff.inHours % 24;
          final mins = diff.inMinutes % 60;
          if (days > 0) {
            timeText = 'เหลือเวลาอีก $days วัน $hours ชม.';
          } else if (hours > 0) {
            timeText = 'เหลือเวลาอีก $hours ชม. $mins นาที';
          } else {
            timeText = 'เหลือเวลาอีก $mins นาที';
          }
        }

        String endFormatted;
        try {
          endFormatted = DateFormat('d MMM yyyy • HH:mm น.', 'th').format(end);
        } catch (_) {
          endFormatted = '${end.day}/${end.month}/${end.year} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')} น.';
        }

        final cardBg = isOverdue ? const Color(0xFFFFF8F8) : const Color(0xFFFBFBFE);
        final borderColor = isOverdue ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0);
        final accentColor = isOverdue ? const Color(0xFFDC2626) : AppColors.primaryColor;

        return InkWell(
          onTap: () => _navigateToRentalStatus(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // แถวบน: รูปอุปกรณ์, ชื่อ, ป้ายสถานะ
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 46,
                        height: 46,
                        color: const Color(0xFFF1F5F9),
                        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 20,
                                  color: Color(0xFF94A3B8),
                                ),
                              )
                            : const Icon(
                                Icons.inventory_2_outlined,
                                size: 20,
                                color: Color(0xFF94A3B8),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ผู้ปล่อยเช่า: ${item.partnerName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isOverdue
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isOverdue
                              ? const Color(0xFFFECACA)
                              : const Color(0xFFDDD6FE),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isOverdue ? '⚠️ เลยกำหนด' : '⏳ กำลังเช่า',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // กล่องข้อความแจ้งเตือนสถานะเวลา (Anti-AI Slop: เรียบ สะอาด สื่อสารตรงประเด็น)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? const Color(0xFFFEE2E2).withValues(alpha: 0.5)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          isOverdue
                              ? 'เลยกำหนดส่งคืนแล้วนะ! กรุณานำส่งคืนทันที'
                              : 'ใกล้ถึงกำหนดคืนแล้วนะ! เตรียมตัวส่งคืน',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // ข้อมูลครบกำหนด & เวลาที่เหลือ/เลท
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ครบกำหนด: $endFormatted',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      timeText,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

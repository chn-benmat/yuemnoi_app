import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../domain/entities/chat_message.dart';

/// แถบสถานะการเช่าด้านบนห้องแชท (Pinned Header Banner)
/// แสดงเวลานับถอยหลัง, สถานะกำลังเช่า, ลิงก์ไปหน้าสถานะการเช่า, และปุ่มลัดไปหน้าคืนของ
class ActiveRentalHeaderBanner extends StatefulWidget {
  const ActiveRentalHeaderBanner({
    super.key,
    required this.bookingData,
    this.bookingMessage,
    this.isOwner = false,
    this.bookingId,
    this.onTap,
  });

  final BookingRequestData bookingData;
  final ChatMessage? bookingMessage;
  final bool isOwner;
  final int? bookingId;
  final VoidCallback? onTap;

  @override
  State<ActiveRentalHeaderBanner> createState() =>
      _ActiveRentalHeaderBannerState();
}

class _ActiveRentalHeaderBannerState extends State<ActiveRentalHeaderBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  DateTime get _effectiveEndDateTime => widget.bookingData.endDateTime;

  bool get _isExpired => DateTime.now().isAfter(_effectiveEndDateTime);

  String _formatRemainingTime() {
    final now = DateTime.now();
    final difference = _effectiveEndDateTime.difference(now);

    if (difference.isNegative || difference == Duration.zero) {
      return 'ครบกำหนดคืนแล้ว';
    }

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;
    final seconds = difference.inSeconds % 60;

    if (days > 0) {
      return '$days วัน $hours ชม.';
    } else if (hours > 0) {
      return '$hours ชม. $minutes นาที $seconds วิ';
    } else if (minutes > 0) {
      return '$minutes นาที $seconds วิ';
    } else {
      return '$seconds วินาที';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _isExpired;
    final remainingText = _formatRemainingTime();
    final itemTitle = widget.bookingData.item.title;

    final primaryBg = isExpired ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final borderColor = isExpired ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
    final accentColor = isExpired ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    return Container(
      key: const ValueKey('chat-active-rental-banner'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primaryBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon แสดงสถานะ
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: FaIcon(
              isExpired
                  ? FontAwesomeIcons.triangleExclamation
                  : FontAwesomeIcons.clock,
              size: 14,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 8),

          // รายละเอียดการเช่า & เวลานับถอยหลัง
          Expanded(
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'กำลังเช่า: $itemTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (widget.bookingId != null && widget.bookingId! > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            '#YM-${widget.bookingId.toString().padLeft(5, '0')}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        isExpired
                            ? FontAwesomeIcons.triangleExclamation
                            : FontAwesomeIcons.stopwatch,
                        size: 10,
                        color: isExpired
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF15803D),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isExpired
                              ? 'ถึงกำหนดคืนแล้ว กรุณาส่งคืน'
                              : 'เหลืออีก: $remainingText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            fontWeight:
                                isExpired ? FontWeight.w700 : FontWeight.w500,
                            color: isExpired
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 6),

          // ปุ่มลัดดูสถานะการเช่า
          InkWell(
            key: const ValueKey('chat-banner-status-button'),
            onTap: () => AppRoutes.openRentalStatus(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(
                    FontAwesomeIcons.receipt,
                    size: 11,
                    color: Color(0xFF475569),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'สถานะ',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 5),

          // ปุ่มลัดไปหน้าคืนของ
          InkWell(
            key: const ValueKey('chat-banner-return-button'),
            onTap: () {
              AppRoutes.openRentalReturn(
                context,
                rentalId: widget.bookingId,
                isLender: widget.isOwner,
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: isExpired
                    ? const Color(0xFFDC2626)
                    : (widget.isOwner ? const Color(0xFF10B981) : AppColors.primaryColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(
                    widget.isOwner
                        ? FontAwesomeIcons.qrcode
                        : FontAwesomeIcons.arrowRotateLeft,
                    size: 11,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.isOwner
                        ? 'รับคืน'
                        : (isExpired ? 'คืนด่วน' : 'คืนของ'),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

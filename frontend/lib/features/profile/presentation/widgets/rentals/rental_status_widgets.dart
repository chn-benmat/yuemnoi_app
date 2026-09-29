import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/rental_countdown_timer_widget.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/rental_booking.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Model
// ─────────────────────────────────────────────────────────────────────────────

class RentalStatusItemData {
  final int? bookingId;
  final int? itemId;
  final String title;
  final String ownerName;
  final String? ownerPhone;
  final String partnerRole;
  final String status;
  final String statusCode;
  final Color statusColor;
  final IconData iconData;
  final String? imageUrl;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? duration;
  final int? totalPrice;
  final String? pickupLocation;

  const RentalStatusItemData({
    this.bookingId,
    this.itemId,
    required this.title,
    required this.ownerName,
    this.ownerPhone,
    this.partnerRole = 'เจ้าของอุปกรณ์',
    required this.status,
    this.statusCode = 'pending',
    required this.statusColor,
    required this.iconData,
    this.imageUrl,
    this.startDate,
    this.endDate,
    this.duration,
    this.totalPrice,
    this.pickupLocation,
  });

  factory RentalStatusItemData.fromEntity(
    RentalBooking entity,
    Color statusColor,
    IconData iconData,
  ) {
    return RentalStatusItemData(
      bookingId: entity.bookingId,
      itemId: entity.itemId,
      title: entity.title,
      ownerName: entity.partnerName,
      ownerPhone: entity.partnerPhone,
      partnerRole: entity.partnerRole,
      status: entity.status,
      statusCode: entity.statusCode,
      statusColor: statusColor,
      iconData: iconData,
      imageUrl: entity.imageUrl,
      startDate: entity.startDate,
      endDate: entity.endDate,
      duration: entity.duration,
      totalPrice: entity.totalPrice.toInt(),
      pickupLocation: entity.pickupLocation,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading Skeleton
// ─────────────────────────────────────────────────────────────────────────────

class RentalStatusLoadingSkeleton extends StatelessWidget {
  const RentalStatusLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (context, i) => const SizedBox(height: 14),
        itemBuilder: (context, index) => Container(
          height: 140,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const SkeletonBox(width: 70, height: 70, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(height: 16, borderRadius: 8),
                        SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.6,
                          child: SkeletonBox(height: 12, borderRadius: 6),
                        ),
                        SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.4,
                          child: SkeletonBox(height: 10, borderRadius: 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SkeletonBox(width: 70, height: 26, borderRadius: 14),
                ],
              ),
              const Spacer(),
              const SkeletonBox(height: 36, borderRadius: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty View
// ─────────────────────────────────────────────────────────────────────────────

class RentalStatusEmptyView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String actionLabel;

  const RentalStatusEmptyView({
    super.key,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel = 'ค้นหาอุปกรณ์เพื่อเช่า',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assignment_outlined,
                color: AppColors.primaryColor,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: AppColors.hintTextColor,
                height: 1.5,
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  elevation: 0,
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List Widget
// ─────────────────────────────────────────────────────────────────────────────

class RentalStatusList extends StatelessWidget {
  final List<RentalStatusItemData> items;
  final Future<void> Function()? onRefresh;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onEmptyAction;
  final String emptyActionLabel;

  const RentalStatusList({
    super.key,
    required this.items,
    this.onRefresh,
    this.emptyTitle = 'ยังไม่มีรายการเช่าอุปกรณ์',
    this.emptyMessage = 'เมื่อคุณทำการยืนยันเช่าอุปกรณ์ รายการจะแสดงที่นี่',
    this.onEmptyAction,
    this.emptyActionLabel = 'ค้นหาอุปกรณ์เพื่อเช่า',
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      final emptyChild = RentalStatusEmptyView(
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction ?? () => AppRoutes.openHome(context),
      );
      if (onRefresh != null) {
        return RefreshIndicator(
          color: AppColors.primaryColor,
          onRefresh: onRefresh!,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: emptyChild,
              ),
            ],
          ),
        );
      }
      return emptyChild;
    }

    final listView = ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, i) => const SizedBox(height: 14),
      itemBuilder: (context, index) => RentalStatusCard(item: items[index]),
    );

    if (onRefresh != null) {
      return RefreshIndicator(
        color: AppColors.primaryColor,
        onRefresh: onRefresh!,
        child: listView,
      );
    }

    return listView;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card Widget
// ─────────────────────────────────────────────────────────────────────────────

DateTime _computeEffectiveRentalEnd(RentalStatusItemData item) {
  final initialEnd = item.endDate;
  final handoverStart = BookingConfirmationTracker.getHandoverStartTimeSync(
    bookingId: item.bookingId,
  );

  Duration duration = const Duration(days: 1);
  if (item.startDate != null && item.endDate != null) {
    final diff = item.endDate!.difference(item.startDate!);
    if (diff > Duration.zero) {
      duration = diff;
    }
  }

  final now = DateTime.now();

  if (handoverStart != null) {
    return handoverStart.add(duration);
  }

  if (initialEnd != null && initialEnd.isBefore(now)) {
    return now.add(duration);
  }

  return initialEnd ?? now.add(duration);
}

class RentalStatusCard extends StatelessWidget {
  final RentalStatusItemData item;
  const RentalStatusCard({super.key, required this.item});

  void _openTrackingMap(BuildContext context) {
    final isOwner = item.partnerRole == 'ผู้เช่า';
    AppRoutes.openRentalTrackingMap(
      context,
      isOwner: isOwner,
      trackingArgs: {
        'itemTitle': item.title,
        'itemImageUrl': item.imageUrl,
        'pickupLocation': item.pickupLocation,
        'ownerName': item.ownerName,
        'ownerPhone': item.ownerPhone,
        'periodText': item.duration,
        'totalPrice': item.totalPrice?.toDouble(),
        'statusCode': item.statusCode,
        'bookingId': item.bookingId,
        'isOwner': isOwner,
      },
    );
  }

  void _showDetailModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) => _RentalStatusDetailSheet(item: item),
    );
  }

  Widget _buildStatusBadge(RentalStatusItemData item) {
    final status = item.statusCode.toLowerCase().trim();
    Color bg;
    Color fg;
    BorderSide border;

    switch (status) {
      case 'pending':
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFB45309);
        border = const BorderSide(color: Color(0xFFFDE68A));
        break;
      case 'confirmed':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        border = const BorderSide(color: Color(0xFFBFDBFE));
        break;
      case 'active':
        final effectiveEnd = _computeEffectiveRentalEnd(item);
        final isOverdue = DateTime.now().isAfter(effectiveEnd);
        if (isOverdue) {
          bg = const Color(0xFFFEF2F2);
          fg = const Color(0xFFDC2626);
          border = const BorderSide(color: Color(0xFFFECACA));
        } else {
          bg = const Color(0xFFF5F3FF);
          fg = AppColors.primaryColor;
          border = const BorderSide(color: Color(0xFFDDD6FE));
        }
        break;
      case 'completed':
      case 'finished':
        bg = const Color(0xFFF0FDF4);
        fg = const Color(0xFF15803D);
        border = const BorderSide(color: Color(0xFFBBF7D0));
        break;
      case 'cancelled':
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFB91C1C);
        border = const BorderSide(color: Color(0xFFFECACA));
        break;
      default:
        bg = const Color(0xFFF8FAFC);
        fg = const Color(0xFF475569);
        border = const BorderSide(color: Color(0xFFE2E8F0));
    }

    final effectiveEnd = _computeEffectiveRentalEnd(item);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.fromBorderSide(border),
      ),
      child: Text(
        (status == 'active' && DateTime.now().isAfter(effectiveEnd))
            ? '⚠️ เลยกำหนดคืน'
            : item.status,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showDetailModal(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // ── Top row: image + info + status ────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 66,
                      height: 66,
                      color: const Color(0xFFF1F5F9),
                      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: const Color(0xFFF1F5F9),
                                child: Icon(
                                  item.iconData,
                                  color: const Color(0xFF94A3B8),
                                  size: 24,
                                ),
                              ),
                              errorWidget: (context, url, err) => Container(
                                color: const Color(0xFFF1F5F9),
                                child: Icon(
                                  item.iconData,
                                  color: const Color(0xFF94A3B8),
                                  size: 24,
                                ),
                              ),
                            )
                          : Icon(
                              item.iconData,
                              color: const Color(0xFF94A3B8),
                              size: 24,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Product info
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${item.partnerRole}: ${item.ownerName}',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.duration != null || item.totalPrice != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (item.duration != null &&
                                  item.duration!.isNotEmpty) ...[
                                Text(
                                  item.duration!,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                              if (item.duration != null &&
                                  item.duration!.isNotEmpty &&
                                  item.totalPrice != null)
                                const Text(
                                  ' • ',
                                  style: TextStyle(
                                    color: Color(0xFFCBD5E1),
                                    fontSize: 11,
                                  ),
                                ),
                              if (item.totalPrice != null)
                                Text(
                                  '฿${item.totalPrice}',
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  _buildStatusBadge(item),
                ],
              ),

              // ── วิดเจ็ตนับเวลาถอยหลังการส่งคืน / ติดตามเวลาเลท (เมื่อสถานะเป็น active) ──
              if (item.statusCode.toLowerCase() == 'active') ...[
                const SizedBox(height: 10),
                RentalCountdownTimerWidget(
                  endDateTime: _computeEffectiveRentalEnd(item),
                  startDateTime: item.startDate,
                  isCompact: false,
                ),
              ],

              const SizedBox(height: 12),
              // ── Tracking route & action button ─────────────────────────────
              if (item.statusCode.toLowerCase() == 'active') ...[
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () {
                      AppRoutes.openRentalReturn(
                        context,
                        rentalId: item.bookingId,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'ส่งคืนอุปกรณ์',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => _openTrackingMap(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(
                      Icons.near_me_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'ดูเส้นทางนัดรับ & ตรวจรับของ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rental Status Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RentalStatusDetailSheet extends StatelessWidget {
  final RentalStatusItemData item;
  const _RentalStatusDetailSheet({required this.item});

  int _currentStepIndex() {
    switch (item.statusCode.toLowerCase()) {
      case 'cancelled':
        return -1;
      case 'completed':
      case 'finished':
        return 3;
      case 'active':
        return 2;
      case 'confirmed':
        return 1;
      case 'pending':
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = _currentStepIndex();
    final isCancelled = currentStep == -1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Sheet Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'รายละเอียดสถานะการเช่า',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E2022),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Item preview card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 54,
                      height: 54,
                      color: const Color(0xFFF3E8FF),
                      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Icon(
                                item.iconData,
                                color: AppColors.primaryColor,
                                size: 26,
                              ),
                            )
                          : Icon(
                              item.iconData,
                              color: AppColors.primaryColor,
                              size: 26,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1E2022),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${item.partnerRole}: ${item.ownerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            color: Color(0xFF777A7C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.totalPrice != null)
                    Text(
                      '฿${item.totalPrice}',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.primaryColor,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (isCancelled) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFCDD2)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.cancel_outlined,
                      color: Color(0xFFC62828),
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'รายการเช่านี้ถูกยกเลิกแล้ว',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Rental Details Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  if (item.bookingId != null) ...[
                    _buildInfoRow('รหัสคำขอเช่า', '#${item.bookingId}'),
                    const Divider(height: 16),
                  ],
                  _buildInfoRow('สถานะปัจจุบัน', item.status, valueColor: item.statusColor),
                  if (item.startDate != null && item.endDate != null) ...[
                    const Divider(height: 16),
                    _buildInfoRow(
                      'ระยะเวลาเช่า',
                      '${_formatDate(item.startDate!)} - ${_formatDate(item.endDate!)}',
                    ),
                  ],
                  if (item.pickupLocation != null && item.pickupLocation!.isNotEmpty) ...[
                    const Divider(height: 16),
                    _buildInfoRow('สถานที่นัดรับ', item.pickupLocation!),
                  ],
                  if (item.totalPrice != null) ...[
                    const Divider(height: 16),
                    _buildInfoRow(
                      'ยอดรวมทั้งหมด',
                      '฿${item.totalPrice}',
                      valueColor: AppColors.primaryColor,
                      isBold: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── วิดเจ็ตนับเวลาถอยหลังการส่งคืน / ติดตามเวลาส่งคืนเลท ในหน้า Sheet ──
            if (item.statusCode.toLowerCase() == 'active') ...[
              RentalCountdownTimerWidget(
                endDateTime: _computeEffectiveRentalEnd(item),
                startDateTime: item.startDate,
                isCompact: false,
              ),
              const SizedBox(height: 16),
            ],
            // Actions
            if (item.statusCode.toLowerCase() == 'active') ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    AppRoutes.openRentalReturn(
                      context,
                      rentalId: item.bookingId,
                    );
                  },
                  icon: const Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'ดำเนินการส่งคืนอุปกรณ์',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (item.pickupLocation != null && item.pickupLocation!.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    final isOwner = item.partnerRole == 'ผู้เช่า';
                    AppRoutes.openRentalTrackingMap(
                      context,
                      isOwner: isOwner,
                      trackingArgs: {
                        'itemTitle': item.title,
                        'itemImageUrl': item.imageUrl,
                        'pickupLocation': item.pickupLocation,
                        'ownerName': item.ownerName,
                        'periodText': item.duration,
                        'totalPrice': item.totalPrice?.toDouble(),
                        'statusCode': item.statusCode,
                        'bookingId': item.bookingId,
                        'isOwner': isOwner,
                      },
                    );
                  },
                  icon: Icon(
                    item.statusCode.toLowerCase() == 'active'
                        ? Icons.inventory_2_outlined
                        : Icons.near_me_rounded,
                    size: 18,
                  ),
                  label: Text(
                    item.statusCode.toLowerCase() == 'active'
                        ? 'ดูรายละเอียดการเช่า'
                        : 'ดูเส้นทางนัดรับ & ตรวจรับของ',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (item.itemId != null) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    side: const BorderSide(color: Color(0xFFD8B4FE)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    AppRoutes.openItemDetail(context, itemId: item.itemId!);
                  },
                  child: const Text(
                    'ดูรายละเอียดอุปกรณ์',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12,
            color: Color(0xFF777A7C),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? const Color(0xFF1E2022),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    try {
      return DateFormat('d MMM yyyy', 'th').format(date.toLocal());
    } catch (_) {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}


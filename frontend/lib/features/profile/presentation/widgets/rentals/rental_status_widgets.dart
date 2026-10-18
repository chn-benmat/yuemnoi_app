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
  final String category;
  final bool isOwner;

  const RentalStatusItemData({
    this.bookingId,
    this.itemId,
    required this.title,
    required this.ownerName,
    this.ownerPhone,
    this.partnerRole = 'เจ้าของอุปกรณ์',
    required this.status,
    this.statusCode = 'confirmed',
    required this.statusColor,
    required this.iconData,
    this.imageUrl,
    this.startDate,
    this.endDate,
    this.duration,
    this.totalPrice,
    this.pickupLocation,
    this.category = 'ทั่วไป',
    this.isOwner = false,
  });

  bool get isPending {
    final code = statusCode.toLowerCase().trim();
    return code == 'pending' ||
        status.contains('รอการยืนยัน') ||
        status.contains('มีคำขอเช่าใหม่') ||
        status.contains('รอดำเนินการ');
  }

  bool get isActive {
    final code = statusCode.toLowerCase().trim();
    return code == 'active' ||
        code == 'in_use' ||
        code == 'ongoing' ||
        status.contains('กำลังเช่า') ||
        status.contains('กำลังใช้งาน');
  }

  bool get isConfirmed {
    final code = statusCode.toLowerCase().trim();
    return code == 'confirmed' || status.contains('ยืนยัน') || status.contains('นัดรับ');
  }

  bool get isCompleted {
    final code = statusCode.toLowerCase().trim();
    return code == 'completed' ||
        code == 'finished' ||
        status.contains('เสร็จสิ้น') ||
        status.contains('คืนแล้ว');
  }

  bool get isCancelled {
    final code = statusCode.toLowerCase().trim();
    return code == 'cancelled' || status.contains('ยกเลิก');
  }

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
      category: entity.category ?? 'ทั่วไป',
      isOwner: entity.isOwner,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (context, i) => const SizedBox(height: 14),
        itemBuilder: (context, index) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 74, height: 74, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 80, height: 12, borderRadius: 6),
                        SizedBox(height: 8),
                        SkeletonBox(height: 16, borderRadius: 8),
                        SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.65,
                          child: SkeletonBox(height: 12, borderRadius: 6),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const SkeletonBox(width: 68, height: 24, borderRadius: 12),
                ],
              ),
              const SizedBox(height: 12),
              const SkeletonBox(height: 38, borderRadius: 10),
              const SizedBox(height: 12),
              const SkeletonBox(height: 42, borderRadius: 12),
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
  final IconData icon;

  const RentalStatusEmptyView({
    super.key,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel = 'ค้นหาอุปกรณ์เพื่อเช่า',
    this.icon = Icons.inventory_2_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
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
              child: Icon(
                icon,
                color: AppColors.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
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
// List Widget with Interactive Sub-Filters & Urgency Banner
// ─────────────────────────────────────────────────────────────────────────────

class RentalStatusList extends StatefulWidget {
  final List<RentalStatusItemData> items;
  final Future<void> Function()? onRefresh;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onEmptyAction;
  final String emptyActionLabel;
  final bool isLender;

  const RentalStatusList({
    super.key,
    required this.items,
    this.onRefresh,
    this.emptyTitle = 'ยังไม่มีรายการเช่าอุปกรณ์',
    this.emptyMessage = 'เมื่อคุณทำการยืนยันเช่าอุปกรณ์ รายการจะแสดงที่นี่',
    this.onEmptyAction,
    this.emptyActionLabel = 'ค้นหาอุปกรณ์เพื่อเช่า',
    this.isLender = false,
  });

  @override
  State<RentalStatusList> createState() => _RentalStatusListState();
}

class _RentalStatusListState extends State<RentalStatusList> {
  String _activeFilter = 'all'; // all, pending, confirmed, active, completed

  List<RentalStatusItemData> get _filteredItems {
    if (_activeFilter == 'pending') {
      return widget.items.where((it) => it.isPending).toList();
    }
    if (_activeFilter == 'confirmed') {
      return widget.items.where((it) => it.isConfirmed).toList();
    }
    if (_activeFilter == 'active') {
      return widget.items.where((it) => it.isActive).toList();
    }
    if (_activeFilter == 'completed') {
      return widget.items.where((it) => it.isCompleted || it.isCancelled).toList();
    }
    return widget.items;
  }

  int get _countPending => widget.items.where((it) => it.isPending).length;
  int get _countConfirmed => widget.items.where((it) => it.isConfirmed).length;
  int get _countActive => widget.items.where((it) => it.isActive).length;
  int get _countCompleted =>
      widget.items.where((it) => it.isCompleted || it.isCancelled).length;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      final emptyChild = RentalStatusEmptyView(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
        actionLabel: widget.emptyActionLabel,
        onAction: widget.onEmptyAction ?? () => AppRoutes.openHome(context),
      );
      if (widget.onRefresh != null) {
        return RefreshIndicator(
          color: AppColors.primaryColor,
          backgroundColor: Colors.white,
          onRefresh: widget.onRefresh!,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: emptyChild,
              ),
            ],
          ),
        );
      }
      return emptyChild;
    }

    final filtered = _filteredItems;

    // หา item ที่กำลังใช้งานตัวแรกเพื่อแสดง Banner ด่วน
    final activeUrgentItem = widget.items.where((it) => it.isActive).firstOrNull;

    final content = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // ── 1. Status Filter Pills Bar ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildFilterChip('all', 'ทั้งหมด', widget.items.length),
                  const SizedBox(width: 8),
                  if (_countPending > 0 || _activeFilter == 'pending') ...[
                    _buildFilterChip('pending', 'รอการยืนยัน', _countPending,
                        activeColor: const Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                  ],
                  _buildFilterChip('confirmed', 'รอนัดรับ', _countConfirmed,
                      activeColor: const Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  _buildFilterChip('active', 'กำลังใช้งาน', _countActive,
                      activeColor: const Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  _buildFilterChip('completed', 'เสร็จสิ้น', _countCompleted,
                      activeColor: const Color(0xFF64748B)),
                ],
              ),
            ),
          ),
        ),

        // ── 2. Urgent Active Alert Banner (ถ้ามีอุปกรณ์ที่กำลังเช่าอยู่) ──
        if (activeUrgentItem != null &&
            _activeFilter != 'completed' &&
            _activeFilter != 'pending') ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _buildActiveUrgencyBanner(context, activeUrgentItem),
            ),
          ),
        ],

        // ── 3. List of Rental Cards ──
        if (filtered.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: RentalStatusEmptyView(
                title: 'ไม่มีรายการในหมวดนี้',
                message: 'ไม่พบรายการอุปกรณ์ตามตัวกรองที่คุณเลือก',
                actionLabel: 'ดูทั้งหมด',
                onAction: () => setState(() => _activeFilter = 'all'),
              ),
            ),
          ),
        ] else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = filtered[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: RentalStatusCard(item: item),
                  );
                },
                childCount: filtered.length,
              ),
            ),
          ),
        ],
      ],
    );

    if (widget.onRefresh != null) {
      return RefreshIndicator(
        color: AppColors.primaryColor,
        backgroundColor: Colors.white,
        onRefresh: widget.onRefresh!,
        child: content,
      );
    }

    return content;
  }

  Widget _buildFilterChip(
    String key,
    String label,
    int count, {
    Color activeColor = AppColors.primaryColor,
  }) {
    final isSelected = _activeFilter == key;

    return InkWell(
      onTap: () => setState(() => _activeFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.24)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveUrgencyBanner(
    BuildContext context,
    RentalStatusItemData item,
  ) {
    final effectiveEnd = _computeEffectiveRentalEnd(item);
    final now = DateTime.now();
    final isOverdue = now.isAfter(effectiveEnd);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOverdue ? const Color(0xFFFEF2F2) : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue ? const Color(0xFFFECACA) : const Color(0xFFDDD6FE),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isOverdue ? const Color(0xFFFEE2E2) : const Color(0xFFEDE9FE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOverdue ? Icons.warning_amber_rounded : Icons.timer_outlined,
              color: isOverdue ? const Color(0xFFDC2626) : AppColors.primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOverdue ? 'เลยกำหนดส่งคืนอุปกรณ์!' : 'กำลังใช้งานอยู่ขณะนี้',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isOverdue
                        ? const Color(0xFFB91C1C)
                        : AppColors.primaryColor,
                  ),
                ),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              AppRoutes.openRentalReturn(
                context,
                rentalId: item.bookingId,
                isLender: item.isOwner,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isOverdue ? const Color(0xFFDC2626) : AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(
              item.isOwner ? 'ตรวจรับคืน' : 'ส่งคืนอุปกรณ์',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card Widget (Clean Shopee/SaaS Hybrid Style)
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

  bool _isItemOverdue(RentalStatusItemData item) {
    if (!item.isActive) return false;
    final now = DateTime.now();
    DateTime? effectiveEnd = item.endDate;
    if (effectiveEnd == null && item.startDate != null) {
      effectiveEnd = item.startDate!.add(const Duration(days: 1));
    }
    return effectiveEnd != null && now.isAfter(effectiveEnd);
  }

  Widget _buildStatusBadge(RentalStatusItemData item) {
    final status = item.statusCode.toLowerCase().trim();
    final isOverdue = _isItemOverdue(item);

    Color bg;
    Color fg;
    Color border;
    IconData badgeIcon;
    String badgeText = item.status;

    if (isOverdue) {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
      border = const Color(0xFFFECACA);
      badgeIcon = Icons.warning_amber_rounded;
      badgeText = 'เลยกำหนดคืน';
    } else {
      switch (status) {
        case 'pending':
          bg = const Color(0xFFFFFBEB);
          fg = const Color(0xFFD97706);
          border = const Color(0xFFFDE68A);
          badgeIcon = Icons.hourglass_top_rounded;
          badgeText = item.status.isNotEmpty ? item.status : 'รอการยืนยัน';
          break;
        case 'confirmed':
          bg = const Color(0xFFEFF6FF);
          fg = const Color(0xFF1D4ED8);
          border = const Color(0xFFBFDBFE);
          badgeIcon = Icons.handshake_outlined;
          badgeText = 'นัดรับอุปกรณ์';
          break;
        case 'active':
          bg = const Color(0xFFECFDF5);
          fg = const Color(0xFF059669);
          border = const Color(0xFFA7F3D0);
          badgeIcon = Icons.play_circle_outline_rounded;
          badgeText = 'กำลังใช้งาน';
          break;
        case 'completed':
        case 'finished':
          bg = const Color(0xFFF8FAFC);
          fg = const Color(0xFF475569);
          border = const Color(0xFFE2E8F0);
          badgeIcon = Icons.check_circle_outline_rounded;
          badgeText = 'เสร็จสิ้น';
          break;
        case 'cancelled':
          bg = const Color(0xFFFEF2F2);
          fg = const Color(0xFFB91C1C);
          border = const Color(0xFFFECACA);
          badgeIcon = Icons.cancel_outlined;
          badgeText = 'ยกเลิกแล้ว';
          break;
        default:
          bg = const Color(0xFFF8FAFC);
          fg = const Color(0xFF475569);
          border = const Color(0xFFE2E8F0);
          badgeIcon = Icons.info_outline_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeHighlightBox(RentalStatusItemData item) {
    if (!item.isActive) return const SizedBox.shrink();

    final now = DateTime.now();
    DateTime? effectiveEnd = item.endDate;
    if (effectiveEnd == null && item.startDate != null) {
      effectiveEnd = item.startDate!.add(const Duration(days: 1));
    }

    final isExpired = effectiveEnd != null && now.isAfter(effectiveEnd);
    final bgColor = isExpired ? const Color(0xFFFEF2F2) : const Color(0xFFF5F3FF);
    final borderColor = isExpired ? const Color(0xFFFECACA) : const Color(0xFFDDD6FE);
    final accentColor = isExpired ? const Color(0xFFDC2626) : AppColors.primaryColor;

    String statusText;
    if (effectiveEnd == null) {
      statusText = 'กำลังอยู่ในระหว่างการเช่าอุปกรณ์ตามกำหนด';
    } else if (isExpired) {
      final diff = now.difference(effectiveEnd);
      final diffText = _formatDurationDiff(diff);
      statusText = 'เลยกำหนดส่งคืนแล้ว $diffText (กรุณาส่งคืนด่วน)';
    } else {
      final diff = effectiveEnd.difference(now);
      final diffText = _formatDurationDiff(diff);
      final deadlineStr = _formatDeadlineTime(effectiveEnd);
      statusText = 'ครบกำหนด: $deadlineStr (เหลืออีก $diffText)';
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Row(
        children: [
          Icon(
            isExpired ? Icons.warning_rounded : Icons.schedule_rounded,
            size: 14,
            color: accentColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11.5,
                fontWeight: isExpired ? FontWeight.w700 : FontWeight.w600,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDurationDiff(Duration diff) {
    if (diff.inDays > 0) {
      final hours = diff.inHours % 24;
      return hours > 0 ? '${diff.inDays} วัน $hours ชม.' : '${diff.inDays} วัน';
    } else if (diff.inHours > 0) {
      final mins = diff.inMinutes % 60;
      return mins > 0 ? '${diff.inHours} ชม. $mins นาที' : '${diff.inHours} ชม.';
    } else {
      final mins = diff.inMinutes;
      return '${mins > 0 ? mins : 1} นาที';
    }
  }

  String _formatDeadlineTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final timeStr = '${DateFormat('HH:mm').format(dt)} น.';
    if (isToday) {
      return 'วันนี้ $timeStr';
    }
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = dt.year == tomorrow.year && dt.month == tomorrow.month && dt.day == tomorrow.day;
    if (isTomorrow) {
      return 'พรุ่งนี้ $timeStr';
    }
    try {
      return '${DateFormat('d MMM', 'th').format(dt)} $timeStr';
    } catch (_) {
      return '${dt.day}/${dt.month} $timeStr';
    }
  }

  String _formatRentalDates(RentalStatusItemData item) {
    if (item.startDate == null || item.endDate == null) {
      return item.duration?.isNotEmpty == true ? item.duration! : 'ระยะเวลาตามสัญญา';
    }
    try {
      final f = DateFormat('d MMM', 'th');
      final s = f.format(item.startDate!.toLocal());
      final e = f.format(item.endDate!.toLocal());
      if (item.duration != null && item.duration!.isNotEmpty) {
        return '$s - $e (${item.duration})';
      }
      return '$s - $e';
    } catch (_) {
      return '${item.startDate!.day}/${item.startDate!.month} - ${item.endDate!.day}/${item.endDate!.month}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetailModal(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Top Section: Image + Info + Status Badge ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: const Color(0xFFF1F5F9),
                                  child: Center(
                                    child: Icon(
                                      item.iconData,
                                      color: const Color(0xFF94A3B8),
                                      size: 26,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, err) => Container(
                                  color: const Color(0xFFF1F5F9),
                                  child: Icon(
                                    item.iconData,
                                    color: const Color(0xFF94A3B8),
                                    size: 26,
                                  ),
                                ),
                              )
                            : Icon(
                                item.iconData,
                                color: const Color(0xFF94A3B8),
                                size: 28,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Product Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.bookingId != null) ...[
                            Text(
                              '#BK${item.bookingId} • ${item.category}',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                item.partnerRole.contains('เจ้าของ')
                                    ? Icons.storefront_outlined
                                    : Icons.person_outline_rounded,
                                size: 13,
                                color: const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${item.partnerRole}: ${item.ownerName}',
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
                    const SizedBox(width: 8),
                    _buildStatusBadge(item),
                  ],
                ),

                // ── 2. Time Countdown Highlight (if active) ──
                _buildTimeHighlightBox(item),

                // ── 3. Pickup Location Pin (if confirmed) ──
                if (item.isConfirmed &&
                    item.pickupLocation != null &&
                    item.pickupLocation!.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13.5,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'นัดรับที่: ${item.pickupLocation!}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // ── 4. Period & Pricing Bar ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 12.5,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatRentalDates(item),
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (item.totalPrice != null) ...[
                        Text(
                          '฿${item.totalPrice}',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── 5. Action Buttons Row ──
                Row(
                  children: [
                    // Primary Action
                    Expanded(
                      child: item.isActive
                          ? ElevatedButton.icon(
                              onPressed: () {
                                AppRoutes.openRentalReturn(
                                  context,
                                  rentalId: item.bookingId,
                                  isLender: item.isOwner,
                                );
                              },
                              icon: Icon(
                                item.isOwner
                                    ? Icons.qr_code_2_rounded
                                    : Icons.assignment_turned_in_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                              label: Text(
                                item.isOwner
                                    ? 'ตรวจรับของคืน & สแกน QR'
                                    : 'ส่งคืนอุปกรณ์ (ถ่ายภาพ)',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: item.isOwner
                                    ? const Color(0xFF10B981)
                                    : AppColors.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            )
                          : item.isConfirmed
                              ? ElevatedButton.icon(
                                  onPressed: () => _openTrackingMap(context),
                                  icon: const Icon(
                                    Icons.near_me_outlined,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'ดูจุดนัดรับ & เส้นทาง',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                )
                              : item.isPending
                                  ? item.isOwner
                                      ? ElevatedButton.icon(
                                          onPressed: () => _showDetailModal(context),
                                          icon: const Icon(
                                            Icons.assignment_ind_outlined,
                                            size: 15,
                                            color: Colors.white,
                                          ),
                                          label: const Text(
                                            'ตรวจสอบคำขอเช่า',
                                            style: TextStyle(
                                              fontFamily: AppTextStyles.fontFamily,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFF59E0B),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                          ),
                                        )
                                      : OutlinedButton.icon(
                                          onPressed: () => _showDetailModal(context),
                                          icon: const Icon(
                                            Icons.hourglass_empty_rounded,
                                            size: 15,
                                            color: Color(0xFFD97706),
                                          ),
                                          label: const Text(
                                            'รอการยืนยันจากเจ้าของ',
                                            style: TextStyle(
                                              fontFamily: AppTextStyles.fontFamily,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFD97706),
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFFFBEB),
                                            side: const BorderSide(
                                              color: Color(0xFFFDE68A),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                          ),
                                        )
                                  : OutlinedButton(
                                      onPressed: () => _showDetailModal(context),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.primaryColor,
                                        side: const BorderSide(
                                          color: Color(0xFFE2E8F0),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                      child: const Text(
                                        'ดูรายละเอียดการเช่า',
                                        style: TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                    ),
                    const SizedBox(width: 8),
                    // Secondary detail button
                    Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => _showDetailModal(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
        child: SingleChildScrollView(
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

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'รายละเอียดสถานะการเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Step-by-Step Progress Stepper
              if (!isCancelled) ...[
                _buildTimelineStepper(currentStep),
                const SizedBox(height: 16),
              ],

              // Item Preview Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 56,
                        height: 56,
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
                              fontSize: 14.5,
                              color: Color(0xFF0F172A),
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
                              color: Color(0xFF64748B),
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

              const SizedBox(height: 14),

              if (isCancelled) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'รายการเช่านี้ถูกยกเลิกแล้ว',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Rental Details Info Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    if (item.bookingId != null) ...[
                      _buildInfoRow('รหัสคำขอเช่า', '#BK${item.bookingId}'),
                      const Divider(height: 16, color: Color(0xFFF1F5F9)),
                    ],
                    _buildInfoRow('สถานะปัจจุบัน', item.status, valueColor: item.statusColor),
                    if (item.startDate != null && item.endDate != null) ...[
                      const Divider(height: 16, color: Color(0xFFF1F5F9)),
                      _buildInfoRow(
                        'ระยะเวลาเช่า',
                        '${_formatDate(item.startDate!)} - ${_formatDate(item.endDate!)}',
                      ),
                    ],
                    if (item.pickupLocation != null && item.pickupLocation!.isNotEmpty) ...[
                      const Divider(height: 16, color: Color(0xFFF1F5F9)),
                      _buildInfoRow('สถานที่นัดรับ', item.pickupLocation!),
                    ],
                    if (item.totalPrice != null) ...[
                      const Divider(height: 16, color: Color(0xFFF1F5F9)),
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

              // วิดเจ็ตนับเวลาถอยหลัง (ถ้า Active)
              if (item.isActive) ...[
                RentalCountdownTimerWidget(
                  endDateTime: _computeEffectiveRentalEnd(item),
                  startDateTime: item.startDate,
                  isCompact: false,
                ),
                const SizedBox(height: 16),
              ],

              // Actions
              if (item.isActive) ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: item.isOwner
                          ? const Color(0xFF10B981)
                          : AppColors.primaryColor,
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
                        isLender: item.isOwner,
                      );
                    },
                    icon: Icon(
                      item.isOwner
                          ? Icons.qr_code_2_rounded
                          : Icons.assignment_turned_in_outlined,
                      size: 18,
                    ),
                    label: Text(
                      item.isOwner
                          ? 'ตรวจรับของคืน & สแกน QR'
                          : 'ดำเนินการส่งคืนอุปกรณ์',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              if (item.pickupLocation != null && item.pickupLocation!.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
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
                          'ownerPhone': item.ownerPhone,
                          'periodText': item.duration,
                          'totalPrice': item.totalPrice?.toDouble(),
                          'statusCode': item.statusCode,
                          'bookingId': item.bookingId,
                          'isOwner': isOwner,
                        },
                      );
                    },
                    icon: const Icon(Icons.near_me_rounded, size: 18),
                    label: const Text(
                      'ดูเส้นทางนัดรับ & แผนที่',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              if (item.itemId != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
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
                      'ดูรายละเอียดอุปกรณ์ต้นทาง',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
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

  Widget _buildTimelineStepper(int currentStep) {
    const steps = [
      'ส่งคำขอเช่า',
      'ยืนยันนัดรับ',
      'กำลังใช้งาน',
      'ส่งคืนเรียบร้อย',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _buildStepCircle(i, i <= currentStep, i == currentStep, steps[i]),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  color: i < currentStep
                      ? AppColors.primaryColor
                      : const Color(0xFFCBD5E1),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepCircle(
    int stepIndex,
    bool isCompletedOrCurrent,
    bool isCurrent,
    String label,
  ) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isCompletedOrCurrent
                ? (isCurrent && stepIndex == 0
                    ? const Color(0xFFF59E0B)
                    : AppColors.primaryColor)
                : const Color(0xFFE2E8F0),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompletedOrCurrent
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '${stepIndex + 1}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10,
            color: isCompletedOrCurrent
                ? const Color(0xFF0F172A)
                : const Color(0xFF94A3B8),
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
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
            fontSize: 12.5,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? const Color(0xFF0F172A),
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

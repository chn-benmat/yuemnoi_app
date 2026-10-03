import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/data/repositories/rental_management_repository_impl.dart';
import '../../../profile/domain/entities/rental_booking.dart';

/// แบบจำลองข้อมูลการแจ้งเตือนระบบและการอัปเดตแอปพลิเคชัน
class SystemNotificationItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final IconData icon;
  final String category;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SystemNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.icon = Icons.info_outline_rounded,
    this.category = 'ประกาศระบบ',
    this.actionLabel,
    this.onAction,
  });

  SystemNotificationItem copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? timestamp,
    bool? isRead,
    IconData? icon,
    String? category,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return SystemNotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      actionLabel: actionLabel ?? this.actionLabel,
      onAction: onAction ?? this.onAction,
    );
  }
}

/// หน้าจอการแจ้งเตือน (Notification Page)
/// สไตล์ Swiss Style & Clean SaaS:
/// - โทนสว่างสะอาด เรียบง่าย ใช้ 2 สีหลัก (ม่วง Yuemnoi 0xFF7400C9 และ Slate Ink 0xFF0F172A)
/// - แบ่ง 2 หมวดหมู่ชัดเจน:
///   1. ด้านบน: "สถานะอุปกรณ์" แสดงคำสั่งเช่า/ปล่อยเช่าที่อยู่ระหว่างดำเนินการ (รอการยืนยัน, รอการชำระ, รอการรับอุปกรณ์, กำลังเช่า, ต้องส่งคืน) โชว์ 2 รายการ
///      พร้อมปุ่ม "อ่านทั้งหมด" ด้านบนขวา ซึ่งเมื่อกดจะเปิดไปยังหน้า "สถานะการเช่า" (Rental Status)
///   2. ด้านล่าง: "อัปเดตและข้อความระบบ" แสดงประกาศ ข่าวสาร และความปลอดภัยของแอป
///      พร้อมปุ่ม "อ่านทั้งหมด" ด้านบนขวาสำหรับทำเครื่องหมายอ่านแล้ว
class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  bool _isLoading = true;
  List<RentalBooking> _activeRentals = [];
  final Set<String> _readItemIds = {};

  final List<SystemNotificationItem> _systemNotifications = [
    SystemNotificationItem(
      id: 'sys_1',
      title: 'ยินดีต้อนรับสู่ Yuemnoi',
      message:
          'เริ่มค้นหาอุปกรณ์ที่คุณต้องการหรือลงประกาศปล่อยเช่าอุปกรณ์ของคุณได้ง่ายๆ ปลอดภัยทุกการใช้งาน',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      icon: Icons.verified_user_outlined,
      category: 'ยินดีต้อนรับ',
      actionLabel: 'สำรวจอุปกรณ์',
    ),
    SystemNotificationItem(
      id: 'sys_2',
      title: 'การชำระเงินปลอดภัย',
      message:
          'ระบบมัดจำและเงินประกันถูกล็อคไว้อย่างปลอดภัยผ่าน Escrow Wallet จนกว่าจะส่งคืนอุปกรณ์เรียบร้อย',
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
      icon: Icons.shield_outlined,
      category: 'ความปลอดภัย & Escrow',
      actionLabel: 'ดูกระเป๋าเงิน',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    try {
      final userId = SupabaseConfig.isInitialized
          ? SupabaseConfig.client.auth.currentUser?.id
          : null;

      if (userId == null || userId.isEmpty) {
        if (mounted) {
          setState(() {
            _activeRentals = [];
            _isLoading = false;
          });
        }
        return;
      }

      final repo = RentalManagementRepositoryImpl();
      final rentingFuture = repo.getRentingBookings(userId);
      final lendingFuture = repo.getLendingBookings(userId);
      final results = await Future.wait([rentingFuture, lendingFuture]);

      final allBookings = [...results[0], ...results[1]];

      // ดึงสถานะที่อยู่ระหว่างดำเนินการ:
      // รอการยืนยัน, รอการชำระ, รอการรับอุปกรณ์, กำลังเช่า, ต้องส่งคืน
      final inProgress = allBookings.where((b) {
        final code = b.statusCode.toLowerCase().trim();
        return code != 'completed' &&
            code != 'finished' &&
            code != 'cancelled';
      }).toList();

      if (mounted) {
        setState(() {
          _activeRentals = inProgress;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToRentalStatus() {
    HapticFeedback.lightImpact();
    for (final r in _activeRentals) {
      if (r.bookingId != null) {
        _readItemIds.add('rental_${r.bookingId}');
      }
    }
    setState(() {});
    AppRoutes.openRentalStatus(context);
  }

  void _markSystemAsRead() {
    HapticFeedback.lightImpact();
    setState(() {
      for (final s in _systemNotifications) {
        _readItemIds.add(s.id);
      }
    });
    _showFeedbackToast('ทำเครื่องหมายอ่านแล้วข้อความระบบทั้งหมด');
  }

  void _showFeedbackToast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
  }

  bool _isItemRead(String id) {
    return _readItemIds.contains(id);
  }

  void _toggleItemRead(String id) {
    setState(() {
      if (_readItemIds.contains(id)) {
        _readItemIds.remove(id);
      } else {
        _readItemIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header (Swiss Style Typography & Refresh) ──
            _buildHeader(),

            // ── Main Content Stream (2 Sections Unified) ──
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primaryColor,
                backgroundColor: Colors.white,
                onRefresh: _fetchNotifications,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryColor,
                          strokeWidth: 2.2,
                        ),
                      )
                    : _buildContent(now),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. Header (Swiss Minimalist Clean Layout)
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: const Text(
        'การแจ้งเตือน',
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Content Router (หมวดบน: สถานะอุปกรณ์ | หมวดล่าง: อัปเดตแอพ)
  // ─────────────────────────────────────────────────────────────
  Widget _buildContent(DateTime now) {
    // แสดงเพียง 2 รายการสำหรับหมวดสถานะอุปกรณ์
    final displayedRentals = _activeRentals.take(2).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 110),
      children: [
        // ══════════════════════════════════════════════════════════
        // หมวดที่ 1 (จอบน): สถานะอุปกรณ์ (แสดงสูงสุด 2 รายการ)
        // ══════════════════════════════════════════════════════════
        _buildSectionHeaderWithAction(
          title: 'สถานะอุปกรณ์',
          count: _activeRentals.length,
          subtitle: 'ติดตามความคืบหน้าคำสั่งเช่าและสถานะอุปกรณ์',
          actionLabel: 'ดูทั้งหมด',
          onActionTap: _navigateToRentalStatus,
        ),
        const SizedBox(height: 10),
        if (displayedRentals.isNotEmpty)
          ...displayedRentals
              .map((item) => _buildEcommerceRentalCard(item, now))
        else
          _buildCompactEmptyState(
            title: 'ไม่มีรายการอุปกรณ์ที่กำลังดำเนินการ',
            subtitle: 'เมื่อมีคำสั่งเช่าหรืออัปเดตสถานะ ข้อมูลจะแสดงที่นี่',
            actionText: 'สำรวจอุปกรณ์เช่า',
            onAction: () => context.push(AppRoutes.search),
          ),

        const SizedBox(height: 28),

        // ══════════════════════════════════════════════════════════
        // หมวดที่ 2 (จอล่าง): อัปเดตและข้อความระบบ
        // ══════════════════════════════════════════════════════════
        _buildSectionHeaderWithAction(
          title: 'อัปเดตและข้อความระบบ',
          count: _systemNotifications.length,
          subtitle: 'ประกาศสำคัญ ความปลอดภัย และความคืบหน้าของแพลตฟอร์ม',
          actionLabel: 'อ่านทั้งหมด',
          onActionTap: _markSystemAsRead,
        ),
        const SizedBox(height: 10),
        if (_systemNotifications.isNotEmpty)
          ..._systemNotifications.map(_buildSystemCard)
        else
          _buildCompactEmptyState(
            title: 'ไม่มีประกาศระบบใหม่',
            subtitle: 'ข้อมูลอัปเดตและข่าวสารของ Yuemnoi จะแจ้งให้ทราบที่นี่',
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. Section Header พร้อมปุ่ม Action (ไม่มีไอคอน)
  // ─────────────────────────────────────────────────────────────
  Widget _buildSectionHeaderWithAction({
    required String title,
    required int count,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onActionTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // ปุ่ม Action บนขวาของหมวด (เช่น "ดูทั้งหมด" หรือ "อ่านทั้งหมด")
        InkWell(
          onTap: onActionTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. Compact Empty State สำหรับแต่ละหมวดหมู่
  // ─────────────────────────────────────────────────────────────
  Widget _buildCompactEmptyState({
    required String title,
    required String subtitle,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
            ),
            child: const Icon(
              Icons.inbox_outlined,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: const Color(0xFFDDD6FE), width: 0.8),
                ),
                child: Text(
                  actionText,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. E-commerce Style Equipment Status Card (สถานะอุปกรณ์)
  // ─────────────────────────────────────────────────────────────
  Widget _buildEcommerceRentalCard(RentalBooking item, DateTime now) {
    final end = item.endDate ?? now.add(const Duration(hours: 24));
    final bool isOverdue = now.isAfter(end);
    final Duration diff = isOverdue ? now.difference(end) : end.difference(now);

    final notifId = 'rental_${item.bookingId ?? item.title.hashCode}';
    final isRead = _isItemRead(notifId);

    // กำหนดข้อความสถานะและสี
    final (statusLabel, statusColor, statusBg, statusBorder) =
        _resolveStatusStyle(item, isOverdue);

    // ข้อความแถบเวลาหรือความคืบหน้า
    final tickerInfo = _resolveTickerInfo(item, diff, isOverdue, end);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOverdue ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _handleCardTap(item, isOverdue),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ส่วนหัวการ์ด: รหัสคำสั่งเช่า & ป้ายสถานะ ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (!isRead) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          item.bookingId != null
                              ? 'คำสั่งเช่า #YM-${item.bookingId}'
                              : 'คำสั่งเช่าอุปกรณ์',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusBorder, width: 0.8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── ส่วนข้อมูลอุปกรณ์และคู่สัญญา ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 58,
                        height: 58,
                        color: const Color(0xFFF1F5F9),
                        child: item.imageUrl != null &&
                                item.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 24,
                                  color: Color(0xFF94A3B8),
                                ),
                              )
                            : const Icon(
                                Icons.inventory_2_outlined,
                                size: 24,
                                color: Color(0xFF94A3B8),
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
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'คู่สัญญา: ${item.partnerName} (${item.partnerRole})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          if (item.totalPrice > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              'ยอดเช่ารวม: ฿${item.totalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── แถบวัดเวลาหรือความคืบหน้าสถานะ (พร้อมลูกศรนำทาง) ──
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? const Color(0xFFFEE2E2).withValues(alpha: 0.6)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isOverdue
                          ? const Color(0xFFFECACA)
                          : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        tickerInfo.icon,
                        size: 14,
                        color: tickerInfo.iconColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tickerInfo.mainText,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: tickerInfo.iconColor,
                          ),
                        ),
                      ),
                      if (tickerInfo.subText.isNotEmpty) ...[
                        Text(
                          tickerInfo.subText,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleCardTap(RentalBooking item, bool isOverdue) {
    HapticFeedback.lightImpact();
    final notifId = 'rental_${item.bookingId ?? item.title.hashCode}';
    _toggleItemRead(notifId);

    final code = item.statusCode.toLowerCase().trim();

    // 1. สถานะต้องส่งคืน หรือเลยกำหนดส่งคืน -> นำทางไปหน้าคืนของ (Rental Return)
    if (code == 'returning' || isOverdue) {
      if (item.bookingId != null) {
        AppRoutes.openRentalReturn(context, rentalId: item.bookingId);
        return;
      }
    }

    // 2. สถานะรอการรับอุปกรณ์ / นัดรับของ -> ไปหน้าติดตามแผนที่รับอุปกรณ์
    if (code == 'confirmed' || code == 'pickup' || code == 'ready_for_pickup') {
      AppRoutes.openRentalTrackingMap(
        context,
        isOwner: item.isOwner,
        trackingArgs: {
          'itemTitle': item.title,
          'itemImageUrl': item.imageUrl,
          'pickupLocation': item.pickupLocation,
          'ownerName': item.partnerName,
          'ownerPhone': item.partnerPhone,
          'periodText': item.duration,
          'totalPrice': item.totalPrice,
          'statusCode': item.statusCode,
          'bookingId': item.bookingId,
          'isOwner': item.isOwner,
        },
      );
      return;
    }

    // 3. สถานะรอการชำระเงิน -> ไปหน้ากระเป๋าเงิน / ชำระเงิน
    if (code == 'unpaid' ||
        code == 'waiting_payment' ||
        code == 'payment_pending') {
      AppRoutes.openWallet(context);
      return;
    }

    // 4. สถานะอื่นๆ (เช่น รอการยืนยัน หรือกำลังเช่า) -> ไปหน้ารายละเอียดสถานะการเช่า
    AppRoutes.openRentalStatus(context);
  }



  (String, Color, Color, Color) _resolveStatusStyle(
    RentalBooking item,
    bool isOverdue,
  ) {
    final code = item.statusCode.toLowerCase().trim();
    switch (code) {
      case 'pending':
        return (
          'รอการยืนยัน',
          const Color(0xFFD97706),
          const Color(0xFFFFFBEB),
          const Color(0xFFFDE68A),
        );
      case 'unpaid':
      case 'waiting_payment':
      case 'payment_pending':
        return (
          'รอการชำระ',
          const Color(0xFFD97706),
          const Color(0xFFFFFBEB),
          const Color(0xFFFDE68A),
        );
      case 'confirmed':
        return (
          'รอการรับอุปกรณ์',
          const Color(0xFF2563EB),
          const Color(0xFFEFF6FF),
          const Color(0xFFBFDBFE),
        );
      case 'returning':
        return (
          'ต้องส่งคืน',
          const Color(0xFFEA580C),
          const Color(0xFFFFF7ED),
          const Color(0xFFFED7AA),
        );
      case 'active':
      default:
        if (isOverdue) {
          return (
            'ต้องส่งคืน (เลยกำหนด)',
            const Color(0xFFDC2626),
            const Color(0xFFFEF2F2),
            const Color(0xFFFECACA),
          );
        }
        return (
          'กำลังเช่า',
          AppColors.primaryColor,
          const Color(0xFFF5F3FF),
          const Color(0xFFDDD6FE),
        );
    }
  }

  _TickerData _resolveTickerInfo(
    RentalBooking item,
    Duration diff,
    bool isOverdue,
    DateTime end,
  ) {
    final code = item.statusCode.toLowerCase().trim();
    String endFormatted;
    try {
      endFormatted = DateFormat('d MMM yyyy • HH:mm น.', 'th').format(end);
    } catch (_) {
      endFormatted = '${end.day}/${end.month}/${end.year}';
    }

    if (code == 'pending') {
      return _TickerData(
        icon: Icons.hourglass_top_rounded,
        iconColor: const Color(0xFFD97706),
        mainText: 'รอเจ้าของยืนยันคำขอเช่า',
        subText: '',
      );
    }
    if (code == 'unpaid' ||
        code == 'waiting_payment' ||
        code == 'payment_pending') {
      return _TickerData(
        icon: Icons.payment_rounded,
        iconColor: const Color(0xFFD97706),
        mainText: 'รอการชำระเงินมัดจำ',
        subText: 'เพื่อยืนยันการจอง',
      );
    }
    if (code == 'confirmed') {
      return _TickerData(
        icon: Icons.inventory_2_outlined,
        iconColor: const Color(0xFF2563EB),
        mainText: 'รอการรับอุปกรณ์',
        subText: 'กำหนด: $endFormatted',
      );
    }
    if (code == 'returning') {
      return _TickerData(
        icon: Icons.assignment_return_outlined,
        iconColor: const Color(0xFFEA580C),
        mainText: 'อยู่ระหว่างขั้นตอนส่งคืนอุปกรณ์',
        subText: '',
      );
    }

    // Default / Active
    final String timeText;
    if (isOverdue) {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      timeText = hours > 0
          ? 'เลยกำหนดมาแล้ว $hours ชม. $mins นาที'
          : 'เลยกำหนดมาแล้ว $mins นาที';
      return _TickerData(
        icon: Icons.error_outline_rounded,
        iconColor: const Color(0xFFDC2626),
        mainText: timeText,
        subText: 'กำหนด: $endFormatted',
      );
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
      return _TickerData(
        icon: Icons.access_time_rounded,
        iconColor: AppColors.primaryColor,
        mainText: timeText,
        subText: 'กำหนด: $endFormatted',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 6. Editorial SaaS System Bulletin Card (อัปเดตและข้อความระบบ)
  // ─────────────────────────────────────────────────────────────
  Widget _buildSystemCard(SystemNotificationItem item) {
    final isRead = _isItemRead(item.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x030F172A),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _toggleItemRead(item.id);
            _handleSystemAction(item);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFDDD6FE),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    item.icon,
                    size: 18,
                    color: AppColors.primaryColor,
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
                          Row(
                            children: [
                              Text(
                                item.category,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '• ${_formatRelativeTime(item.timestamp)}',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                          if (!isRead)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.message,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          color: Color(0xFF475569),
                          height: 1.45,
                        ),
                      ),
                      if (item.actionLabel != null) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _handleSystemAction(item),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.actionLabel!,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 12,
                                color: AppColors.primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSystemAction(SystemNotificationItem item) {
    if (item.id == 'sys_1') {
      context.push(AppRoutes.search);
    } else if (item.id == 'sys_2') {
      context.push(AppRoutes.wallet);
    }
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
      return '$mins นาทีที่แล้ว';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} ชั่วโมงที่แล้ว';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} วันที่แล้ว';
    } else {
      return DateFormat('d MMM yyyy', 'th').format(time);
    }
  }
}

class _TickerData {
  final IconData icon;
  final Color iconColor;
  final String mainText;
  final String subText;

  _TickerData({
    required this.icon,
    required this.iconColor,
    required this.mainText,
    required this.subText,
  });
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/data/repositories/rental_management_repository_impl.dart';
import '../../../profile/domain/entities/rental_booking.dart';

/// ประเภทตัวกรองการแจ้งเตือน
enum NotificationFilter { all, rentals, system }

/// แบบจำลองข้อมูลการแจ้งเตือนทั่วไปของระบบ
class SystemNotificationItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final IconData icon;

  const SystemNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.icon = Icons.info_outline_rounded,
  });
}

/// หน้าจอการแจ้งเตือน (Notification Page)
/// ออกแบบด้วยสไตล์ Swiss Style / Clean SaaS:
/// - ใช้ 2 สีหลัก: ม่วง Yuemnoi (0xFF7400C9) และสี Neutral Slate
/// - ลำดับชั้นตัวอักษรคมชัด ไม่ใช้ gradient ฉูดฉาด และไม่มีไอคอนตกแต่งอย่างไร้จุดหมาย
/// - ให้มิติที่ชัดเจนระหว่าง "อุปกรณ์ที่ต้องคืนด่วน" กับ "อัปเดตทั่วไป"
class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  NotificationFilter _selectedFilter = NotificationFilter.all;
  bool _isLoading = true;
  List<RentalBooking> _activeRentals = [];

  final List<SystemNotificationItem> _systemNotifications = [
    SystemNotificationItem(
      id: 'sys_1',
      title: 'ยินดีต้อนรับสู่ Yuemnoi',
      message: 'เริ่มค้นหาอุปกรณ์ที่คุณต้องการหรือลงประกาศปล่อยเช่าอุปกรณ์ของคุณได้ง่ายๆ ปลอดภัยทุกการใช้งาน',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      icon: Icons.verified_user_outlined,
    ),
    SystemNotificationItem(
      id: 'sys_2',
      title: 'การชำระเงินปลอดภัย',
      message: 'ระบบมัดจำและเงินประกันถูกล็อคไว้อย่างปลอดภัยผ่าน Escrow Wallet จนกว่าจะส่งคืนอุปกรณ์เรียบร้อย',
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
      icon: Icons.shield_outlined,
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
      final bookings = await repo.getRentingBookings(userId);
      final active = bookings.where((b) {
        final code = b.statusCode.toLowerCase().trim();
        return code == 'active';
      }).toList();

      if (mounted) {
        setState(() {
          _activeRentals = active;
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdueCount = _activeRentals.where((b) {
      final end = b.endDate ?? now;
      return now.isAfter(end);
    }).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header (Swiss Style Minimal Header) ──
            _buildHeader(overdueCount),

            // ── Category Filters ──
            _buildFilterTabs(),

            // ── Content List ──
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primaryColor,
                backgroundColor: Colors.white,
                onRefresh: _fetchNotifications,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryColor,
                          strokeWidth: 2.5,
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

  Widget _buildHeader(int overdueCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'การแจ้งเตือน',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_activeRentals.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: overdueCount > 0
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: overdueCount > 0
                              ? const Color(0xFFFECACA)
                              : const Color(0xFFDDD6FE),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        overdueCount > 0
                            ? '$overdueCount ด่วน'
                            : '${_activeRentals.length} รายการ',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: overdueCount > 0
                              ? const Color(0xFFDC2626)
                              : AppColors.primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'ติดตามสถานะการเช่าและกำหนดส่งคืนอุปกรณ์',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _fetchNotifications,
            tooltip: 'รีเฟรช',
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF64748B),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(
        children: [
          _buildFilterChip('ทั้งหมด', NotificationFilter.all),
          const SizedBox(width: 8),
          _buildFilterChip(
            'กำหนดคืน (${_activeRentals.length})',
            NotificationFilter.rentals,
          ),
          const SizedBox(width: 8),
          _buildFilterChip('ระบบ (${_systemNotifications.length})', NotificationFilter.system),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, NotificationFilter filter) {
    final isSelected = _selectedFilter == filter;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filter),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryColor : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(DateTime now) {
    final showRentals = _selectedFilter == NotificationFilter.all ||
        _selectedFilter == NotificationFilter.rentals;
    final showSystem = _selectedFilter == NotificationFilter.all ||
        _selectedFilter == NotificationFilter.system;

    final hasContent = (showRentals && _activeRentals.isNotEmpty) ||
        (showSystem && _systemNotifications.isNotEmpty);

    if (!hasContent) {
      return _buildEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      children: [
        if (showRentals && _activeRentals.isNotEmpty) ...[
          _buildSectionHeader(
            'กำหนดส่งคืนอุปกรณ์',
            '${_activeRentals.length} อุปกรณ์ที่ต้องส่งคืน',
          ),
          const SizedBox(height: 10),
          ..._activeRentals.map((item) => _buildRentalCard(item, now)),
          const SizedBox(height: 20),
        ],
        if (showSystem && _systemNotifications.isNotEmpty) ...[
          _buildSectionHeader('อัปเดตและข้อความระบบ', 'ข้อมูลสำคัญเกี่ยวกับบัญชี'),
          const SizedBox(height: 10),
          ..._systemNotifications.map(_buildSystemCard),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11.5,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRentalCard(RentalBooking item, DateTime now) {
    final end = item.endDate ?? now.add(const Duration(hours: 24));
    final bool isOverdue = now.isAfter(end);
    final Duration diff = isOverdue ? now.difference(end) : end.difference(now);

    final String timeText;
    if (isOverdue) {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      timeText = hours > 0
          ? 'เลยกำหนดมาแล้ว $hours ชม. $mins นาที'
          : 'เลยกำหนดมาแล้ว $mins นาที';
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
      endFormatted = '${end.day}/${end.month}/${end.year}';
    }

    final cardBg = isOverdue ? const Color(0xFFFFF8F8) : Colors.white;
    final borderColor = isOverdue ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0);
    final accentColor = isOverdue ? const Color(0xFFDC2626) : AppColors.primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => AppRoutes.openRentalStatus(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // รูปภาพอุปกรณ์
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 52,
                        height: 52,
                        color: const Color(0xFFF1F5F9),
                        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
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
                    // ข้อมูลอุปกรณ์
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
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
                                  isOverdue ? 'เลยกำหนด' : 'กำลังเช่า',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'ผู้ปล่อยเช่า: ${item.partnerName}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // ป้ายสถานะเวลา
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? const Color(0xFFFEE2E2).withValues(alpha: 0.5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOverdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                        size: 15,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          timeText,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ),
                      Text(
                        'ครบกำหนด: $endFormatted',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // แถบปุ่ม Action นำทาง
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => AppRoutes.openRentalStatus(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryColor,
                        side: const BorderSide(color: Color(0xFFDDD6FE)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'ดูสถานะการเช่า',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
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

  Widget _buildSystemCard(SystemNotificationItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, size: 20, color: AppColors.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.message,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatRelativeTime(item.timestamp),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} นาทีที่แล้ว';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} ชั่วโมงที่แล้ว';
    } else {
      return '${diff.inDays} วันที่แล้ว';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'ไม่มีการแจ้งเตือนใหม่',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'เมื่อมีกำหนดส่งคืนอุปกรณ์ หรือมีการอัปเดตระบบ ข้อมูลจะแสดงที่นี่',
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
      ),
    );
  }
}

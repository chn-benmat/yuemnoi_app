import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';

class RentalHistoryScreen extends StatefulWidget {
  const RentalHistoryScreen({super.key});

  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  bool _isLoading = true;
  List<_RentalHistoryItemData> _history = [];

  @override
  void initState() {
    super.initState();
    _loadRentalHistory();
  }

  Future<void> _loadRentalHistory() async {
    if (!SupabaseConfig.isInitialized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = SupabaseConfig.client;

      // 1. ดึงข้อมูลการจอง/เช่าของผู้ใช้จาก booking_tb
      final bookingsResp = await client
          .from('booking_tb')
          .select(
              'id, user_id, item_id, start_date, end_date, start_at, end_at, price, total_price, status, type, created_at')
          .eq('user_id', currentUserId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> rawBookings =
          List<Map<String, dynamic>>.from(bookingsResp as List);

      if (rawBookings.isEmpty) {
        if (mounted) {
          setState(() {
            _history = [];
            _isLoading = false;
          });
        }
        return;
      }

      // 2. ดึงข้อมูลอุปกรณ์จาก item_tb ตาม item_id
      final itemIds = rawBookings
          .map((b) => (b['item_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      final Map<int, Map<String, dynamic>> itemsMap = {};
      final Set<String> ownerIds = {};

      if (itemIds.isNotEmpty) {
        try {
          final itemsResp = await client
              .from('item_tb')
              .select('id, user_id, item_name, category, item_image_url')
              .inFilter('id', itemIds);

          for (final it in (itemsResp as List)) {
            if (it is Map) {
              final id = (it['id'] as num?)?.toInt();
              if (id != null) {
                itemsMap[id] = Map<String, dynamic>.from(it);
                final ownerId = it['user_id']?.toString();
                if (ownerId != null && ownerId.isNotEmpty) {
                  ownerIds.add(ownerId);
                }
              }
            }
          }
        } catch (_) {}
      }

      // 3. ดึงชื่อเจ้าของอุปกรณ์จาก profile_tb
      final Map<String, String> ownerNames = {};
      if (ownerIds.isNotEmpty) {
        try {
          final profilesResp = await client
              .from('profile_tb')
              .select('user_id, email')
              .inFilter('user_id', ownerIds.toList());

          for (final p in (profilesResp as List)) {
            if (p is Map) {
              final uid = p['user_id']?.toString();
              final email = p['email']?.toString() ?? '';
              if (uid != null) {
                ownerNames[uid] =
                    email.isNotEmpty ? email.split('@').first : 'เจ้าของอุปกรณ์';
              }
            }
          }
        } catch (_) {}
      }

      // 4. ประกอบข้อมูลประวัติการเช่า
      final List<_RentalHistoryItemData> result = [];

      for (final b in rawBookings) {
        final itemId = (b['item_id'] as num?)?.toInt();
        final itemData = itemId != null ? itemsMap[itemId] : null;

        final title = itemData?['item_name']?.toString() ?? 'อุปกรณ์เช่า';
        final category = itemData?['category']?.toString() ?? '';
        final ownerId = itemData?['user_id']?.toString() ?? '';
        final ownerName = ownerNames[ownerId] ?? 'เจ้าของอุปกรณ์';

        // คำนวณระยะเวลา
        String duration = 'เช่า 1 วัน';
        DateTime? startDate;
        DateTime? endDate;

        if (b['start_at'] != null) {
          startDate = DateTime.tryParse(b['start_at'].toString());
        } else if (b['start_date'] != null) {
          startDate = DateTime.tryParse(b['start_date'].toString());
        }

        if (b['end_at'] != null) {
          endDate = DateTime.tryParse(b['end_at'].toString());
        } else if (b['end_date'] != null) {
          endDate = DateTime.tryParse(b['end_date'].toString());
        }

        if (startDate != null && endDate != null) {
          final diff = endDate.difference(startDate);
          if (b['type'] == 'รายชั่วโมง' || diff.inDays == 0) {
            final hours = diff.inHours > 0 ? diff.inHours : 1;
            duration = 'เช่า $hours ชั่วโมง';
          } else {
            final days = diff.inDays > 0 ? diff.inDays : 1;
            duration = 'เช่า $days วัน';
          }
        }

        // แปลงวันที่
        String dateStr = '';
        final createdDate = b['created_at'] != null
            ? DateTime.tryParse(b['created_at'].toString())
            : startDate;
        if (createdDate != null) {
          try {
            dateStr = DateFormat('d MMM yyyy', 'th').format(createdDate.toLocal());
          } catch (_) {
            dateStr =
                '${createdDate.day}/${createdDate.month}/${createdDate.year}';
          }
        }

        // สถานะ
        final (statusText, statusColor, statusBg) =
            _formatStatus(b['status']?.toString());

        result.add(
          _RentalHistoryItemData(
            itemId: itemId,
            title: title,
            ownerName: ownerName,
            duration: duration,
            date: dateStr,
            status: statusText,
            statusColor: statusColor,
            statusBgColor: statusBg,
            iconData: _mapCategoryToIcon(category),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _history = result;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  (String, Color, Color) _formatStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'finished':
        return (
          'เสร็จสิ้น',
          const Color(0xFF2E7D32),
          const Color(0xFFE8F5E9),
        );
      case 'active':
        return (
          'กำลังเช่า',
          const Color(0xFF1565C0),
          const Color(0xFFE3F2FF),
        );
      case 'pending_payment':
        return (
          'รอชำระเงิน',
          const Color(0xFFE65100),
          const Color(0xFFFFF3E0),
        );
      case 'cancelled':
        return (
          'ยกเลิกแล้ว',
          const Color(0xFFC62828),
          const Color(0xFFFFEBEE),
        );
      default:
        return (
          'เสร็จสิ้น',
          const Color(0xFF2E7D32),
          const Color(0xFFE8F5E9),
        );
    }
  }

  IconData _mapCategoryToIcon(String? category) {
    if (category == null) return Icons.devices_other_outlined;
    final cat = category.toLowerCase();
    if (cat.contains('กล้อง') || cat.contains('camera')) {
      return Icons.camera_alt_outlined;
    }
    if (cat.contains('โดรน') || cat.contains('drone')) {
      return Icons.flight_takeoff_outlined;
    }
    if (cat.contains('โทรศัพท์') ||
        cat.contains('มือถือ') ||
        cat.contains('phone')) {
      return Icons.smartphone_outlined;
    }
    if (cat.contains('คอมพิวเตอร์') ||
        cat.contains('โน้ตบุ๊ก') ||
        cat.contains('laptop') ||
        cat.contains('macbook')) {
      return Icons.laptop_mac_outlined;
    }
    if (cat.contains('เสียง') ||
        cat.contains('ลำโพง') ||
        cat.contains('audio')) {
      return Icons.speaker_outlined;
    }
    if (cat.contains('แคมป์') || cat.contains('เต็นท์')) {
      return Icons.terrain_outlined;
    }
    if (cat.contains('รถ') || cat.contains('ยานยนต์')) {
      return Icons.directions_car_outlined;
    }
    if (cat.contains('เครื่องมือ') || cat.contains('tool')) {
      return Icons.build_outlined;
    }
    if (cat.contains('เสื้อ') || cat.contains('สูท')) {
      return Icons.checkroom_outlined;
    }
    return Icons.inventory_2_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ประวัติการเช่า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            )
          : _history.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppColors.primaryColor,
                  onRefresh: _loadRentalHistory,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    itemCount: _history.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      return _RentalHistoryCard(item: item);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ยังไม่มีประวัติการเช่า',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'เมื่อคุณทำการจองหรือเช่าอุปกรณ์ รายการประวัติการเช่าของคุณจะแสดงที่นี่',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: AppColors.hintTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              child: const Text(
                'ค้นหาอุปกรณ์เพื่อเช่า',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _RentalHistoryItemData {
  final int? itemId;
  final String title;
  final String ownerName;
  final String duration;
  final String date;
  final String status;
  final Color statusColor;
  final Color statusBgColor;
  final IconData iconData;

  _RentalHistoryItemData({
    this.itemId,
    required this.title,
    required this.ownerName,
    required this.duration,
    required this.date,
    required this.status,
    required this.statusColor,
    required this.statusBgColor,
    required this.iconData,
  });
}

// ─── Card Widget ──────────────────────────────────────────────────────────────

class _RentalHistoryCard extends StatelessWidget {
  final _RentalHistoryItemData item;

  const _RentalHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.itemId != null
          ? () => AppRoutes.openItemDetail(context, itemId: item.itemId!)
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon Box ──
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                item.iconData,
                color: AppColors.primaryColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            // ── Details ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'เช่าจาก: ${item.ownerName}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: AppColors.labelColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.date.isNotEmpty) ...[
                        Text(
                          item.date,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            color: AppColors.hintTextColor,
                          ),
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.hintTextColor,
                          ),
                        ),
                      ],
                      Text(
                        item.duration,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          color: AppColors.hintTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Status Badge ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: item.statusBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.status,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: item.statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

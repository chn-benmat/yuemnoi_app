import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../widgets/rentals/rental_status_widgets.dart';

class RentalStatusScreen extends StatefulWidget {
  const RentalStatusScreen({super.key});

  @override
  State<RentalStatusScreen> createState() => _RentalStatusScreenState();
}

class _RentalStatusScreenState extends State<RentalStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  List<RentalStatusItemData> _rentingItems = [];
  List<RentalStatusItemData> _lendingItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
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

      // 1. ดึงข้อมูลคำขอเช่าที่ผู้ใช้เช่าคนอื่น (Tab "เช่า")
      final rentingResp = await client
          .from('booking_tb')
          .select(
            'id, user_id, item_id, start_date, end_date, start_at, end_at, price, total_price, status, type, pickup_location, created_at',
          )
          .eq('user_id', currentUserId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> rawRentingBookings =
          List<Map<String, dynamic>>.from(rentingResp as List);

      // 2. ดึงข้อมูลคำขอเช่าที่คนอื่นมาเช่าอุปกรณ์ของผู้ใช้ (Tab "ปล่อยเช่า")
      final myItemsResp = await client
          .from('item_tb')
          .select('id')
          .eq('user_id', currentUserId);

      final myItemIds = (myItemsResp as List)
          .map((it) => (it['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();

      List<Map<String, dynamic>> rawLendingBookings = [];
      if (myItemIds.isNotEmpty) {
        final lendingResp = await client
            .from('booking_tb')
            .select(
              'id, user_id, item_id, start_date, end_date, start_at, end_at, price, total_price, status, type, pickup_location, created_at',
            )
            .inFilter('item_id', myItemIds)
            .order('created_at', ascending: false);

        rawLendingBookings =
            List<Map<String, dynamic>>.from(lendingResp as List);
      }

      // 3. รวบรวม item_id ทั้งหมดเพื่อดึงรายละเอียดจาก item_tb
      final Set<int> allItemIds = {};
      for (final b in rawRentingBookings) {
        final itemId = (b['item_id'] as num?)?.toInt();
        if (itemId != null) allItemIds.add(itemId);
      }
      for (final b in rawLendingBookings) {
        final itemId = (b['item_id'] as num?)?.toInt();
        if (itemId != null) allItemIds.add(itemId);
      }

      final Map<int, Map<String, dynamic>> itemsMap = {};
      final Set<String> partnerUserIds = {};

      if (allItemIds.isNotEmpty) {
        try {
          final itemsResp = await client
              .from('item_tb')
              .select('id, user_id, item_name, category, item_image_url, price, type')
              .inFilter('id', allItemIds.toList());

          for (final it in (itemsResp as List)) {
            if (it is Map) {
              final id = (it['id'] as num?)?.toInt();
              if (id != null) {
                itemsMap[id] = Map<String, dynamic>.from(it);
                final ownerId = it['user_id']?.toString();
                if (ownerId != null && ownerId.isNotEmpty) {
                  partnerUserIds.add(ownerId);
                }
              }
            }
          }
        } catch (_) {}
      }

      // ผู้เช่าของฝั่งปล่อยเช่า
      for (final b in rawLendingBookings) {
        final renterId = b['user_id']?.toString();
        if (renterId != null && renterId.isNotEmpty) {
          partnerUserIds.add(renterId);
        }
      }

      // 4. ดึงโปรไฟล์คู่สัญญาจาก profile_tb
      final Map<String, String> userNames = {};
      final Map<String, String> userPhones = {};
      if (partnerUserIds.isNotEmpty) {
        try {
          final profilesResp = await client
              .from('profile_tb')
              .select('user_id, email, phone')
              .inFilter('user_id', partnerUserIds.toList());

          for (final p in (profilesResp as List)) {
            if (p is Map) {
              final uid = p['user_id']?.toString();
              final email = p['email']?.toString() ?? '';
              final phone = p['phone']?.toString().trim();
              if (uid != null) {
                userNames[uid] = email.isNotEmpty
                    ? email.split('@').first
                    : 'ผู้ใช้งาน';
                if (phone != null && phone.isNotEmpty) {
                  userPhones[uid] = phone;
                }
              }
            }
          }
        } catch (_) {}
      }

      // 5. แปลงข้อมูลฝั่ง "เช่า"
      final List<RentalStatusItemData> rentingResult = [];
      for (final b in rawRentingBookings) {
        final itemId = (b['item_id'] as num?)?.toInt();
        final itemData = itemId != null ? itemsMap[itemId] : null;

        final title = itemData?['item_name']?.toString() ?? 'อุปกรณ์เช่า';
        final category = itemData?['category']?.toString();
        final ownerId = itemData?['user_id']?.toString() ?? '';
        final ownerName = userNames[ownerId] ?? 'เจ้าของอุปกรณ์';
        final ownerPhone = userPhones[ownerId];
        final imageUrl = _extractImageUrl(itemData?['item_image_url']);

        final (startDate, endDate) = _parseDates(b);
        final duration = _calculateDuration(b, startDate, endDate);
        final (statusText, statusColor) = _formatStatus(
          b['status']?.toString(),
          isRenter: true,
          startDate: startDate,
        );

        rentingResult.add(
          RentalStatusItemData(
            bookingId: (b['id'] as num?)?.toInt(),
            itemId: itemId,
            title: title,
            ownerName: ownerName,
            ownerPhone: ownerPhone,
            partnerRole: 'เจ้าของอุปกรณ์',
            status: statusText,
            statusCode: b['status']?.toString() ?? 'pending',
            statusColor: statusColor,
            iconData: _mapCategoryToIcon(category),
            imageUrl: imageUrl,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            totalPrice: (b['total_price'] as num?)?.toInt() ??
                (b['price'] as num?)?.toInt(),
            pickupLocation: b['pickup_location']?.toString(),
          ),
        );
      }

      // 6. แปลงข้อมูลฝั่ง "ปล่อยเช่า"
      final List<RentalStatusItemData> lendingResult = [];
      for (final b in rawLendingBookings) {
        final itemId = (b['item_id'] as num?)?.toInt();
        final itemData = itemId != null ? itemsMap[itemId] : null;

        final title = itemData?['item_name']?.toString() ?? 'อุปกรณ์เช่า';
        final category = itemData?['category']?.toString();
        final renterId = b['user_id']?.toString() ?? '';
        final renterName = userNames[renterId] ?? 'ผู้เช่า';
        final renterPhone = userPhones[renterId];
        final imageUrl = _extractImageUrl(itemData?['item_image_url']);

        final (startDate, endDate) = _parseDates(b);
        final duration = _calculateDuration(b, startDate, endDate);
        final (statusText, statusColor) = _formatStatus(
          b['status']?.toString(),
          isRenter: false,
          startDate: startDate,
        );

        lendingResult.add(
          RentalStatusItemData(
            bookingId: (b['id'] as num?)?.toInt(),
            itemId: itemId,
            title: title,
            ownerName: renterName,
            ownerPhone: renterPhone,
            partnerRole: 'ผู้เช่า',
            status: statusText,
            statusCode: b['status']?.toString() ?? 'pending',
            statusColor: statusColor,
            iconData: _mapCategoryToIcon(category),
            imageUrl: imageUrl,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            totalPrice: (b['total_price'] as num?)?.toInt() ??
                (b['price'] as num?)?.toInt(),
            pickupLocation: b['pickup_location']?.toString(),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _rentingItems = rentingResult;
          _lendingItems = lendingResult;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  (DateTime?, DateTime?) _parseDates(Map<String, dynamic> b) {
    DateTime? start;
    DateTime? end;

    if (b['start_at'] != null) {
      start = DateTime.tryParse(b['start_at'].toString());
    } else if (b['start_date'] != null) {
      start = DateTime.tryParse(b['start_date'].toString());
    }

    if (b['end_at'] != null) {
      end = DateTime.tryParse(b['end_at'].toString());
    } else if (b['end_date'] != null) {
      end = DateTime.tryParse(b['end_date'].toString());
    }

    return (start, end);
  }

  String _calculateDuration(
    Map<String, dynamic> b,
    DateTime? start,
    DateTime? end,
  ) {
    if (start != null && end != null) {
      final diff = end.difference(start);
      if (b['type'] == 'รายชั่วโมง' || diff.inDays == 0) {
        final hours = diff.inHours > 0 ? diff.inHours : 1;
        return 'เช่า $hours ชั่วโมง';
      } else {
        final days = diff.inDays > 0 ? diff.inDays : 1;
        return 'เช่า $days วัน';
      }
    }
    return 'เช่า 1 วัน';
  }

  String? _extractImageUrl(dynamic raw) {
    if (raw == null) return null;
    if (raw is List && raw.isNotEmpty) {
      return raw.first.toString();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List && decoded.isNotEmpty) {
            return decoded.first.toString();
          }
        } catch (_) {}
      }
      if (trimmed.startsWith('http')) return trimmed;
    }
    return null;
  }

  (String, Color) _formatStatus(
    String? rawStatus, {
    required bool isRenter,
    DateTime? startDate,
  }) {
    final status = rawStatus?.toLowerCase().trim();
    switch (status) {
      case 'pending':
        return (
          isRenter ? 'รอเจ้าของยืนยัน' : 'รอยืนยันคำขอ',
          const Color(0xFFFFD54F),
        );
      case 'confirmed':
        if (startDate != null) {
          final now = DateTime.now();
          final startDay = DateTime(startDate.year, startDate.month, startDate.day);
          final today = DateTime(now.year, now.month, now.day);
          if (today.isBefore(startDay)) {
            final days = startDay.difference(today).inDays;
            return (
              'รอนัดรับ (อีก $days วัน)',
              const Color(0xFF60A5FA),
            );
          }
        }
        return (
          'ยืนยันแล้ว / นัดรับของ',
          const Color(0xFF80DEEA),
        );
      case 'active':
        return (
          'กำลังเช่า',
          const Color(0xFFA5D6A7),
        );
      case 'completed':
      case 'finished':
        return (
          'เสร็จสิ้น',
          const Color(0xFF81C784),
        );
      case 'cancelled':
        return (
          'ยกเลิกแล้ว',
          const Color(0xFFFF8A80),
        );
      default:
        return (
          rawStatus ?? 'รอยืนยัน',
          const Color(0xFFFFD54F),
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
    if (cat.contains('แฟน')) {
      return Icons.favorite_border_rounded;
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
          'สถานะ',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.w400,
            fontSize: 15,
          ),
          tabs: const [
            Tab(text: 'เช่า'),
            Tab(text: 'ปล่อยเช่า'),
          ],
        ),
      ),
      body: _isLoading
          ? const RentalStatusLoadingSkeleton()
          : TabBarView(
              controller: _tabController,
              children: [
                RentalStatusList(
                  items: _rentingItems,
                  onRefresh: _loadData,
                  emptyTitle: 'ยังไม่มีรายการเช่าอุปกรณ์',
                  emptyMessage:
                      'เมื่อคุณทำการยืนยันเช่าอุปกรณ์ รายการจะแสดงที่นี่',
                  onEmptyAction: () => AppRoutes.openHome(context),
                ),
                RentalStatusList(
                  items: _lendingItems,
                  onRefresh: _loadData,
                  emptyTitle: 'ยังไม่มีรายการปล่อยเช่า',
                  emptyMessage:
                      'เมื่อมีผู้ใช้งานขอเช่าอุปกรณ์ของคุณ รายการจะแสดงที่นี่',
                  onEmptyAction: () => AppRoutes.openHome(context),
                ),
              ],
            ),
    );
  }
}

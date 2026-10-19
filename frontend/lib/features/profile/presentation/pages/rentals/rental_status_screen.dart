import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../bloc/rental_status_cubit.dart';
import '../../bloc/rental_status_state.dart';
import '../../../domain/entities/rental_booking.dart';
import '../../widgets/rentals/rental_status_widgets.dart';

class RentalStatusScreen extends StatefulWidget {
  const RentalStatusScreen({super.key});

  @override
  State<RentalStatusScreen> createState() => _RentalStatusScreenState();
}

class _RentalStatusScreenState extends State<RentalStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final RentalStatusCubit _cubit;
  RealtimeChannel? _realtimeChannel;
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _cubit = RentalStatusCubit();
    _loadData();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _tabController.dispose();
    _cubit.close();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    try {
      if (!SupabaseConfig.isInitialized) return;
      final client = SupabaseConfig.client;
      _realtimeChannel?.unsubscribe();

      final channelName =
          'rental_status_realtime_${DateTime.now().millisecondsSinceEpoch}';
      _realtimeChannel = client.channel(channelName);

      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'booking_tb',
        callback: (payload) {
          debugPrint(
            'Realtime PostgresChange on booking_tb: ${payload.eventType}',
          );
          if (mounted) {
            _loadData();
          }
        },
      );

      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error in RentalStatusScreen: $e');
    }
  }

  Future<void> _loadData() async {
    final currentUserId = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;

    if (currentUserId == null || currentUserId.isEmpty) {
      setState(() {
        _isGuest = true;
      });
      return;
    }

    setState(() {
      _isGuest = false;
    });

    await _cubit.loadBookings(currentUserId);
  }

  Color _mapStatusColor(String? rawStatus, DateTime? startDate) {
    final status = rawStatus?.toLowerCase().trim();
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B); // Amber (รอการยืนยัน)
      case 'confirmed':
        return const Color(0xFF2563EB); // Electric blue
      case 'active':
        return const Color(0xFF059669); // Emerald
      case 'completed':
      case 'finished':
        return const Color(0xFF475569); // Slate
      case 'cancelled':
        return const Color(0xFFDC2626); // Rose
      default:
        return AppColors.primaryColor;
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
    if (cat.contains('เครื่องมือ') ||
        cat.contains('ทำความสะอาด') ||
        cat.contains('tool')) {
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

  RentalStatusItemData _toItemData(RentalBooking b) {
    return RentalStatusItemData.fromEntity(
      b,
      _mapStatusColor(b.statusCode, b.startDate),
      _mapCategoryToIcon(b.category),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: BlocProvider.value(
        value: _cubit,
        child: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9), // Slate 100 เหมือนหน้า Home
          body: BlocBuilder<RentalStatusCubit, RentalStatusState>(
            builder: (context, state) {
              final rentingItems = state is RentalStatusLoaded
                  ? state.rentingList.map(_toItemData).toList()
                  : <RentalStatusItemData>[];

              final lendingItems = state is RentalStatusLoaded
                  ? state.lendingList.map(_toItemData).toList()
                  : <RentalStatusItemData>[];

              final isLoading =
                  state is RentalStatusLoading ||
                  (state is RentalStatusInitial && !_isGuest);

              return Column(
                children: [
                  // ── 1. Top Control Deck (สไตล์เดียวกับหน้า Home พร้อมขอบโค้ง 22px) ──
                  _buildTopControlDeck(
                    rentingCount: rentingItems.length,
                    lendingCount: lendingItems.length,
                    isLoading: isLoading,
                  ),

                  // ── 2. Content Body ──
                  Expanded(
                    child: _isGuest
                        ? _buildGuestView()
                        : isLoading
                        ? const RentalStatusLoadingSkeleton()
                        : state is RentalStatusError
                        ? _buildErrorView(state.message)
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              RentalStatusList(
                                items: rentingItems,
                                onRefresh: _loadData,
                                emptyTitle: 'ยังไม่มีรายการเช่าอุปกรณ์',
                                emptyMessage:
                                    'เมื่อคุณทำการยืนยันเช่าอุปกรณ์ รายการจะแสดงและติดตามสถานะได้ที่นี่',
                                emptyActionLabel: 'ค้นหาอุปกรณ์เพื่อเช่า',
                                onEmptyAction: () =>
                                    AppRoutes.openHome(context),
                                isLender: false,
                              ),
                              RentalStatusList(
                                items: lendingItems,
                                onRefresh: _loadData,
                                emptyTitle: 'ยังไม่มีรายการปล่อยเช่า',
                                emptyMessage:
                                    'เมื่อมีผู้ใช้งานขอเช่าอุปกรณ์ของคุณ รายการจะแสดงและแจ้งเตือนที่นี่',
                                emptyActionLabel: 'ลงประกาศปล่อยเช่าอุปกรณ์',
                                onEmptyAction: () =>
                                    AppRoutes.openAddRentalItem(context),
                                isLender: true,
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// ส่วนหัวด้านบน (Top Control Deck) สไตล์เดียวกับ Home Feed
  Widget _buildTopControlDeck({
    required int rentingCount,
    required int lendingCount,
    required bool isLoading,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Navigation Bar Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    tooltip: 'ย้อนกลับ',
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'สถานะการเช่า',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    tooltip: 'รีเฟรชข้อมูล',
                    onPressed: isLoading ? null : _loadData,
                  ),
                ],
              ),
            ),

            // Modern Segmented Pill TabBar: ปรับแท็บเป็น "เช่า" และ "ปล่อยเช่า"
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSegmentedTab(
                      index: 0,
                      label: 'เช่า',
                      count: rentingCount,
                      icon: Icons.shopping_bag_outlined,
                    ),
                  ),
                  Expanded(
                    child: _buildSegmentedTab(
                      index: 1,
                      label: 'ปล่อยเช่า',
                      count: lendingCount,
                      icon: Icons.storefront_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedTab({
    required int index,
    required String label,
    required int count,
    required IconData icon,
  }) {
    final isSelected = _tabController.index == index;

    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8.5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? AppColors.primaryColor
                  : Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? AppColors.primaryColor
                    : Colors.white.withValues(alpha: 0.90),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryColor.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.primaryColor : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuestView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
                Icons.lock_outline_rounded,
                color: AppColors.primaryColor,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'เข้าสู่ระบบเพื่อดูสถานะการเช่า',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'กรุณาเข้าสู่ระบบเพื่อตรวจสอบอุปกรณ์ที่คุณกำลังเช่า ติดตามเวลากำหนดส่งคืน และดูประวัติการทำรายการ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => AppRoutes.openLogin(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                elevation: 0,
              ),
              child: const Text(
                'เข้าสู่ระบบทันที',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 48,
            ),
            const SizedBox(height: 14),
            const Text(
              'ไม่สามารถโหลดสถานะได้',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12.5,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('ลองใหม่อีกครั้ง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

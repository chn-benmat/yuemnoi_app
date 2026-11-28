import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/services/skeleton_layout_cache.dart';
import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../bloc/rental_status_cubit.dart';
import '../../bloc/rental_status_state.dart';
import '../../../domain/entities/rental_booking.dart';
import '../../widgets/rentals/rental_status_widgets.dart';

class RentalStatusScreen extends StatefulWidget {
  const RentalStatusScreen({
    super.key,
    this.initialBookingId,
    this.isLender = false,
  });

  final int? initialBookingId;
  final bool isLender;

  @override
  State<RentalStatusScreen> createState() => _RentalStatusScreenState();
}

class _RentalStatusScreenState extends State<RentalStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late RentalStatusCubit _cubit;
  late final GoTrueClient? _auth;
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _realtimeChannel;
  String? _userId;
  bool _didOpenInitialBooking = false;

  String? get _authenticatedUserId {
    final userId = _auth?.currentUser?.id;
    return userId == null || userId.isEmpty ? null : userId;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isLender ? 1 : 0,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _cubit = RentalStatusCubit();
    _auth = SupabaseConfig.isInitialized ? SupabaseConfig.client.auth : null;
    _userId = _authenticatedUserId;
    _authSubscription = _auth?.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        final signedOut = state.event == AuthChangeEvent.signedOut;
        if (signedOut || _authenticatedUserId != _userId) {
          unawaited(_loadData(resetSession: signedOut));
        }
      },
      onError: (Object error) {
        debugPrint('Auth subscription error in RentalStatusScreen: $error');
      },
    );
    unawaited(_loadData());
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
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

  Future<void> _loadData({bool resetSession = false}) async {
    final currentUserId = _authenticatedUserId;

    if (resetSession || currentUserId != _userId) {
      // ปิด Cubit เดิมเพื่อไม่ให้ผลที่ยังโหลดอยู่กลับมาแสดงหลังเปลี่ยนบัญชี
      final previousCubit = _cubit;
      setState(() {
        _userId = currentUserId;
        _cubit = RentalStatusCubit();
      });
      unawaited(previousCubit.close());
    }
    if (currentUserId == null) return;

    final cubit = _cubit;
    bool isCurrentSession() =>
        mounted &&
        identical(cubit, _cubit) &&
        currentUserId == _authenticatedUserId;

    await cubit.loadBookings(currentUserId);
    if (!isCurrentSession() ||
        _didOpenInitialBooking ||
        widget.initialBookingId == null) {
      return;
    }
    final state = cubit.state;
    if (state is! RentalStatusLoaded) return;
    final renting = state.rentingList
        .where((b) => b.bookingId == widget.initialBookingId)
        .firstOrNull;
    final lending = state.lendingList
        .where((b) => b.bookingId == widget.initialBookingId)
        .firstOrNull;
    final booking = renting ?? lending;
    if (booking == null) return;
    _didOpenInitialBooking = true;
    _tabController.index = lending != null ? 1 : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isCurrentSession()) {
        RentalStatusCard.showDetails(context, _toItemData(booking));
      }
    });
  }

  Color _mapStatusColor(String? rawStatus, DateTime? startDate) {
    final status = rawStatus?.toLowerCase().trim();
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B); // Amber (รอการยืนยัน)
      case 'confirmed':
        return const Color(0xFF2563EB); // Electric blue
      case 'active':
      case 'awaiting_return':
      case 'return_ready':
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
        key: ObjectKey(_cubit),
        value: _cubit,
        child: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9), // Slate 100 เหมือนหน้า Home
          body: BlocConsumer<RentalStatusCubit, RentalStatusState>(
            listener: (context, state) {
              if (state is! RentalStatusError ||
                  state.previous == null ||
                  ModalRoute.isCurrentOf(context) != true) {
                return;
              }
              final cubit = _cubit;
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: const Text('อัปเดตสถานะการเช่าไม่สำเร็จ'),
                    action: SnackBarAction(
                      label: 'ลองใหม่อีกครั้ง',
                      onPressed: () {
                        if (mounted && identical(cubit, _cubit)) {
                          unawaited(_loadData());
                        }
                      },
                    ),
                  ),
                );
            },
            builder: (context, state) {
              final bookings = switch (state) {
                RentalStatusLoaded() => state,
                RentalStatusLoading(:final previous) => previous,
                RentalStatusError(:final previous) => previous,
                _ => null,
              };

              final rentingItems =
                  bookings?.rentingList.map(_toItemData).toList() ?? [];
              final lendingItems =
                  bookings?.lendingList.map(_toItemData).toList() ?? [];

              if (bookings != null) {
                SkeletonLayoutCache.instance.writeCount(
                  'rental_status.$_userId',
                  rentingItems.length,
                );
              }

              final isLoading =
                  bookings == null &&
                  (state is RentalStatusLoading ||
                      state is RentalStatusInitial);

              return Column(
                children: [
                  // ── 1. Top Control Deck (สไตล์เดียวกับหน้า Home พร้อมขอบโค้ง 22px) ──
                  _buildTopControlDeck(
                    rentingCount: rentingItems.length,
                    lendingCount: lendingItems.length,
                  ),

                  // ── 2. Content Body ──
                  Expanded(
                    child: _userId == null
                        ? _buildGuestView()
                        : isLoading
                        ? RentalStatusLoadingSkeleton(
                            count: SkeletonLayoutCache.instance.count(
                              'rental_status.$_userId',
                              fallback: 3,
                            ),
                          )
                        : state is RentalStatusError && bookings == null
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
                                    'เมื่อมีผู้ใช้งานขอเช่าอุปกรณ์ของคุณ รายการจะแสดงที่นี่',
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
                  const SizedBox(width: 48),
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
        padding: const EdgeInsets.symmetric(vertical: 13),
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

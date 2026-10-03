import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cubit = RentalStatusCubit();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    final currentUserId = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      await _cubit.loadBookings(currentUserId);
    }
  }

  Color _mapStatusColor(String? rawStatus, DateTime? startDate) {
    final status = rawStatus?.toLowerCase().trim();
    switch (status) {
      case 'confirmed':
        if (startDate != null) {
          final now = DateTime.now();
          final startDay = DateTime(startDate.year, startDate.month, startDate.day);
          final today = DateTime(now.year, now.month, now.day);
          if (today.isBefore(startDay)) {
            return const Color(0xFF60A5FA);
          }
        }
        return const Color(0xFF80DEEA);
      case 'active':
        return const Color(0xFFA5D6A7);
      case 'completed':
      case 'finished':
        return const Color(0xFF81C784);
      case 'cancelled':
        return const Color(0xFFFF8A80);
      default:
        return const Color(0xFF80DEEA);
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
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
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
        body: BlocBuilder<RentalStatusCubit, RentalStatusState>(
          builder: (context, state) {
            if (state is RentalStatusLoading || state is RentalStatusInitial) {
              return const RentalStatusLoadingSkeleton();
            }

            final rentingItems = state is RentalStatusLoaded
                ? state.rentingList.map(_toItemData).toList()
                : <RentalStatusItemData>[];

            final lendingItems = state is RentalStatusLoaded
                ? state.lendingList.map(_toItemData).toList()
                : <RentalStatusItemData>[];

            return TabBarView(
              controller: _tabController,
              children: [
                RentalStatusList(
                  items: rentingItems,
                  onRefresh: _loadData,
                  emptyTitle: 'ยังไม่มีรายการเช่าอุปกรณ์',
                  emptyMessage:
                      'เมื่อคุณทำการยืนยันเช่าอุปกรณ์ รายการจะแสดงที่นี่',
                  onEmptyAction: () => AppRoutes.openHome(context),
                ),
                RentalStatusList(
                  items: lendingItems,
                  onRefresh: _loadData,
                  emptyTitle: 'ยังไม่มีรายการปล่อยเช่า',
                  emptyMessage:
                      'เมื่อมีผู้ใช้งานขอเช่าอุปกรณ์ของคุณ รายการจะแสดงที่นี่',
                  onEmptyAction: () => AppRoutes.openHome(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

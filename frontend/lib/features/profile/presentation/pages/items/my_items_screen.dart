import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../bloc/my_items_cubit.dart';
import '../../bloc/my_items_state.dart';
import '../../widgets/items/my_items_widgets.dart';

class MyItemsScreen extends StatefulWidget {
  const MyItemsScreen({super.key});

  @override
  State<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends State<MyItemsScreen> {
  late final MyItemsCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = MyItemsCubit();
    _fetchItems();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _fetchItems() {
    final currentUserId = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      _cubit.loadMyItems(currentUserId);
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
    return Icons.inventory_2_outlined;
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
            'อุปกรณ์ของฉัน',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: BlocBuilder<MyItemsCubit, MyItemsState>(
          builder: (context, state) {
            if (state is MyItemsLoading || state is MyItemsInitial) {
              return const MyItemsLoadingSkeleton();
            }

            final items = state is MyItemsLoaded ? state.items : [];

            return RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: () async => _fetchItems(),
              child: Column(
                children: [
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF3E8FF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.inventory_2_outlined,
                                      color: AppColors.primaryColor,
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'คุณยังไม่มีอุปกรณ์ที่ปล่อยเช่า',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'กดปุ่มด้านล่างเพื่อเริ่มลงประกาศปล่อยเช่าอุปกรณ์ของคุณ',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 13,
                                      color: AppColors.hintTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (context, i) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entity = items[index];
                              final cardData = MyItemData.fromEntity(
                                entity,
                                _mapCategoryToIcon(entity.category),
                              );
                              return MyItemCard(item: cardData);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 8,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: () async {
              await AppRoutes.openAddRentalItem(context);
              _fetchItems();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              minimumSize: const Size(double.infinity, 52),
            ),
            child: const Text(
              'เพิ่มอุปกรณ์',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

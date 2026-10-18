import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/user_item.dart';
import '../../../domain/usecases/get_my_items_usecase.dart';
import '../../bloc/my_items_cubit.dart';
import '../../bloc/my_items_state.dart';
import '../../widgets/items/my_items_widgets.dart';

class MyItemsScreen extends StatefulWidget {
  const MyItemsScreen({super.key, this.getMyItems, this.userId});
  final GetMyItemsUseCase? getMyItems;
  final String? userId;

  @override
  State<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends State<MyItemsScreen> {
  late final MyItemsCubit _cubit;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cubit = MyItemsCubit(getMyItems: widget.getMyItems);
    _fetchItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _fetchItems() async {
    final userId =
        widget.userId ??
        (SupabaseConfig.isInitialized
            ? SupabaseConfig.client.auth.currentUser?.id
            : null);
    await _cubit.loadMyItems(userId ?? '');
  }

  void _clearFilters() {
    _searchController.clear();
    _cubit.clearFilters();
  }

  Future<void> _openFilters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => BlocBuilder<MyItemsCubit, MyItemsState>(
        bloc: _cubit,
        builder: (context, state) {
          final loaded = state is MyItemsLoaded ? state : null;
          return MyItemsFilterSheet(
            counts: loaded == null
                ? null
                : {
                    null: loaded.items.length,
                    for (final status in MyItemsFilter.values)
                      status: loaded.countFor(status),
                  },
            selectedStatus: state.statusFilter,
            onSelected: (status) {
              _cubit.filterByStatus(status);
              Navigator.of(sheetContext).pop();
            },
          );
        },
      ),
    );
  }

  Future<void> _openItem(UserItem item) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await AppRoutes.openItemDetail(
      context,
      itemId: item.id!,
      ownerLoadingLayout: true,
    );
    if (mounted) await _fetchItems();
  }

  IconData _categoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('กล้อง') || cat.contains('camera'))
      return Icons.camera_alt_outlined;
    if (cat.contains('โดรน') || cat.contains('drone'))
      return Icons.flight_takeoff_outlined;
    if (cat.contains('โทรศัพท์') ||
        cat.contains('มือถือ') ||
        cat.contains('phone'))
      return Icons.smartphone_outlined;
    if (cat.contains('คอมพิวเตอร์') ||
        cat.contains('โน้ตบุ๊ก') ||
        cat.contains('laptop') ||
        cat.contains('macbook'))
      return Icons.laptop_mac_outlined;
    if (cat.contains('เสียง') ||
        cat.contains('ดนตรี') ||
        cat.contains('ลำโพง') ||
        cat.contains('audio'))
      return Icons.music_note_outlined;
    if (cat.contains('แคมป์') || cat.contains('เต็นท์'))
      return Icons.terrain_outlined;
    if (cat.contains('รถ') || cat.contains('ยานยนต์'))
      return Icons.directions_car_outlined;
    if (cat.contains('เครื่องมือ') ||
        cat.contains('ทำความสะอาด') ||
        cat.contains('tool'))
      return Icons.build_outlined;
    if (cat.contains('เสื้อ') || cat.contains('สูท'))
      return Icons.checkroom_outlined;
    return Icons.inventory_2_outlined;
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _cubit,
    child: Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF242132),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: const BackButton(),
        title: const Text(
          'อุปกรณ์ของฉัน',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 19,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: BlocBuilder<MyItemsCubit, MyItemsState>(
          builder: (context, state) {
            final loaded = state is MyItemsLoaded ? state : null;
            final visibleItems = loaded?.visibleItems ?? const <UserItem>[];
            return Column(
              children: [
                _buildSearchToolbar(state),
                Expanded(
                  child: state is MyItemsLoading || state is MyItemsInitial
                      ? const MyItemsLoadingSkeleton()
                      : RefreshIndicator(
                          color: AppColors.primaryColor,
                          onRefresh: _fetchItems,
                          child: CustomScrollView(
                            key: const PageStorageKey('my-items-list'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            slivers: [
                              if (loaded?.isRefreshing == true)
                                const SliverToBoxAdapter(
                                  child: LinearProgressIndicator(
                                    minHeight: 2,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              if (loaded != null &&
                                  loaded.items.isNotEmpty) ...[
                                if (loaded.refreshError != null)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        8,
                                        20,
                                        0,
                                      ),
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 8,
                                        children: [
                                          const Text(
                                            'อัปเดตข้อมูลไม่สำเร็จ',
                                            style: TextStyle(
                                              color: Color(0xFF8C5719),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _fetchItems,
                                            child: const Text('ลองใหม่'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      18,
                                      20,
                                      12,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${state.statusFilter?.label ?? 'อุปกรณ์'} ${visibleItems.length} รายการ',
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF626574),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'ล่าสุดก่อน',
                                          style: TextStyle(
                                            fontFamily:
                                                AppTextStyles.fontFamily,
                                            fontSize: 11,
                                            color: Color(0xFF757181),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (state is MyItemsError ||
                                  loaded?.items.isEmpty == true ||
                                  visibleItems.isEmpty)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _buildMessage(state),
                                )
                              else
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    24,
                                  ),
                                  sliver: SliverList.separated(
                                    itemCount: visibleItems.length,
                                    separatorBuilder: (_, index) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final item = visibleItems[index];
                                      return MyItemCard(
                                        key: ValueKey('my-item-${item.id}'),
                                        item: MyItemData.fromEntity(
                                          item,
                                          _categoryIcon(item.category),
                                        ),
                                        onTap: item.id == null
                                            ? null
                                            : () => _openItem(item),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : _buildAddButton(),
    ),
  );

  Widget _buildMessage(MyItemsState state) {
    if (state is MyItemsError ||
        (state is MyItemsLoaded &&
            state.items.isEmpty &&
            state.refreshError != null)) {
      return MyItemsMessage(
        icon: Icons.cloud_off_outlined,
        title: 'โหลดอุปกรณ์ไม่สำเร็จ',
        description: 'ตรวจสอบการเชื่อมต่อ แล้วลองอีกครั้ง',
        actionLabel: 'ลองใหม่',
        onAction: _fetchItems,
      );
    }
    if (state is MyItemsLoaded && state.items.isEmpty) {
      return const MyItemsMessage(
        icon: Icons.inventory_2_outlined,
        title: 'เริ่มปล่อยเช่าอุปกรณ์ชิ้นแรก',
        description:
            'เพิ่มอุปกรณ์ของคุณ แล้วจัดการสถานะ\nการปล่อยเช่าได้จากหน้านี้',
      );
    }
    return MyItemsMessage(
      icon: Icons.search_off_rounded,
      title: 'ไม่พบอุปกรณ์ที่ตรงกัน',
      description: 'ลองใช้คำค้นอื่น หรือเลือกสถานะทั้งหมด',
      actionLabel: 'ล้างการค้นหาและตัวกรอง',
      onAction: _clearFilters,
    );
  }

  Widget _buildSearchToolbar(MyItemsState state) => ColoredBox(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _cubit.search,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              textInputAction: TextInputAction.search,
              autocorrect: false,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                color: Color(0xFF242132),
              ),
              decoration: InputDecoration(
                hintText: 'ค้นหาชื่อหรือหมวดหมู่',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF85808F),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 23,
                  color: Color(0xFF85808F),
                ),
                suffixIcon: state.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'ล้างคำค้น',
                        onPressed: () {
                          _searchController.clear();
                          _cubit.search('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                filled: true,
                fillColor: const Color(0xFFF5F4F8),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFECEAF1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton(
              key: const ValueKey('my-items-filter-button'),
              tooltip: state.statusFilter == null
                  ? 'ตัวกรองสถานะ'
                  : 'ตัวกรอง: ${state.statusFilter!.label}',
              onPressed: _openFilters,
              isSelected: state.statusFilter != null,
              style: IconButton.styleFrom(
                foregroundColor: state.statusFilter == null
                    ? const Color(0xFF626574)
                    : AppColors.primaryColor,
                backgroundColor: state.statusFilter == null
                    ? const Color(0xFFF5F4F8)
                    : const Color(0xFFF3EAFB),
                side: BorderSide(
                  color: state.statusFilter == null
                      ? const Color(0xFFECEAF1)
                      : AppColors.primaryColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Badge(
                isLabelVisible: state.statusFilter != null,
                backgroundColor: AppColors.primaryColor,
                child: const Icon(Icons.tune_rounded, size: 23),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildAddButton() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFECEAF1))),
    ),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: SafeArea(
      top: false,
      child: ElevatedButton.icon(
        onPressed: () async {
          await AppRoutes.openAddRentalItem(context);
          if (mounted) await _fetchItems();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.add_rounded, size: 23),
        label: const Text(
          'เพิ่มอุปกรณ์',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    ),
  );
}

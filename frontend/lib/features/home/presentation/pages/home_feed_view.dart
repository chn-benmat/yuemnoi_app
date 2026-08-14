import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/feed_item.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../widgets/category_filter_sheet.dart';
import '../widgets/home_empty_state.dart';
import '../widgets/home_header.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/shopee_product_card.dart';

/// หน้า Home Feed หลักของแอป Yuemnoi (ปรับปรุงเป็น Shopee 2-Column Grid)
class HomeFeedView extends StatefulWidget {
  const HomeFeedView({super.key});

  @override
  State<HomeFeedView> createState() => _HomeFeedViewState();
}

class _HomeFeedViewState extends State<HomeFeedView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onItemTap(FeedItem item) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'เลือกดู: ${item.title.replaceAll('\n', ' ')}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onFavoriteToggle(BuildContext context, FeedItem item) {
    context.read<HomeBloc>().add(ToggleFavoriteRequested(item.id));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item.isFavorite
              ? 'นำออกจากรายการโปรดแล้ว'
              : 'เพิ่ม "${item.title.replaceAll('\n', ' ')}" ในรายการโปรดแล้ว',
        ),
        backgroundColor: const Color(0xFF2B2E31),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          if (state is HomeInitial || state is HomeLoading) {
            return const _HomeLoadingView();
          }

          if (state is HomeError) {
            return _HomeErrorView(
              message: state.message,
              onRetry: () =>
                  context.read<HomeBloc>().add(const LoadHomeFeedStarted()),
            );
          }

          if (state is HomeLoaded) {
            // รวมรายการสินค้าสำหรับแสดงผลในกริด 2 คอลัมน์
            final List<FeedItem> displayedItems = [];
            final seenIds = <String>{};

            if (!state.hasActiveFilters && state.searchQuery.isEmpty) {
              for (final item in state.curatedItems) {
                if (seenIds.add(item.id)) displayedItems.add(item);
              }
              for (final item in state.nearbyItems) {
                if (seenIds.add(item.id)) displayedItems.add(item);
              }
            } else {
              for (final item in state.nearbyItems) {
                if (seenIds.add(item.id)) displayedItems.add(item);
              }
            }

            return Column(
              children: [
                // 1. ส่วนหัว Header ตรึงไว้ด้านบน (ไม่เลื่อนทะลุตามการดึงรีเฟรช)
                HomeHeader(
                  unreadCount: 3,
                  onNotificationTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ไม่มีการแจ้งเตือนใหม่'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),

                // 2. เนื้อหา Feed ด้านล่างที่เลื่อนได้ และดึงเพื่อรีเฟรชอยู่ใต้ Header พอดี
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.primaryColor,
                    backgroundColor: Colors.white,
                    edgeOffset: 0,
                    onRefresh: () async {
                      context.read<HomeBloc>().add(const RefreshHomeFeedRequested());
                      await Future<void>.delayed(const Duration(milliseconds: 500));
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        // ช่องค้นหาพร้อมปุ่มตัวกรองหมวดหมู่ด้านข้าง (หน้าต่างเลื่อนลงจากด้านบน)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: HomeSearchBar(
                                        controller: _searchController,
                                        onChanged: (query) {
                                          context.read<HomeBloc>().add(
                                                SearchQueryChanged(query),
                                              );
                                        },
                                        onClear: () {
                                          context.read<HomeBloc>().add(
                                                const SearchQueryChanged(''),
                                              );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    CategoryFilterButton(
                                      categories: state.categories,
                                      selectedCategoryId:
                                          state.selectedCategoryId,
                                      minPrice: state.minPrice,
                                      maxPrice: state.maxPrice,
                                      minRating: state.minRating,
                                      onApplyFilter: ({
                                        required categoryId,
                                        minPrice,
                                        maxPrice,
                                        minRating,
                                      }) {
                                        context.read<HomeBloc>().add(
                                              ApplyFilterRequested(
                                                categoryId: categoryId,
                                                minPrice: minPrice,
                                                maxPrice: maxPrice,
                                                minRating: minRating,
                                              ),
                                            );
                                      },
                                      onResetFilter: () {
                                        context.read<HomeBloc>().add(
                                              const ClearFilterRequested(),
                                            );
                                      },
                                    ),
                                  ],
                                ),
                                ActiveCategoryTag(
                                  categories: state.categories,
                                  selectedCategoryId: state.selectedCategoryId,
                                  minPrice: state.minPrice,
                                  maxPrice: state.maxPrice,
                                  minRating: state.minRating,
                                  onClearCategory: () {
                                    context.read<HomeBloc>().add(
                                          ApplyFilterRequested(
                                            categoryId: 'all',
                                            minPrice: state.minPrice,
                                            maxPrice: state.maxPrice,
                                            minRating: state.minRating,
                                          ),
                                        );
                                  },
                                  onClearPrice: () {
                                    context.read<HomeBloc>().add(
                                          ApplyFilterRequested(
                                            categoryId: state.selectedCategoryId,
                                            minPrice: null,
                                            maxPrice: null,
                                            minRating: state.minRating,
                                          ),
                                        );
                                  },
                                  onClearRating: () {
                                    context.read<HomeBloc>().add(
                                          ApplyFilterRequested(
                                            categoryId: state.selectedCategoryId,
                                            minPrice: state.minPrice,
                                            maxPrice: state.maxPrice,
                                            minRating: null,
                                          ),
                                        );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 14)),

                        // แสดงรายการสินค้าแบบ Grid 2 คอลัมน์ ซ้าย-ขวา สไตล์ Shopee Card
                        if (displayedItems.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: HomeEmptyState(searchQuery: state.searchQuery),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.61,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = displayedItems[index];
                                  return ShopeeProductCard(
                                    item: item,
                                    onTap: () => _onItemTap(item),
                                    onFavoriteToggle: () =>
                                        _onFavoriteToggle(context, item),
                                  );
                                },
                                childCount: displayedItems.length,
                              ),
                            ),
                          ),

                        // เว้นระยะห่างด้านล่างสำหรับ Bottom Navigation Bar และ FAB
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _HomeLoadingView extends StatelessWidget {
  const _HomeLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.primaryColor,
            strokeWidth: 3,
          ),
          SizedBox(height: 16),
          Text(
            'กำลังโหลดรายการอุปกรณ์...',
            style: TextStyle(
              color: Color(0xFF6B7075),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeErrorView extends StatelessWidget {
  const _HomeErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFE53935),
              size: 54,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2E3236),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('ลองใหม่อีกครั้ง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


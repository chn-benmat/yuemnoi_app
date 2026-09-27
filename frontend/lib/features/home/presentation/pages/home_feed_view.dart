import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../domain/entities/feed_item.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../widgets/category_filter_sheet.dart';
import '../widgets/home_empty_state.dart';
import '../widgets/home_header.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/rental_notification_bottom_sheet.dart';
import '../widgets/shopee_product_card.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../profile/data/repositories/rental_management_repository_impl.dart';
import '../../../profile/domain/entities/rental_booking.dart';

/// หน้า Home Feed หลักของแอป Yuemnoi (Shopee 2-Column Grid)
class HomeFeedView extends StatefulWidget {
  const HomeFeedView({super.key});

  @override
  State<HomeFeedView> createState() => _HomeFeedViewState();
}

class _HomeFeedViewState extends State<HomeFeedView> {
  final TextEditingController _searchController = TextEditingController();
  List<RentalBooking> _activeRentals = [];

  @override
  void initState() {
    super.initState();
    _fetchRentalAlerts();
  }

  Future<void> _fetchRentalAlerts() async {
    try {
      final userId = SupabaseConfig.isInitialized
          ? SupabaseConfig.client.auth.currentUser?.id
          : null;
      if (userId == null || userId.isEmpty) {
        if (mounted) {
          setState(() {
            _activeRentals = [];
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
        });
      }
    } catch (e) {
      debugPrint('Error fetching rental alerts: $e');
    }
  }

  void _openNotifications() {
    RentalNotificationBottomSheet.show(
      context,
      activeRentals: _activeRentals,
      onRefresh: _fetchRentalAlerts,
    ).then((_) {
      if (mounted) {
        _fetchRentalAlerts();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onItemTap(FeedItem item) {
    final itemId = int.tryParse(item.id);
    if (itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดรายละเอียดอุปกรณ์ได้')),
      );
      return;
    }
    AppRoutes.openItemDetail(context, itemId: itemId);
  }

  /// รวมและตัดรายการสินค้าซ้ำ
  List<FeedItem> _getDisplayedItems(HomeLoaded state) {
    if (state.hasActiveFilters || state.searchQuery.isNotEmpty) {
      return state.nearbyItems;
    }
    final seenIds = <String>{};
    return [
      ...state.curatedItems.where((item) => seenIds.add(item.id)),
      ...state.nearbyItems.where((item) => seenIds.add(item.id)),
    ];
  }

  /// ตัวช่วยส่ง Event ตัวกรอง
  void _applyFilter({
    required String categoryId,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) {
    context.read<HomeBloc>().add(
      ApplyFilterRequested(
        categoryId: categoryId,
        minPrice: minPrice,
        maxPrice: maxPrice,
        minRating: minRating,
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
            return _buildLoadedContent(state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildLoadedContent(HomeLoaded state) {
    final displayedItems = _getDisplayedItems(state);

    return Column(
      children: [
        // ส่วน Header ตรึงด้านบน
        HomeHeader(
          unreadCount: _activeRentals.length,
          onNotificationTap: _openNotifications,
        ),

        // แถบค้นหาและตัวกรองอยู่นอกพื้นที่ Pull to Refresh เพื่อไม่ให้ถูกดึงลง
        _buildSearchAndFilterSection(state),
        const SizedBox(height: 14),

        // ส่วน Feed เลื่อนได้ พร้อม Pull to Refresh
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryColor,
            backgroundColor: Colors.white,
            edgeOffset: 0,
            onRefresh: () async {
              context.read<HomeBloc>().add(const RefreshHomeFeedRequested());
              await _fetchRentalAlerts();
              await Future<void>.delayed(const Duration(milliseconds: 500));
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                _buildProductGridSliver(displayedItems, state.searchQuery),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// แถบค้นหา + ปุ่มตัวกรอง + ป้าย Filter Tag
  Widget _buildSearchAndFilterSection(HomeLoaded state) {
    final bloc = context.read<HomeBloc>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: HomeSearchBar(
                  controller: _searchController,
                  onChanged: (query) => bloc.add(SearchQueryChanged(query)),
                  onClear: () => bloc.add(const SearchQueryChanged('')),
                ),
              ),
              const SizedBox(width: 10),
              CategoryFilterButton(
                categories: state.categories,
                selectedCategoryId: state.selectedCategoryId,
                minPrice: state.minPrice,
                maxPrice: state.maxPrice,
                minRating: state.minRating,
                onApplyFilter:
                    ({required categoryId, minPrice, maxPrice, minRating}) =>
                        _applyFilter(
                          categoryId: categoryId,
                          minPrice: minPrice,
                          maxPrice: maxPrice,
                          minRating: minRating,
                        ),
                onResetFilter: () => bloc.add(const ClearFilterRequested()),
              ),
            ],
          ),
          ActiveCategoryTag(
            categories: state.categories,
            selectedCategoryId: state.selectedCategoryId,
            minPrice: state.minPrice,
            maxPrice: state.maxPrice,
            minRating: state.minRating,
            onClearCategory: () => _applyFilter(
              categoryId: 'all',
              minPrice: state.minPrice,
              maxPrice: state.maxPrice,
              minRating: state.minRating,
            ),
            onClearPrice: () => _applyFilter(
              categoryId: state.selectedCategoryId,
              minPrice: null,
              maxPrice: null,
              minRating: state.minRating,
            ),
            onClearRating: () => _applyFilter(
              categoryId: state.selectedCategoryId,
              minPrice: state.minPrice,
              maxPrice: state.maxPrice,
              minRating: null,
            ),
          ),
        ],
      ),
    );
  }

  /// กริดแสดงสินค้า 2 คอลัมน์ หรือ Empty State
  Widget _buildProductGridSliver(List<FeedItem> items, String searchQuery) {
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: HomeEmptyState(searchQuery: searchQuery),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.61,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          return ShopeeProductCard(item: item, onTap: () => _onItemTap(item));
        }, childCount: items.length),
      ),
    );
  }
}

class _HomeLoadingView extends StatelessWidget {
  const _HomeLoadingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('home-feed-skeleton'),
      children: [
        const HomeHeader(unreadCount: 0),
        Expanded(
          child: SkeletonShimmer(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Expanded(
                        child: SkeletonBox(height: 52, borderRadius: 18),
                      ),
                      SizedBox(width: 10),
                      SkeletonBox(width: 52, height: 52, borderRadius: 18),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.61,
                          ),
                      itemCount: 6,
                      itemBuilder: (context, index) =>
                          const _ProductCardSkeleton(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductCardSkeleton extends StatelessWidget {
  const _ProductCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: SkeletonBox(height: double.infinity, borderRadius: 0),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: double.infinity,
                    height: 14,
                    borderRadius: 7,
                  ),
                  SizedBox(height: 8),
                  SkeletonBox(width: 96, height: 14, borderRadius: 7),
                  Spacer(),
                  SkeletonBox(width: 76, height: 18, borderRadius: 9),
                  SizedBox(height: 8),
                  SkeletonBox(width: 116, height: 12, borderRadius: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeErrorView extends StatelessWidget {
  const _HomeErrorView({required this.message, required this.onRetry});

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

import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../domain/entities/feed_item.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../bloc/home_state.dart';
import '../widgets/category_filter_chips.dart';
import '../widgets/home_empty_state.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/shopee_product_card.dart';

/// หน้า Home Feed หลักของแอป Yuemnoi (Shopee 2-Column Grid)
class HomeFeedView extends StatefulWidget {
  const HomeFeedView({super.key});

  @override
  State<HomeFeedView> createState() => _HomeFeedViewState();
}

class _HomeFeedViewState extends State<HomeFeedView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final homeBloc = context.read<HomeBloc>();
    if (homeBloc.state is HomeLoaded) {
      final loaded = homeBloc.state as HomeLoaded;
      _searchController.text = loaded.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onItemTap(FeedItem item) {
    final itemId = int.tryParse(item.id);
    if (itemId == null) {
      showAppPopup(context, content: Text('ไม่สามารถเปิดรายละเอียดอุปกรณ์ได้'));
      return;
    }
    AppRoutes.openItemDetail(
      context,
      itemId: itemId,
      ownerLoadingLayout: item.isOwner,
    );
  }

  /// รวมและตัดรายการสินค้าซ้ำ
  List<FeedItem> _getDisplayedItems(HomeLoaded? state) {
    if (state == null) return const [];

    if (state.hasActiveFilters || state.searchQuery.trim().isNotEmpty) {
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: BlocConsumer<HomeBloc, HomeState>(
          listener: (context, state) {
            if (state is HomeLoaded) {
              final favoriteError = state.favoriteErrorMessage;
              if (favoriteError != null) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(favoriteError)));
              }
              if (_searchController.text != state.searchQuery) {
                _searchController.text = state.searchQuery;
              }
            }
          },
          builder: (context, state) {
            if (state is HomeInitial || state is HomeLoading) {
              return _buildFeedContent(null);
            }
            if (state is HomeError) {
              return _HomeErrorView(
                message: state.message,
                onRetry: () =>
                    context.read<HomeBloc>().add(const LoadHomeFeedStarted()),
              );
            }
            if (state is HomeLoaded) {
              return _buildFeedContent(state);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildFeedContent(HomeLoaded? state) {
    final displayedItems = _getDisplayedItems(state);

    return Column(
      children: [
        // ── 1. Top Control Deck: Search Bar + แถบ navbar ของอุปกรณ์ประเภทต่างๆ (PINNED / ตรึงอยู่กับที่ ไม่เลื่อนตาม และไม่ถูกดึงลงเมื่อรีเฟรช) ──
        ListenableBuilder(
          listenable: _scrollController,
          builder: (context, _) {
            final isScrolled =
                _scrollController.hasClients && _scrollController.offset > 4.0;

            return Container(
              decoration: BoxDecoration(
                color: AppColors.primaryColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
                boxShadow: isScrolled
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSearchAndFilterSection(state),
                    _buildCategoryNavbarSection(state),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        ),

        // ── 2. Scrollable Product Feed Layer (Pull to Refresh) ──
        Expanded(
          child: state == null
              ? const _HomeLoadingView()
              : RefreshIndicator(
                  color: AppColors.primaryColor,
                  backgroundColor: Colors.white,
                  onRefresh: () async {
                    context.read<HomeBloc>().add(
                      const RefreshHomeFeedRequested(),
                    );
                    await Future<void>.delayed(
                      const Duration(milliseconds: 400),
                    );
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      // ระยะห่างก่อนถึงการ์ดสินค้า
                      const SliverToBoxAdapter(child: SizedBox(height: 10)),

                      // รายการสินค้า
                      _buildProductGridSliver(
                        displayedItems,
                        state.searchQuery,
                      ),

                      // ระยะห่างด้านล่างสำหรับ FloatingActionButton & Bottom Navigation Bar
                      const SliverToBoxAdapter(child: SizedBox(height: 110)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// แถบ navbar ของอุปกรณ์ประเภทต่างๆ (Category Filter Chips) ตรึงอยู่กับที่ใน Top Control Deck
  Widget _buildCategoryNavbarSection(HomeLoaded? state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFBA77FF), // สีม่วงอ่อนสว่าง
            Color(0xFFC78FFF), // สีม่วงพาสเทลอ่อนละมุน
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.50),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: CategoryFilterChips(
        categories: state?.categories ?? const [],
        selectedCategoryId: state?.selectedCategoryId ?? 'all',
        onCategorySelected: (categoryId) async {
          if (categoryId == 'all') {
            _applyFilter(
              categoryId: 'all',
              minPrice: state?.minPrice,
              maxPrice: state?.maxPrice,
              minRating: state?.minRating,
            );
            return;
          }

          final label = CategoryFilterChips.getCategoryLabel(categoryId);
          await AppRoutes.openSearch(
            context,
            initialQuery: label,
            curatedItems: _getDisplayedItems(state),
            categories: state?.categories ?? const [],
          );
          if (mounted &&
              ((state?.selectedCategoryId ?? 'all') != 'all' ||
                  _searchController.text.isNotEmpty)) {
            _searchController.clear();
            _applyFilter(
              categoryId: 'all',
              minPrice: state?.minPrice,
              maxPrice: state?.maxPrice,
              minRating: state?.minRating,
            );
          }
        },
      ),
    );
  }

  /// แถบค้นหา + ปุ่มหัวใจไปยังหน้าอุปกรณ์ที่ถูกใจ
  Widget _buildSearchAndFilterSection(HomeLoaded? state) {
    final bloc = context.read<HomeBloc>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: HomeSearchBar(
              controller: _searchController,
              readOnly: true,
              onTap: () async {
                await AppRoutes.openSearch(
                  context,
                  curatedItems: _getDisplayedItems(state),
                  initialQuery: _searchController.text.isNotEmpty
                      ? _searchController.text
                      : null,
                  initialCategoryId: state?.selectedCategoryId ?? 'all',
                  categories: state?.categories ?? const [],
                  minPrice: state?.minPrice,
                  maxPrice: state?.maxPrice,
                  minRating: state?.minRating,
                );
              },
              onChanged: (query) => bloc.add(SearchQueryChanged(query)),
              onClear: () {
                _searchController.clear();
                bloc.add(const SearchQueryChanged(''));
              },
            ),
          ),
          const SizedBox(width: 10),
          _buildFavoritesButton(context),
        ],
      ),
    );
  }

  Widget _buildFavoritesButton(BuildContext context) {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('home-favorites-button'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => AppRoutes.openFavorite(context),
          child: const Center(
            child: Icon(
              Icons.favorite_rounded,
              color: AppColors.primaryColor,
              size: 24,
            ),
          ),
        ),
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
    return SkeletonShimmer(
      child: Container(
        key: const ValueKey('home-feed-skeleton'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: GridView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.61,
            ),
            itemCount: 6,
            itemBuilder: (context, index) => const _ProductCardSkeleton(),
          ),
        ),
      ),
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
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: SkeletonBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        width: double.infinity,
                        height: 16,
                        borderRadius: 4,
                      ),
                      SizedBox(height: 4),
                      SkeletonBox(width: 116, height: 13, borderRadius: 4),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 76, height: 20, borderRadius: 4),
                      SizedBox(height: 4),
                      SkeletonBox(width: 96, height: 14, borderRadius: 4),
                    ],
                  ),
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

/// วาดรูปทรงพื้นหลัง Control Deck โค้งลงแบบครึ่งวงกลม (Convex Semicircle Dome)
class SemicircleControlDeckPainter extends CustomPainter {
  final Color color;
  final Color? secondaryColor;
  final double curveDepth;

  const SemicircleControlDeckPainter({
    required this.color,
    this.secondaryColor,
    required this.curveDepth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;

    if (secondaryColor != null) {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color, secondaryColor!],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    } else {
      paint.color = color;
    }

    if (curveDepth <= 1.0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      return;
    }

    final baseHeight = size.height - curveDepth;
    final path = Path()
      ..lineTo(0, baseHeight)
      // โค้งลงแบบครึ่งวงกลม (Semicircle convex arc) ทอดลงมาด้านล่าง
      ..cubicTo(
        size.width * 0.16,
        size.height + curveDepth * 0.18,
        size.width * 0.84,
        size.height + curveDepth * 0.18,
        size.width,
        baseHeight,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SemicircleControlDeckPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.curveDepth != curveDepth;
  }
}

import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/recommendation_location_service.dart';
import '../../../../core/widgets/product_card_grid.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/entities/feed_category.dart';
import '../../domain/entities/feed_item.dart';
import '../../domain/repositories/home_repository.dart';
import '../../domain/usecases/rank_items_by_distance.dart';
import '../widgets/category_filter_sheet.dart';
import '../widgets/category_filter_chips.dart';
import '../widgets/shopee_product_card.dart';

/// หน้าค้นหาอุปกรณ์สไตล์ Shopee ผสาน Swiss Style / Clean SaaS
/// มี 2 โหมดหลัก:
/// 1. Pre-Search: แสดง Search Bar, ประวัติการค้นหา (คำค้นหาเก่า) และ สิ่งที่ผู้เช่าสนใจ (Item Cards)
/// 2. Search Results: แสดงผลลัพธ์อุปกรณ์เมื่อกดค้นหา (ไม่ใช่พิมพ์แล้วกรองทันที)
class EquipmentSearchScreen extends StatefulWidget {
  const EquipmentSearchScreen({
    super.key,
    this.initialCuratedItems,
    this.initialQuery,
    this.initialCategoryId,
    this.initialMinPrice,
    this.initialMaxPrice,
    this.initialMinRating,
    this.initialCategories,
    this.homeRepository,
    this.onCategoryInterest,
  });

  final List<FeedItem>? initialCuratedItems;
  final String? initialQuery;
  final String? initialCategoryId;
  final int? initialMinPrice;
  final int? initialMaxPrice;
  final double? initialMinRating;
  final List<FeedCategory>? initialCategories;
  final HomeRepository? homeRepository;
  final ValueChanged<String>? onCategoryInterest;

  @override
  State<EquipmentSearchScreen> createState() => _EquipmentSearchScreenState();
}

class _EquipmentSearchScreenState extends State<EquipmentSearchScreen> {
  static const String _recentSearchesKey = 'equipment_recent_searches_v1';

  late final HomeRepository _repository;
  late final TextEditingController _searchController;
  late final FocusNode _focusNode;

  List<String> _recentSearches = [];
  List<FeedItem> _curatedItems = [];
  List<FeedItem> _searchResults = [];
  List<FeedCategory> _categories = [];
  String _selectedCategoryId = 'all';
  int? _minPrice;
  int? _maxPrice;
  double? _minRating;

  bool _isSearchSubmitted = false;
  bool _isLoadingResults = false;
  bool _isLoadingCurated = false;
  String _lastSubmittedQuery = '';
  String? _searchErrorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.homeRepository ?? HomeRepositoryImpl();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _focusNode = FocusNode();
    _selectedCategoryId = widget.initialCategoryId ?? 'all';
    _minPrice = widget.initialMinPrice;
    _maxPrice = widget.initialMaxPrice;
    _minRating = widget.initialMinRating;

    _loadRecentSearches();

    if (widget.initialCuratedItems != null &&
        widget.initialCuratedItems!.isNotEmpty) {
      _curatedItems = widget.initialCuratedItems!;
    } else {
      _fetchCuratedItems();
    }

    if (widget.initialCategories != null &&
        widget.initialCategories!.isNotEmpty) {
      _categories = widget.initialCategories!;
    } else {
      _fetchCategories();
    }

    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _executeSearch(widget.initialQuery!.trim());
    } else if (_selectedCategoryId != 'all' ||
        _minPrice != null ||
        _maxPrice != null ||
        _minRating != null) {
      _executeSearch('');
    } else {
      // Auto-focus ช่องค้นหาเมื่อเปิดหน้าค้นหา
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ==========================================
  // จัดการประวัติการค้นหา (คำค้นหาเก่า)
  // ==========================================

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = prefs.getStringList(_recentSearchesKey) ?? [];
      if (list.length > 4) {
        list = list.sublist(0, 4);
      }
      if (mounted) {
        setState(() {
          _recentSearches = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading recent searches: $e');
    }
  }

  Future<void> _saveSearchQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final updated = List<String>.from(_recentSearches);
    updated.removeWhere((item) => item.toLowerCase() == clean.toLowerCase());
    updated.insert(0, clean);

    // เก็บประวัติสูงสุด 4 คำค้นหา (เมื่อครบ 4 คำค้นหาแล้วมีการค้นหาใหม่ นำประวัติเก่าที่สุดออก)
    if (updated.length > 4) {
      updated.removeRange(4, updated.length);
    }

    if (mounted) {
      setState(() {
        _recentSearches = updated;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentSearchesKey, updated);
    } catch (e) {
      debugPrint('Error saving recent search: $e');
    }
  }

  Future<void> _confirmClearSearchHistory() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('clear-search-history-dialog'),
        title: const Text('ล้างประวัติการค้นหา'),
        content: const Text('ต้องการลบประวัติการค้นหาทั้งหมดหรือไม่?'),
        actions: [
          TextButton(
            key: const ValueKey('cancel-clear-search-history'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            key: const ValueKey('confirm-clear-search-history'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ลบประวัติ'),
          ),
        ],
      ),
    );

    if (shouldClear != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSearchesKey);
    } catch (e) {
      debugPrint('Error clearing recent searches: $e');
    }

    if (mounted) {
      setState(() {
        _recentSearches = [];
      });
    }
  }

  // ==========================================
  // ดึงข้อมูลอุปกรณ์สิ่งที่ผู้เช่าสนใจ (Curated Items)
  // ==========================================

  Future<void> _fetchCuratedItems() async {
    if (mounted) {
      setState(() {
        _isLoadingCurated = true;
      });
    }
    try {
      final items = await _repository.getCuratedItems();
      if (mounted) {
        setState(() {
          _curatedItems = items;
          _isLoadingCurated = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching curated items: $e');
      if (mounted) {
        setState(() {
          _isLoadingCurated = false;
        });
      }
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final list = await _repository.getCategories();
      if (mounted) {
        setState(() {
          _categories = list;
        });
      }
    } catch (e) {
      debugPrint('Error fetching categories in search: $e');
    }
  }

  // ==========================================
  // ทำการค้นหา (Triggered เมื่อกดค้นหา / Enter / แท็ก)
  // ==========================================

  Future<void> _executeSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty &&
        _selectedCategoryId == 'all' &&
        _minPrice == null &&
        _maxPrice == null &&
        _minRating == null) {
      _resetToPreSearch();
      return;
    }

    _focusNode.unfocus();
    _searchController.text = trimmed;

    setState(() {
      _isSearchSubmitted = true;
      _isLoadingResults = true;
      _lastSubmittedQuery = trimmed;
      _searchErrorMessage = null;
    });

    if (trimmed.isNotEmpty) await _saveSearchQuery(trimmed);

    final explicitCategory = _selectedCategoryId != 'all'
        ? _selectedCategoryId
        : _categories
              .where(
                (category) =>
                    category.name == trimmed ||
                    category.id == trimmed.toLowerCase() ||
                    CategoryFilterChips.getCategoryLabel(category.id) ==
                        trimmed,
              )
              .firstOrNull
              ?.id;
    if (explicitCategory != null) {
      widget.onCategoryInterest?.call(explicitCategory);
    }

    try {
      final results = await _repository.getNearbyItems(
        categoryId: _selectedCategoryId != 'all' ? _selectedCategoryId : null,
        searchQuery: trimmed.isNotEmpty ? trimmed : null,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        minRating: _minRating,
      );

      if (mounted) {
        if (explicitCategory == null &&
            trimmed.isNotEmpty &&
            _lastSubmittedQuery == trimmed &&
            results.isNotEmpty) {
          widget.onCategoryInterest?.call(results.first.categoryId);
        }
        setState(() {
          _searchResults = results;
          _isLoadingResults = false;
          _searchErrorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error searching items: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isLoadingResults = false;
          _searchErrorMessage = 'ไม่มีการเชื่อมต่ออินเตอร์เน็ตกรุณาลองใหม่';
        });
      }
    }
  }

  void _applyFilter({
    required String categoryId,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) {
    setState(() {
      _selectedCategoryId = categoryId;
      _minPrice = minPrice;
      _maxPrice = maxPrice;
      _minRating = minRating;
    });
    _executeSearch(
      _lastSubmittedQuery.isNotEmpty
          ? _lastSubmittedQuery
          : _searchController.text,
    );
  }

  void _resetFilter() {
    setState(() {
      _selectedCategoryId = 'all';
      _minPrice = null;
      _maxPrice = null;
      _minRating = null;
    });
    _executeSearch(
      _lastSubmittedQuery.isNotEmpty
          ? _lastSubmittedQuery
          : _searchController.text,
    );
  }

  /// รีเซ็ตกลับไปหน้าคำค้นหาเก่าและสิ่งที่ผู้เช่าสนใจ
  void _resetToPreSearch() {
    setState(() {
      _isSearchSubmitted = false;
      _searchResults = [];
      _lastSubmittedQuery = '';
      _selectedCategoryId = 'all';
      _minPrice = null;
      _maxPrice = null;
      _minRating = null;
    });
    _focusNode.requestFocus();
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

  void _handleBackAction() {
    if (_isSearchSubmitted) {
      _resetToPreSearch();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSearchSubmitted,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearchSubmitted) {
          _resetToPreSearch();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: SafeArea(
          child: Column(
            children: [
              // Search Bar ด้านบนสุด
              _buildTopSearchBar(),

              // ส่วนเนื้อหาด้านล่าง: สลับระหว่าง Pre-Search กับ Search Results
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable:
                      RecommendationLocationService.instance.position,
                  builder: (context, position, _) => _isSearchSubmitted
                      ? _buildSearchResultsView(
                          rankItemsByDistance(_searchResults, position),
                        )
                      : _buildPreSearchView(
                          rankItemsByDistance(_curatedItems, position),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 1. TOP SEARCH BAR (Clean Swiss / Minimalist SaaS)
  // ==========================================

  Widget _buildTopSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7), width: 1)),
      ),
      child: Row(
        children: [
          // ปุ่มย้อนกลับ
          IconButton(
            key: const ValueKey('search-back-button'),
            tooltip: 'ย้อนกลับ',
            onPressed: _handleBackAction,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF18181B),
              size: 22,
            ),
            splashRadius: 22,
          ),
          const SizedBox(width: 4),

          // ช่องกรอกข้อความค้นหา
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? AppColors.primaryColor
                      : const Color(0xFFE4E4E7),
                  width: 1.2,
                ),
              ),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, _) {
                  return TextField(
                    key: const ValueKey('equipment-search-input'),
                    controller: _searchController,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _executeSearch,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF18181B),
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'ค้นหาอุปกรณ์ที่ต้องการเช่า...',
                      hintStyle: const TextStyle(
                        color: Color(0xFFA1A1AA),
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.search_rounded,
                          color: Color(0xFF71717A),
                          size: 20,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      suffixIcon: value.text.isNotEmpty
                          ? IconButton(
                              key: const ValueKey('search-clear-button'),
                              tooltip: 'ล้างคำค้นหา',
                              onPressed: () {
                                _searchController.clear();
                                if (_isSearchSubmitted) {
                                  _executeSearch('');
                                }
                              },
                              icon: const Icon(
                                Icons.cancel_rounded,
                                color: Color(0xFFA1A1AA),
                                size: 18,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 8,
                      ),
                      isDense: true,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // ปุ่มค้นหา (ม่วงธีมของแอป คมชัด ไม่ฉูดฉาด)
          GestureDetector(
            key: const ValueKey('search-submit-button'),
            onTap: () => _executeSearch(_searchController.text),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.primaryColor.withValues(alpha: 0.08),
              ),
              child: const Text(
                'ค้นหา',
                style: TextStyle(
                  color: AppColors.primaryColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. PRE-SEARCH VIEW (คำค้นหาเก่า + สิ่งที่ผู้เช่าสนใจ)
  // ==========================================

  Widget _buildPreSearchView(List<FeedItem> curatedItems) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 2.1 ส่วนคำค้นหาเก่า (Search History: บน 2 ล่าง 2)
        if (_recentSearches.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHistoryRow(
                    _recentSearches.take(2).toList(),
                    showClearButton: _recentSearches.length <= 2,
                  ),
                  if (_recentSearches.length > 2) ...[
                    const SizedBox(height: 8),
                    _buildHistoryRow(
                      _recentSearches.skip(2).take(2).toList(),
                      showClearButton: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 16),
              child: Divider(
                color: Color(0xFFE4E4E7),
                thickness: 1,
                height: 1,
                indent: 18,
                endIndent: 18,
              ),
            ),
          ),
        ],

        // 2.2 ส่วนสินค้าแนะนำสำหรับคุณ (Recommended item cards)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Text(
              'แนะนำสำหรับคุณ',
              style: TextStyle(
                color: Color(0xFF18181B),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),

        // รายการสินค้าแนะนำแบบ Item Cards (2-Column Grid)
        _buildCuratedGridSliver(curatedItems),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildHistoryRow(List<String> items, {bool showClearButton = false}) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Flexible(child: _buildHistoryTag(items[i])),
        ],
        if (showClearButton) ...[
          if (items.isNotEmpty) const SizedBox(width: 8),
          _buildClearHistoryButton(),
        ],
      ],
    );
  }

  Widget _buildClearHistoryButton() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
      ),
      child: InkWell(
        key: const ValueKey('clear-search-history-button'),
        borderRadius: BorderRadius.circular(8),
        onTap: _confirmClearSearchHistory,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 18,
            color: Color(0xFF71717A),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTag(String query) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _executeSearch(query),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            query,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF27272A),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCuratedGridSliver(List<FeedItem> curatedItems) {
    if (_isLoadingCurated && curatedItems.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: ProductCardGrid(
          itemCount: 4,
          itemBuilder: (context, index) => const _SearchItemSkeletonCard(),
        ),
      );
    }

    if (curatedItems.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'ไม่มีอุปกรณ์แนะนำในขณะนี้',
              style: TextStyle(color: Color(0xFF71717A), fontSize: 13.5),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: ProductCardGrid(
        itemCount: curatedItems.length,
        itemBuilder: (context, index) {
          final item = curatedItems[index];
          return ShopeeProductCard(item: item, onTap: () => _onItemTap(item));
        },
      ),
    );
  }

  // ==========================================
  // 3. SEARCH RESULTS VIEW (แสดงเมื่อกดเสิร์ชแล้ว)
  // ==========================================

  Widget _buildSearchResultsView(List<FeedItem> searchResults) {
    if (_isLoadingResults) {
      return Column(
        children: [
          _buildResultsHeader(isPlaceholder: true),
          Expanded(
            child: CustomScrollView(
              physics: const NeverScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  sliver: ProductCardGrid(
                    itemCount: 4,
                    itemBuilder: (context, index) =>
                        const _SearchItemSkeletonCard(),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildResultsHeader(),
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              if (searchResults.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyResultsState())
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  sliver: ProductCardGrid(
                    itemCount: searchResults.length,
                    itemBuilder: (context, index) {
                      final item = searchResults[index];
                      return ShopeeProductCard(
                        item: item,
                        onTap: () => _onItemTap(item),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 50)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsHeader({bool isPlaceholder = false}) {
    final isCategorySearch = _selectedCategoryId != 'all';
    final searchTerm = isCategorySearch
        ? CategoryFilterChips.getCategoryLabel(_selectedCategoryId)
        : _lastSubmittedQuery;
    final heading = isCategorySearch
        ? 'ผลการค้นหาหมวดหมู่สำหรับ '
        : _lastSubmittedQuery.isNotEmpty
        ? 'ผลการค้นหาสำหรับ '
        : 'ผลการค้นหาตามตัวกรอง';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 13.5,
                    ),
                    children: [
                      TextSpan(text: heading),
                      if (isCategorySearch || _lastSubmittedQuery.isNotEmpty)
                        TextSpan(
                          text: '"$searchTerm"',
                          style: const TextStyle(
                            color: Color(0xFF18181B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isPlaceholder) ...[
                Text(
                  '${_searchResults.length} รายการ',
                  style: const TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                CategoryFilterButton(
                  categories: _categories,
                  selectedCategoryId: _selectedCategoryId,
                  minPrice: _minPrice,
                  maxPrice: _maxPrice,
                  minRating: _minRating,
                  onApplyFilter:
                      ({required categoryId, minPrice, maxPrice, minRating}) =>
                          _applyFilter(
                            categoryId: categoryId,
                            minPrice: minPrice,
                            maxPrice: maxPrice,
                            minRating: minRating,
                          ),
                  onResetFilter: _resetFilter,
                ),
              ],
            ],
          ),
          if (!isPlaceholder)
            ActiveCategoryTag(
              categories: _categories,
              selectedCategoryId: _selectedCategoryId,
              minPrice: _minPrice,
              maxPrice: _maxPrice,
              minRating: _minRating,
              onClearCategory: () => _applyFilter(
                categoryId: 'all',
                minPrice: _minPrice,
                maxPrice: _maxPrice,
                minRating: _minRating,
              ),
              onClearPrice: () => _applyFilter(
                categoryId: _selectedCategoryId,
                minPrice: null,
                maxPrice: null,
                minRating: _minRating,
              ),
              onClearRating: () => _applyFilter(
                categoryId: _selectedCategoryId,
                minPrice: _minPrice,
                maxPrice: _maxPrice,
                minRating: null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyResultsState() {
    final hasSearchError = _searchErrorMessage != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: hasSearchError
                    ? const Color(0xFFFFEEEE)
                    : const Color(0xFFF4F4F5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearchError
                    ? Icons.cloud_off_rounded
                    : Icons.search_off_rounded,
                size: 36,
                color: hasSearchError
                    ? const Color(0xFFE53935)
                    : const Color(0xFF71717A),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasSearchError
                  ? _searchErrorMessage!
                  : _selectedCategoryId != 'all'
                  ? 'ไม่พบอุปกรณ์ในหมวดหมู่ "${CategoryFilterChips.getCategoryLabel(_selectedCategoryId)}"'
                  : _lastSubmittedQuery.isNotEmpty
                  ? 'ไม่พบอุปกรณ์ที่ตรงกับ "$_lastSubmittedQuery"'
                  : 'ไม่พบอุปกรณ์ที่ตรงกับตัวกรองนี้',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF18181B),
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearchError
                  ? 'ตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองค้นหาอีกครั้ง'
                  : 'ลองตรวจสอบตัวสะกด หรือใช้คำค้นหาทั่วไป\nเช่น "กล้อง", "MacBook", "เต็นท์", "ไมโครโฟน"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF71717A),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: hasSearchError
                  ? () => _executeSearch(_lastSubmittedQuery)
                  : _resetToPreSearch,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
                side: const BorderSide(
                  color: AppColors.primaryColor,
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(
                hasSearchError ? 'กรุณาลองอีกครั้ง' : 'กลับไปดูอุปกรณ์แนะนำ',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchItemSkeletonCard extends StatelessWidget {
  const _SearchItemSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: const SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: ColoredBox(color: Color(0xFFE4E4E7)),
            ),
            Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: double.infinity,
                    height: 13,
                    borderRadius: 6,
                  ),
                  SizedBox(height: 6),
                  SkeletonBox(width: 90, height: 13, borderRadius: 6),
                  SizedBox(height: 10),
                  SkeletonBox(width: 70, height: 16, borderRadius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

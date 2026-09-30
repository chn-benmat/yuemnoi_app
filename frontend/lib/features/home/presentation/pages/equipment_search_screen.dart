import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/entities/feed_category.dart';
import '../../domain/entities/feed_item.dart';
import '../../domain/repositories/home_repository.dart';
import '../widgets/category_filter_sheet.dart';
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
    this.initialCategories,
    this.homeRepository,
  });

  final List<FeedItem>? initialCuratedItems;
  final String? initialQuery;
  final List<FeedCategory>? initialCategories;
  final HomeRepository? homeRepository;

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

  @override
  void initState() {
    super.initState();
    _repository = widget.homeRepository ?? HomeRepositoryImpl();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _focusNode = FocusNode();

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
      final list = prefs.getStringList(_recentSearchesKey) ?? [];
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

    // เก็บประวัติสูงสุด 10 คำค้นหา
    if (updated.length > 10) {
      updated.removeRange(10, updated.length);
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

  Future<void> _deleteSearchTag(String query) async {
    final updated = List<String>.from(_recentSearches)..remove(query);
    if (mounted) {
      setState(() {
        _recentSearches = updated;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentSearchesKey, updated);
    } catch (e) {
      debugPrint('Error deleting search tag: $e');
    }
  }

  Future<void> _clearAllRecentSearches() async {
    if (mounted) {
      setState(() {
        _recentSearches = [];
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSearchesKey);
    } catch (e) {
      debugPrint('Error clearing recent searches: $e');
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
    if (trimmed.isEmpty) return;

    _focusNode.unfocus();
    _searchController.text = trimmed;

    setState(() {
      _isSearchSubmitted = true;
      _isLoadingResults = true;
      _lastSubmittedQuery = trimmed;
    });

    await _saveSearchQuery(trimmed);

    try {
      final results = await _repository.getNearbyItems(
        categoryId: _selectedCategoryId != 'all' ? _selectedCategoryId : null,
        searchQuery: trimmed,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        minRating: _minRating,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoadingResults = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching items: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isLoadingResults = false;
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
      _lastSubmittedQuery.isNotEmpty ? _lastSubmittedQuery : _searchController.text,
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
      _lastSubmittedQuery.isNotEmpty ? _lastSubmittedQuery : _searchController.text,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดรายละเอียดอุปกรณ์ได้')),
      );
      return;
    }
    AppRoutes.openItemDetail(context, itemId: itemId);
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
                child: _isSearchSubmitted
                    ? _buildSearchResultsView()
                    : _buildPreSearchView(),
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
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE4E4E7),
            width: 1,
          ),
        ),
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
                                  _resetToPreSearch();
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

  Widget _buildPreSearchView() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 2.1 ส่วนคำค้นหาเก่า (Search History)
        if (_recentSearches.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ประวัติการค้นหา',
                    style: TextStyle(
                      color: Color(0xFF18181B),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('clear-all-recent-searches'),
                    onTap: _clearAllRecentSearches,
                    behavior: HitTestBehavior.opaque,
                    child: const Text(
                      'ล้างทั้งหมด',
                      style: TextStyle(
                        color: Color(0xFF71717A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentSearches.map((query) {
                  return _buildHistoryTag(query);
                }).toList(),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 20),
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

        // 2.2 ส่วนสิ่งที่ผู้เช่าสนใจ (Recommended item cards)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
            child: Row(
              children: [
                const Text(
                  'สิ่งที่คุณอาจสนใจ',
                  style: TextStyle(
                    color: Color(0xFF18181B),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'แนะนำ',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // รายการสินค้าแนะนำแบบ Item Cards (2-Column Grid)
        _buildCuratedGridSliver(),

        const SliverToBoxAdapter(
          child: SizedBox(height: 40),
        ),
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                query,
                style: const TextStyle(
                  color: Color(0xFF27272A),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _deleteSearchTag(query),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(1.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Color(0xFFA1A1AA),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCuratedGridSliver() {
    if (_isLoadingCurated && _curatedItems.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.61,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => const _SearchItemSkeletonCard(),
            childCount: 4,
          ),
        ),
      );
    }

    if (_curatedItems.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'ไม่มีอุปกรณ์แนะนำในขณะนี้',
              style: TextStyle(
                color: Color(0xFF71717A),
                fontSize: 13.5,
              ),
            ),
          ),
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
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = _curatedItems[index];
            return ShopeeProductCard(
              item: item,
              onTap: () => _onItemTap(item),
            );
          },
          childCount: _curatedItems.length,
        ),
      ),
    );
  }

  // ==========================================
  // 3. SEARCH RESULTS VIEW (แสดงเมื่อกดเสิร์ชแล้ว)
  // ==========================================

  Widget _buildSearchResultsView() {
    if (_isLoadingResults) {
      return Column(
        children: [
          _buildResultsHeader(isPlaceholder: true),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.61,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => const _SearchItemSkeletonCard(),
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
              if (_searchResults.isEmpty)
                SliverToBoxAdapter(
                  child: _buildEmptyResultsState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.61,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _searchResults[index];
                        return ShopeeProductCard(
                          item: item,
                          onTap: () => _onItemTap(item),
                        );
                      },
                      childCount: _searchResults.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 50),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsHeader({bool isPlaceholder = false}) {
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
                      const TextSpan(text: 'ผลการค้นหาสำหรับ '),
                      TextSpan(
                        text: '"$_lastSubmittedQuery"',
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
                  onApplyFilter: ({
                    required categoryId,
                    minPrice,
                    maxPrice,
                    minRating,
                  }) => _applyFilter(
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFF4F4F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 36,
                color: Color(0xFF71717A),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ไม่พบอุปกรณ์ที่ตรงกับ "$_lastSubmittedQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF18181B),
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ลองตรวจสอบตัวสะกด หรือใช้คำค้นหาทั่วไป\nเช่น "กล้อง", "MacBook", "เต็นท์", "ไมโครโฟน"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF71717A),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _resetToPreSearch,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
                side: const BorderSide(color: AppColors.primaryColor, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'กลับไปดูอุปกรณ์แนะนำ',
                style: TextStyle(
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
                  SkeletonBox(
                    width: 90,
                    height: 13,
                    borderRadius: 6,
                  ),
                  SizedBox(height: 10),
                  SkeletonBox(
                    width: 70,
                    height: 16,
                    borderRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

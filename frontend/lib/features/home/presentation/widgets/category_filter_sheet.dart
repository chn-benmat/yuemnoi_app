import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/feed_category.dart';

/// รายการตัวเลือกคะแนนรีวิว (1 ดาว ถึง 5 ดาว ไม่มีจุดทศนิยม)
class RatingFilterOption {
  const RatingFilterOption({
    required this.label,
    this.minRating,
    this.stars,
  });

  final String label;
  final double? minRating;
  final int? stars;
}

const List<RatingFilterOption> kRatingFilterOptions = [
  RatingFilterOption(label: 'ทั้งหมด', minRating: null, stars: null),
  RatingFilterOption(label: '5 ดาว', minRating: 5.0, stars: 5),
  RatingFilterOption(label: '4 ดาวขึ้นไป', minRating: 4.0, stars: 4),
  RatingFilterOption(label: '3 ดาวขึ้นไป', minRating: 3.0, stars: 3),
  RatingFilterOption(label: '2 ดาวขึ้นไป', minRating: 2.0, stars: 2),
  RatingFilterOption(label: '1 ดาวขึ้นไป', minRating: 1.0, stars: 1),
];

/// ปุ่มตัวกรองข้างช่องค้นหา (ไอคอน Filter แบบ Funnel / Filter List)
class CategoryFilterButton extends StatelessWidget {
  const CategoryFilterButton({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    this.minPrice,
    this.maxPrice,
    this.minRating,
    required this.onApplyFilter,
    required this.onResetFilter,
  });

  final List<FeedCategory> categories;
  final String selectedCategoryId;
  final int? minPrice;
  final int? maxPrice;
  final double? minRating;
  final void Function({
    required String categoryId,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) onApplyFilter;
  final VoidCallback onResetFilter;

  bool get isFilterActive =>
      selectedCategoryId != 'all' ||
      minPrice != null ||
      maxPrice != null ||
      minRating != null;

  void _showTopFilterModal(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'FilterModalTop',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: _FilterTopSheetDialog(
              categories: categories,
              initialCategoryId: selectedCategoryId,
              initialMinPrice: minPrice,
              initialMaxPrice: maxPrice,
              initialMinRating: minRating,
              onApply: (catId, minP, maxP, minR) {
                Navigator.pop(dialogContext);
                onApplyFilter(
                  categoryId: catId,
                  minPrice: minP,
                  maxPrice: maxP,
                  minRating: minR,
                );
              },
              onReset: () {
                Navigator.pop(dialogContext);
                onResetFilter();
              },
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: anim1,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: isFilterActive ? AppColors.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFilterActive
                  ? AppColors.primaryColor
                  : const Color(0xFFECEEF1),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isFilterActive
                    ? AppColors.primaryColor.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('category-filter-button'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showTopFilterModal(context),
              child: Icon(
                // เปลี่ยนไอคอน Filter เป็นรูปกรวยกรอง (Filter Alt) ตามที่ผู้ใช้ต้องการ
                Icons.filter_alt_rounded,
                color: isFilterActive ? Colors.white : const Color(0xFF4A4D4F),
                size: 24,
              ),
            ),
          ),
        ),

        // จุดสีแจ้งเตือนเมื่อมีเงื่อนไขตัวกรองทำงานอยู่
        if (isFilterActive)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// ป้ายแสดงตัวกรองที่เลือกอยู่ด้านล่าง Search Bar
class ActiveCategoryTag extends StatelessWidget {
  const ActiveCategoryTag({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    this.minPrice,
    this.maxPrice,
    this.minRating,
    required this.onClearCategory,
    required this.onClearPrice,
    required this.onClearRating,
  });

  final List<FeedCategory> categories;
  final String selectedCategoryId;
  final int? minPrice;
  final int? maxPrice;
  final double? minRating;
  final VoidCallback onClearCategory;
  final VoidCallback onClearPrice;
  final VoidCallback onClearRating;

  @override
  Widget build(BuildContext context) {
    final hasCategory = selectedCategoryId != 'all';
    final hasPrice = minPrice != null || maxPrice != null;
    final hasRating = minRating != null;

    if (!hasCategory && !hasPrice && !hasRating) {
      return const SizedBox.shrink();
    }

    final categoryName = categories
        .firstWhere(
          (c) => c.id == selectedCategoryId,
          orElse: () => FeedCategory(id: selectedCategoryId, name: selectedCategoryId),
        )
        .name;

    String priceLabel = '';
    if (minPrice != null && maxPrice != null) {
      if (minPrice == 1) {
        priceLabel = '≤ ฿$maxPrice';
      } else {
        priceLabel = '฿$minPrice - ฿$maxPrice';
      }
    } else if (minPrice != null) {
      priceLabel = '≥ ฿$minPrice';
    } else if (maxPrice != null) {
      priceLabel = '≤ ฿$maxPrice';
    }

    String ratingLabel = '';
    if (minRating != null) {
      final int ratingInt = minRating!.round();
      if (ratingInt >= 5) {
        ratingLabel = '⭐ 5 ดาว';
      } else {
        ratingLabel = '⭐ $ratingInt ดาวขึ้นไป';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (hasCategory)
            _FilterPill(
              keyName: 'clear-category-filter',
              label: categoryName,
              icon: Icons.category_rounded,
              onClear: onClearCategory,
            ),
          if (hasPrice)
            _FilterPill(
              keyName: 'clear-price-filter',
              label: priceLabel,
              icon: Icons.attach_money_rounded,
              onClear: onClearPrice,
            ),
          if (hasRating)
            _FilterPill(
              keyName: 'clear-rating-filter',
              label: ratingLabel,
              icon: Icons.star_rounded,
              onClear: onClearRating,
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.keyName,
    required this.label,
    required this.icon,
    required this.onClear,
  });

  final String keyName;
  final String label;
  final IconData icon;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: AppColors.primaryColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            key: ValueKey(keyName),
            onTap: onClear,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: AppColors.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// หน้าต่างตัวกรองที่เลื่อนลงมาจากด้านบน (Top Sheet Dialog พร้อม Sidebar สำหรับราคาและคะแนนรีวิว)
class _FilterTopSheetDialog extends StatefulWidget {
  const _FilterTopSheetDialog({
    required this.categories,
    required this.initialCategoryId,
    this.initialMinPrice,
    this.initialMaxPrice,
    this.initialMinRating,
    required this.onApply,
    required this.onReset,
  });

  final List<FeedCategory> categories;
  final String initialCategoryId;
  final int? initialMinPrice;
  final int? initialMaxPrice;
  final double? initialMinRating;
  final void Function(
    String categoryId,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  ) onApply;
  final VoidCallback onReset;

  @override
  State<_FilterTopSheetDialog> createState() => _FilterTopSheetDialogState();
}

class _FilterTopSheetDialogState extends State<_FilterTopSheetDialog> {
  // แท็บที่เลือกใน Sidebar: 0 = หมวดหมู่, 1 = กรองราคา, 2 = คะแนนรีวิว
  int _activeSidebarTabIndex = 0;

  late String _selectedCategoryId;
  int? _minPrice;
  int? _maxPrice;
  double? _minRating;

  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    _minPrice = widget.initialMinPrice;
    _maxPrice = widget.initialMaxPrice;
    _minRating = widget.initialMinRating;

    _minPriceController = TextEditingController(
      text: widget.initialMinPrice != null ? widget.initialMinPrice.toString() : '',
    );
    _maxPriceController = TextEditingController(
      text: widget.initialMaxPrice != null ? widget.initialMaxPrice.toString() : '',
    );
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String id) {
    switch (id) {
      case 'camera':
        return Icons.photo_camera_rounded;
      case 'audio':
        return Icons.headphones_rounded;
      case 'computer':
        return Icons.laptop_mac_rounded;
      case 'phone':
        return Icons.smartphone_rounded;
      case 'tools':
        return Icons.construction_rounded;
      case 'appliances':
        return Icons.kitchen_rounded;
      case 'camping':
        return Icons.forest_rounded;
      case 'sports':
        return Icons.fitness_center_rounded;
      case 'gaming':
        return Icons.sports_esports_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'other':
        return Icons.category_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  bool _isRatingSelected(RatingFilterOption opt) {
    return _minRating == opt.minRating;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        minHeight: 460,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ส่วนหัวติด Safe Area ด้านบน
          Container(
            padding: EdgeInsets.fromLTRB(20, topPadding + 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.primaryColor,
              borderRadius: BorderRadius.vertical(top: Radius.zero),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6B00B8),
                  AppColors.primaryColor,
                  Color(0xFF8618E2),
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.filter_alt_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'ตัวกรองสินค้า',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'ปิด',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          // ส่วนเนื้อหาแบบ Sidebar 2 คอลัมน์ (Sidebar ซ้ายขนาดกะทัดรัด + Content ขวา)
          Flexible(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Sidebar ด้านซ้าย (หมวดหมู่ / กรองราคา / คะแนนรีวิว) ขนาดกะทัดรัด
                Container(
                  width: 92,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8F9FA),
                    border: Border(
                      right: BorderSide(
                        color: Color(0xFFE9ECEF),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildSidebarItem(
                        index: 0,
                        title: 'หมวดหมู่',
                        icon: Icons.category_rounded,
                        isActive: _selectedCategoryId != 'all',
                      ),
                      _buildSidebarItem(
                        index: 1,
                        title: 'กรองราคา',
                        icon: Icons.attach_money_rounded,
                        isActive: _minPrice != null || _maxPrice != null,
                      ),
                      _buildSidebarItem(
                        index: 2,
                        title: 'คะแนนรีวิว',
                        icon: Icons.star_rounded,
                        isActive: _minRating != null,
                      ),
                    ],
                  ),
                ),

                // 2. Content ด้านขวา ตามแท็บที่เลือกใน Sidebar
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: _buildActiveTabContent(),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE9ECEF)),

          // แถบปุ่มดำเนินการด้านล่างของ Modal (ล้างตัวกรอง & นำไปใช้)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    key: const ValueKey('reset-filter-modal-button'),
                    onPressed: widget.onReset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4B5563),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'ล้างทั้งหมด',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    key: const ValueKey('apply-filter-modal-button'),
                    onPressed: () {
                      widget.onApply(
                        _selectedCategoryId,
                        _minPrice,
                        _maxPrice,
                        _minRating,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'นำไปใช้',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required String title,
    required IconData icon,
    required bool isActive,
  }) {
    final isSelected = _activeSidebarTabIndex == index;

    return Material(
      color: isSelected ? Colors.white : Colors.transparent,
      child: InkWell(
        key: ValueKey('sidebar-tab-$index'),
        onTap: () {
          setState(() {
            _activeSidebarTabIndex = index;
          });
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? AppColors.primaryColor : Colors.transparent,
                width: 3.0,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? AppColors.primaryColor
                        : const Color(0xFF6C757D),
                  ),
                  if (isActive)
                    Positioned(
                      top: -2,
                      right: -3,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primaryColor
                      : const Color(0xFF495057),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeSidebarTabIndex) {
      case 0:
        return _buildCategoryContent();
      case 1:
        return _buildPriceContent();
      case 2:
        return _buildRatingContent();
      default:
        return const SizedBox.shrink();
    }
  }

  // แท็บ 1: หมวดหมู่สินค้า
  Widget _buildCategoryContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'หมวดหมู่อุปกรณ์ (11 หมวด)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212529),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            itemCount: widget.categories.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final category = widget.categories[index];
              final isSelected = _selectedCategoryId == category.id;
              final icon = _getCategoryIcon(category.id);

              return Material(
                color: isSelected
                    ? const Color(0xFFF4EBFF)
                    : const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey('filter-category-item-${category.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedCategoryId = category.id;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: isSelected
                              ? AppColors.primaryColor
                              : const Color(0xFF6C757D),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            category.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primaryColor
                                  : const Color(0xFF343A40),
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primaryColor,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // แท็บ 2: กรองราคา (ช่องกรอกราคาต่ำสุดและสูงสุด)
  Widget _buildPriceContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ช่วงราคาเช่าต่อวัน (฿)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212529),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ระบุราคาต่ำสุดและราคาสูงสุดที่ต้องการ',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF6C757D),
            ),
          ),
          const SizedBox(height: 16),

          // ช่องกรอกราคาต่ำสุดและราคาสูงสุด
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ช่องราคาต่ำสุด
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ราคาต่ำสุด',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF495057),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('filter-min-price-input'),
                      controller: _minPriceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF212529),
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFADB5BD),
                        ),
                        prefixText: '฿ ',
                        prefixStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryColor,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primaryColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          final trimmed = value.trim();
                          _minPrice = trimmed.isEmpty ? null : int.tryParse(trimmed);
                        });
                      },
                    ),
                  ],
                ),
              ),

              // เส้นคั่นระหว่างช่อง
              const Padding(
                padding: EdgeInsets.only(top: 22, left: 8, right: 8),
                child: Text(
                  '-',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFADB5BD),
                  ),
                ),
              ),

              // ช่องราคาสูงสุด
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ราคาสูงสุด',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF495057),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('filter-max-price-input'),
                      controller: _maxPriceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF212529),
                      ),
                      decoration: InputDecoration(
                        hintText: 'ไม่จำกัด',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFADB5BD),
                        ),
                        prefixText: '฿ ',
                        prefixStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryColor,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primaryColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          final trimmed = value.trim();
                          _maxPrice = trimmed.isEmpty ? null : int.tryParse(trimmed);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ปุ่มลัดเลือกช่วงราคา (Quick price presets)
          const Text(
            'ช่วงราคายอดนิยม',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6C757D),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPricePresetChip(
                label: 'ไม่เกิน 500 ฿',
                min: 1,
                max: 500,
              ),
              _buildPricePresetChip(
                label: '500 - 1,000 ฿',
                min: 500,
                max: 1000,
              ),
              _buildPricePresetChip(
                label: '1,000 - 2,000 ฿',
                min: 1000,
                max: 2000,
              ),
              _buildPricePresetChip(
                label: 'ไม่เกิน 2,000 ฿',
                min: 1,
                max: 2000,
              ),
              _buildPricePresetChip(
                label: '2,000 ฿ ขึ้นไป',
                min: 2000,
                max: null,
              ),
            ],
          ),

          if (_minPrice != null || _maxPrice != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('clear-price-tab-button'),
                onPressed: () {
                  setState(() {
                    _minPrice = null;
                    _maxPrice = null;
                    _minPriceController.clear();
                    _maxPriceController.clear();
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text(
                  'ล้างช่วงราคา',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPricePresetChip({
    required String label,
    required int? min,
    required int? max,
  }) {
    final isSelected = _minPrice == min && _maxPrice == max;

    return Material(
      color: isSelected ? const Color(0xFFF4EBFF) : const Color(0xFFF8F9FA),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _minPrice = min;
            _maxPrice = max;
            _minPriceController.text = min?.toString() ?? '';
            _maxPriceController.text = max?.toString() ?? '';
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primaryColor : const Color(0xFFE9ECEF),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppColors.primaryColor : const Color(0xFF495057),
            ),
          ),
        ),
      ),
    );
  }

  // แท็บ 3: คะแนนรีวิว (1 ดาว ถึง 5 ดาว ไม่มีจุดทศนิยม)
  Widget _buildRatingContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'คะแนนรีวิว',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212529),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'เลือกระดับคะแนนความพึงพอใจ (1 - 5 ดาว)',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF6C757D),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: kRatingFilterOptions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final opt = kRatingFilterOptions[index];
                final isSelected = _isRatingSelected(opt);

                return Material(
                  color: isSelected
                      ? const Color(0xFFF4EBFF)
                      : const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: ValueKey('filter-rating-option-$index'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _minRating = opt.minRating;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 18,
                            color: isSelected
                                ? AppColors.primaryColor
                                : const Color(0xFFADB5BD),
                          ),
                          const SizedBox(width: 10),
                          if (opt.stars != null) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(5, (starIdx) {
                                final isFilled = starIdx < opt.stars!;
                                return Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: isFilled
                                      ? const Color(0xFFFFB800)
                                      : const Color(0xFFE2E8F0),
                                );
                              }),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              opt.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.primaryColor
                                    : const Color(0xFF343A40),
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_rounded,
                              color: AppColors.primaryColor,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


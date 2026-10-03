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
            color: isFilterActive ? const Color(0xFFF3E8FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isFilterActive
                ? Border.all(color: Colors.white, width: 1.5)
                : null,
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
              key: const ValueKey('category-filter-button'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showTopFilterModal(context),
              child: const Icon(
                // เปลี่ยนไอคอน Filter เป็นรูปกรวยกรอง (Filter Alt) ตามที่ผู้ใช้ต้องการ
                Icons.filter_alt_rounded,
                color: AppColors.primaryColor,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
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

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategoryId != 'all') count++;
    if (_minPrice != null || _maxPrice != null) count++;
    if (_minRating != null) count++;
    return count;
  }

  void _resetLocalFilters() {
    setState(() {
      _selectedCategoryId = 'all';
      _minPrice = null;
      _maxPrice = null;
      _minRating = null;
      _minPriceController.clear();
      _maxPriceController.clear();
    });
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
        minHeight: 380,
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
                Row(
                  children: [
                    const Icon(
                      Icons.filter_alt_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ตัวกรองสินค้า',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_activeFilterCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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

          // ส่วนเนื้อหาแบบ Single Page Scroll (สไตล์ Shopee/Lazada เลื่อนลงหน้าเดียว)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. ช่วงราคา (Price Range) ──
                  _buildPriceSection(),

                  const SizedBox(height: 18),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 18),

                  // ── 2. หมวดหมู่อุปกรณ์ (Categories) ──
                  _buildCategorySection(),

                  const SizedBox(height: 18),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 18),

                  // ── 3. คะแนนรีวิว (Rating) ──
                  _buildRatingSection(),
                ],
              ),
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
                    onPressed: () {
                      _resetLocalFilters();
                      widget.onReset();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
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
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(
                      _activeFilterCount > 0
                          ? 'นำไปใช้ ($_activeFilterCount)'
                          : 'นำไปใช้',
                      style: const TextStyle(
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

  // ── ส่วนที่ 1: ช่วงราคา (Price Range) ──
  Widget _buildPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    size: 16,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ช่วงราคาเช่าต่อวัน (฿)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            if (_minPrice != null || _maxPrice != null)
              GestureDetector(
                key: const ValueKey('clear-price-tab-button'),
                onTap: () {
                  setState(() {
                    _minPrice = null;
                    _maxPrice = null;
                    _minPriceController.clear();
                    _maxPriceController.clear();
                  });
                },
                child: const Text(
                  'รีเซ็ต',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // ช่องกรอกราคาต่ำสุดและราคาสูงสุด
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('filter-min-price-input'),
                controller: _minPriceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
                decoration: InputDecoration(
                  hintText: 'ต่ำสุด (฿0)',
                  hintStyle: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF94A3B8),
                  ),
                  prefixText: '฿ ',
                  prefixStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryColor,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
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
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '-',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('filter-max-price-input'),
                controller: _maxPriceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
                decoration: InputDecoration(
                  hintText: 'สูงสุด (ไม่จำกัด)',
                  hintStyle: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF94A3B8),
                  ),
                  prefixText: '฿ ',
                  prefixStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryColor,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
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
            ),
          ],
        ),
        const SizedBox(height: 10),
        // ปุ่มลัดช่วงราคายอดนิยม
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPricePresetChip(label: 'ไม่เกิน 500 ฿', min: 1, max: 500),
            _buildPricePresetChip(label: '500 - 1,000 ฿', min: 500, max: 1000),
            _buildPricePresetChip(label: '1,000 - 2,000 ฿', min: 1000, max: 2000),
            _buildPricePresetChip(label: '2,000 ฿ ขึ้นไป', min: 2000, max: null),
          ],
        ),
      ],
    );
  }

  Widget _buildPricePresetChip({
    required String label,
    required int? min,
    required int? max,
  }) {
    final isSelected = _minPrice == min && _maxPrice == max;

    return Material(
      color: isSelected ? const Color(0xFFF4EBFF) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            if (isSelected) {
              _minPrice = null;
              _maxPrice = null;
              _minPriceController.clear();
              _maxPriceController.clear();
            } else {
              _minPrice = min;
              _maxPrice = max;
              _minPriceController.text = min?.toString() ?? '';
              _maxPriceController.text = max?.toString() ?? '';
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryColor
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? AppColors.primaryColor
                  : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  // ── ส่วนที่ 2: หมวดหมู่อุปกรณ์ (Categories - Shopee/Lazada Wrap Grid) ──
  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    size: 16,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'หมวดหมู่อุปกรณ์',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            if (_selectedCategoryId != 'all')
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategoryId = 'all';
                  });
                },
                child: const Text(
                  'รีเซ็ต',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.categories.map((category) {
            final isSelected = _selectedCategoryId == category.id;
            final icon = _getCategoryIcon(category.id);

            return Material(
              color: isSelected
                  ? const Color(0xFFF4EBFF)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('filter-category-item-${category.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() {
                    _selectedCategoryId = isSelected && category.id != 'all'
                        ? 'all'
                        : category.id;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryColor
                          : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: isSelected
                            ? AppColors.primaryColor
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        category.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? AppColors.primaryColor
                              : const Color(0xFF334155),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: AppColors.primaryColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── ส่วนที่ 3: คะแนนรีวิว (Rating) ──
  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'คะแนนรีวิว',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            if (_minRating != null)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _minRating = null;
                  });
                },
                child: const Text(
                  'รีเซ็ต',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kRatingFilterOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final opt = entry.value;
            final isSelected = _isRatingSelected(opt);

            return Material(
              color: isSelected
                  ? const Color(0xFFF4EBFF)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('filter-rating-option-$index'),
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() {
                    _minRating = isSelected && opt.minRating != null
                        ? null
                        : opt.minRating;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryColor
                          : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (opt.stars != null) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 15,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? AppColors.primaryColor
                              : const Color(0xFF334155),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: AppColors.primaryColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}


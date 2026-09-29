import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/feed_category.dart';

/// โมเดลข้อมูลสำหรับแสดงผลในแถบหมวดหมู่
class CategoryChipItem {
  final String id;
  final String label;
  final IconData? icon;
  final String? imageAsset;

  const CategoryChipItem({
    required this.id,
    required this.label,
    this.icon,
    this.imageAsset,
  });
}

/// แถบหมวดหมู่เลื่อนแนวนอน (Horizontal Category Chips) สไตล์ Swiss Style / Clean SaaS
/// - รองรับ Single Selection
/// - สถานะที่เลือก: พื้นหลังม่วง Yuemnoi ไอคอนและตัวหนังสือสีขาว
/// - สถานะปกติ: พื้นหลังขาว เส้นขอบบาง สีเทาเข้ม
/// - เลื่อนแนวนอนแบบเรียบเนียน (contentPadding ซ้าย-ขวา 16px พอดีกับขอบหน้าจอ)
class CategoryFilterChips extends StatelessWidget {
  const CategoryFilterChips({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  final List<FeedCategory> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onCategorySelected;

  /// รายการหมวดหมู่หลักพร้อมไอคอนที่กำหนดตามดีไซน์
  static const List<CategoryChipItem> _orderedCategories = [
    CategoryChipItem(
      id: 'all',
      label: 'ทั้งหมด',
      icon: Icons.grid_view_rounded,
    ),
    CategoryChipItem(
      id: 'camera',
      label: 'กล้องถ่ายภาพ',
      icon: Icons.photo_camera_rounded,
      imageAsset: 'assets/icons/camera.png',
    ),
    CategoryChipItem(
      id: 'camping',
      label: 'แคมป์ปิ้ง',
      icon: Icons.forest_rounded,
      imageAsset: 'assets/icons/tent.png',
    ),
    CategoryChipItem(
      id: 'computer',
      label: 'คอมพิวเตอร์/ไอที',
      icon: Icons.laptop_mac_rounded,
      imageAsset: 'assets/icons/computer.png',
    ),
    CategoryChipItem(
      id: 'music',
      label: 'เครื่องดนตรี',
      icon: Icons.music_note_rounded,
      imageAsset: 'assets/icons/guitar.png',
    ),
    CategoryChipItem(
      id: 'gaming',
      label: 'เกม/บันเทิง',
      icon: Icons.sports_esports_rounded,
      imageAsset: 'assets/icons/joystick.png',
    ),
    CategoryChipItem(
      id: 'tools',
      label: 'อุปกรณ์ช่าง',
      icon: Icons.handyman_rounded,
      imageAsset: 'assets/icons/drill.png',
    ),
    CategoryChipItem(
      id: 'audio',
      label: 'เครื่องเสียง',
      icon: Icons.headphones_rounded,
      imageAsset: 'assets/icons/audio.png',
    ),
    CategoryChipItem(
      id: 'phone',
      label: 'โทรศัพท์/สื่อสาร',
      icon: Icons.smartphone_rounded,
      imageAsset: 'assets/icons/phone.png',
    ),
    CategoryChipItem(
      id: 'sports',
      label: 'กีฬา/ฟิตเนส',
      icon: Icons.fitness_center_rounded,
      imageAsset: 'assets/icons/dumbell.png',
    ),
  ];

  static IconData _getIconForCategory(String id) {
    switch (id.toLowerCase().trim()) {
      case 'all':
        return Icons.grid_view_rounded;
      case 'camera':
        return Icons.photo_camera_rounded;
      case 'camping':
        return Icons.forest_rounded;
      case 'computer':
        return Icons.laptop_mac_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'gaming':
        return Icons.sports_esports_rounded;
      case 'tools':
        return Icons.handyman_rounded;
      case 'phone':
        return Icons.smartphone_rounded;
      case 'audio':
        return Icons.headphones_rounded;
      case 'sports':
        return Icons.fitness_center_rounded;
      case 'appliances':
        return Icons.kitchen_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  static String? _getImageForCategory(String id) {
    switch (id.toLowerCase().trim()) {
      case 'camera':
        return 'assets/icons/camera.png';
      case 'camping':
        return 'assets/icons/tent.png';
      case 'computer':
        return 'assets/icons/computer.png';
      case 'music':
        return 'assets/icons/guitar.png';
      case 'gaming':
        return 'assets/icons/joystick.png';
      case 'tools':
        return 'assets/icons/drill.png';
      case 'audio':
        return 'assets/icons/audio.png';
      case 'phone':
        return 'assets/icons/phone.png';
      case 'sports':
        return 'assets/icons/dumbell.png';
      default:
        return null;
    }
  }

  static String _getLabelForCategory(String id, String rawName) {
    switch (id.toLowerCase().trim()) {
      case 'all':
        return 'ทั้งหมด';
      case 'camera':
        return 'กล้องถ่ายภาพ';
      case 'camping':
        return 'แคมป์ปิ้ง';
      case 'computer':
        return 'คอมพิวเตอร์/ไอที';
      case 'music':
        return 'เครื่องดนตรี';
      case 'gaming':
        return 'เกม/บันเทิง';
      case 'tools':
        return 'อุปกรณ์ช่าง';
      case 'phone':
        return 'โทรศัพท์/สื่อสาร';
      case 'audio':
        return 'เครื่องเสียง';
      case 'sports':
        return 'กีฬา/ฟิตเนส';
      case 'appliances':
        return 'เครื่องใช้ไฟฟ้า';
      default:
        return rawName.isNotEmpty ? rawName : id;
    }
  }

  static bool _isExcludedCategory(String id, String rawName) {
    final lowerId = id.toLowerCase().trim();
    final lowerName = rawName.toLowerCase().trim();
    return lowerId == 'appliances' ||
        lowerId.contains('appliance') ||
        lowerName.contains('เครื่องใช้ไฟฟ้า') ||
        lowerId == 'other' ||
        lowerId == 'others' ||
        lowerName.contains('อื่น');
  }

  List<CategoryChipItem> _buildItems() {
    if (categories.isEmpty) {
      return _orderedCategories
          .where((cat) => !_isExcludedCategory(cat.id, cat.label))
          .toList();
    }

    final Map<String, FeedCategory> categoryMap = {
      for (final cat in categories)
        if (!_isExcludedCategory(cat.id, cat.name))
          cat.id.toLowerCase().trim(): cat,
    };

    final List<CategoryChipItem> items = [];
    final Set<String> addedIds = {};

    // 1. นำหมวดหมู่หลักที่มีลำดับตาม Requirement มาแสดงก่อน (กรองหมวดหมู่ที่ไม่ต้องการออก เช่น เครื่องใช้ไฟฟ้า)
    for (final pref in _orderedCategories) {
      if (!_isExcludedCategory(pref.id, pref.label) &&
          (categoryMap.containsKey(pref.id) || pref.id == 'all')) {
        items.add(pref);
        addedIds.add(pref.id);
      }
    }

    // 2. ตามด้วยหมวดหมู่อื่นๆ ที่เหลือจากระบบ (ยกเว้นหมวดหมู่ที่ถูกตัดออก เช่น เครื่องใช้ไฟฟ้า)
    for (final cat in categories) {
      final id = cat.id.toLowerCase().trim();
      if (!addedIds.contains(id) && !_isExcludedCategory(cat.id, cat.name)) {
        items.add(
          CategoryChipItem(
            id: cat.id,
            label: _getLabelForCategory(cat.id, cat.name),
            icon: _getIconForCategory(cat.id),
            imageAsset: _getImageForCategory(cat.id),
          ),
        );
        addedIds.add(id);
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();

    return SizedBox(
      height: 72,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected =
              item.id.toLowerCase().trim() ==
              selectedCategoryId.toLowerCase().trim();

          return _CategoryChip(
            item: item,
            isSelected: isSelected,
            onTap: () {
              HapticFeedback.lightImpact();
              onCategorySelected(item.id);
            },
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final CategoryChipItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('category-chip-${item.id}'),
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── กล่องสี่เหลี่ยมจัตุรัสพื้นหลังสีขาวล้วน + โลโก้สีม่วง ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  border: isSelected
                      ? Border.all(color: const Color(0xFFE9D5FF), width: 2.0)
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.8),
                          width: 1.0,
                        ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Center(
                  child: item.imageAsset != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            item.imageAsset!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              item.icon ?? Icons.photo_camera_rounded,
                              size: 22,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        )
                      : Icon(
                          item.icon ?? Icons.category_rounded,
                          size: 22,
                          color: AppColors.primaryColor,
                        ),
                ),
              ),
              const SizedBox(height: 4),
              // ── ตัวอักษรชื่อหมวดหมู่อยู่ข้างล่างสี่เหลี่ยมจัตุรัส ──
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.1,
                  shadows: const [
                    Shadow(
                      color: Color(0x33000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              // ── Active Indicator Pill ด้านล่างสำหรับสถานะที่เลือก ──
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isSelected ? 1.0 : 0.0,
                child: Container(
                  width: 14,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';

class MyItemsScreen extends StatefulWidget {
  const MyItemsScreen({super.key});

  @override
  State<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends State<MyItemsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  final List<String> _categories = ['ทั้งหมด', 'โทรศัพท์', 'กล้อง'];

  final List<_ItemData> _items = [
    _ItemData(
      title: 'กล้อง',
      category: 'กล้อง',
      subtitle: 'อุปกรณ์อิเล็กทรอนิกส์/กล้อง',
      location: 'กรุงเทพฯ',
      imageCount: 1,
      iconData: Icons.camera_alt_outlined,
    ),
    _ItemData(
      title: 'มือถือ',
      category: 'โทรศัพท์',
      subtitle: 'อุปกรณ์อิเล็กทรอนิกส์/มือถือ',
      location: 'กรุงเทพฯ',
      imageCount: 1,
      iconData: Icons.smartphone_outlined,
    ),
  ];

  List<_ItemData> get _filteredItems {
    if (_selectedTab == 0) return _items;
    final cat = _categories[_selectedTab];
    return _items.where((item) => item.category == cat).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this)
      ..addListener(() {
        setState(() => _selectedTab = _tabController.index);
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: Column(
        children: [
          // ── Tab bar ─────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: List.generate(_categories.length, (i) {
                final selected = _selectedTab == i;
                return GestureDetector(
                  onTap: () {
                    _tabController.animateTo(i);
                    setState(() => _selectedTab = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryColor
                          : const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      _categories[i],
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            selected ? Colors.white : AppColors.primaryColor,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Item list ────────────────────────────────
          Expanded(
            child: _filteredItems.isEmpty
                ? Center(
                    child: Text(
                      'ไม่พบอุปกรณ์',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: AppColors.hintTextColor,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredItems.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _ItemCard(item: _filteredItems[index]),
                  ),
          ),
        ],
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
          onPressed: () => AppRoutes.openAddRentalItem(context),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ItemData {
  final String title;
  final String category;
  final String subtitle;
  final String location;
  final int imageCount;
  final IconData iconData;

  const _ItemData({
    required this.title,
    required this.category,
    required this.subtitle,
    required this.location,
    required this.imageCount,
    required this.iconData,
  });
}

class _ItemCard extends StatelessWidget {
  final _ItemData item;
  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Thumbnail ─────────────────────────────
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(16)),
            child: Container(
              width: 80,
              height: 86,
              color: const Color(0xFFEEEEEE),
              child: Icon(item.iconData, color: Colors.grey, size: 32),
            ),
          ),

          // ── Info ──────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.subtitle}\n${item.location}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      color: AppColors.labelColor,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ActionChip(
                        icon: Icons.photo_library_outlined,
                        label: '${item.imageCount} รูป',
                      ),
                      const SizedBox(width: 10),
                      const _ActionChip(
                        icon: Icons.share_outlined,
                        label: 'แชร์',
                      ),
                      const SizedBox(width: 10),
                      const _ActionChip(
                        icon: Icons.copy_outlined,
                        label: 'คัดลอก',
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {},
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.primaryColor,
                        ),
                      ),
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

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.fieldIconColor),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10,
            color: AppColors.labelColor,
          ),
        ),
      ],
    );
  }
}

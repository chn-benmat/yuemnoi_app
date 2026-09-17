import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';

class MyItemsScreen extends StatefulWidget {
  const MyItemsScreen({super.key});

  @override
  State<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends State<MyItemsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;
  bool _isLoading = true;

  List<String> _categories = ['ทั้งหมด'];
  List<_ItemData> _items = [];

  List<_ItemData> get _filteredItems {
    if (_selectedTab == 0 || _selectedTab >= _categories.length) {
      return _items;
    }
    final cat = _categories[_selectedTab];
    return _items.where((item) => item.category == cat).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _loadMyItems();
  }

  Future<void> _loadMyItems() async {
    if (!SupabaseConfig.isInitialized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await SupabaseConfig.client
          .from('item_tb')
          .select(
              'id, user_id, item_name, item_image_url, description, category, price, status')
          .eq('user_id', currentUserId)
          .order('id', ascending: false);

      final List<_ItemData> loaded = [];
      final Set<String> cats = {'ทั้งหมด'};

      for (final item in response) {
        final id = (item['id'] as num?)?.toInt();
          final title = item['item_name']?.toString() ?? 'อุปกรณ์';
          final cat = item['category']?.toString() ?? 'ทั่วไป';
          final desc = item['description']?.toString() ?? '';
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
          final imageUrl = _extractFirstImageUrl(item['item_image_url']);
          final imageCount = _extractImageCount(item['item_image_url']);
          final icon = _mapCategoryToIcon(cat);

          cats.add(cat);
          loaded.add(
            _ItemData(
              id: id,
              title: title,
              category: cat,
              subtitle: desc.isNotEmpty ? desc : 'หมวดหมู่: $cat',
              price: price,
              location: 'กรุงเทพฯ',
              imageCount: imageCount > 0 ? imageCount : 1,
              imageUrl: imageUrl,
              iconData: icon,
            ),
          );
        }

      if (mounted) {
        _tabController.dispose();
        _categories = cats.toList();
        _selectedTab = 0;
        _tabController = TabController(length: _categories.length, vsync: this)
          ..addListener(() {
            setState(() => _selectedTab = _tabController.index);
          });

        setState(() {
          _items = loaded;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _extractFirstImageUrl(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      for (final el in raw) {
        if (el != null && el.toString().trim().isNotEmpty) {
          return el.toString().trim();
        }
      }
      return null;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List && decoded.isNotEmpty) {
            return decoded.first.toString().trim();
          }
        } catch (_) {}
      }
      return trimmed;
    }
    return null;
  }

  int _extractImageCount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is List) return raw.length;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) return decoded.length;
        } catch (_) {}
      }
      return trimmed.isNotEmpty ? 1 : 0;
    }
    return 0;
  }

  IconData _mapCategoryToIcon(String? category) {
    if (category == null) return Icons.devices_other_outlined;
    final cat = category.toLowerCase();
    if (cat.contains('กล้อง') || cat.contains('camera')) {
      return Icons.camera_alt_outlined;
    }
    if (cat.contains('โดรน') || cat.contains('drone')) {
      return Icons.flight_takeoff_outlined;
    }
    if (cat.contains('โทรศัพท์') ||
        cat.contains('มือถือ') ||
        cat.contains('phone')) {
      return Icons.smartphone_outlined;
    }
    if (cat.contains('คอมพิวเตอร์') ||
        cat.contains('โน้ตบุ๊ก') ||
        cat.contains('laptop') ||
        cat.contains('macbook')) {
      return Icons.laptop_mac_outlined;
    }
    if (cat.contains('เสียง') ||
        cat.contains('ลำโพง') ||
        cat.contains('audio')) {
      return Icons.speaker_outlined;
    }
    if (cat.contains('แคมป์') || cat.contains('เต็นท์')) {
      return Icons.terrain_outlined;
    }
    if (cat.contains('รถ') || cat.contains('ยานยนต์')) {
      return Icons.directions_car_outlined;
    }
    if (cat.contains('เครื่องมือ') ||
        cat.contains('ทำความสะอาด') ||
        cat.contains('tool')) {
      return Icons.build_outlined;
    }
    if (cat.contains('เสื้อ') || cat.contains('สูท')) {
      return Icons.checkroom_outlined;
    }
    return Icons.inventory_2_outlined;
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            )
          : RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: _loadMyItems,
              child: Column(
                children: [
                  // ── Tab bar ─────────────────────────────────
                  if (_categories.length > 1)
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
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
                                    color: selected
                                        ? Colors.white
                                        : AppColors.primaryColor,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),

                  // ── Item list ────────────────────────────────
                  Expanded(
                    child: _filteredItems.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF3E8FF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.inventory_2_outlined,
                                      color: AppColors.primaryColor,
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'คุณยังไม่มีอุปกรณ์ที่ปล่อยเช่า',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'กดปุ่มด้านล่างเพื่อเริ่มลงประกาศปล่อยเช่าอุปกรณ์ของคุณ',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 13,
                                      color: AppColors.hintTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredItems.length,
                            separatorBuilder: (context, i) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _ItemCard(item: _filteredItems[index]),
                          ),
                  ),
                ],
              ),
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
          onPressed: () async {
            await AppRoutes.openAddRentalItem(context);
            _loadMyItems();
          },
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
  final int? id;
  final String title;
  final String category;
  final String subtitle;
  final double price;
  final String location;
  final int imageCount;
  final String? imageUrl;
  final IconData iconData;

  const _ItemData({
    this.id,
    required this.title,
    required this.category,
    required this.subtitle,
    this.price = 0.0,
    required this.location,
    required this.imageCount,
    this.imageUrl,
    required this.iconData,
  });
}

class _ItemCard extends StatelessWidget {
  final _ItemData item;
  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (item.id != null) {
          AppRoutes.openItemDetail(context, itemId: item.id!);
        }
      },
      child: Container(
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
                color: const Color(0xFFF3E8FF),
                child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, st) => Icon(
                          item.iconData,
                          color: AppColors.primaryColor,
                          size: 32,
                        ),
                      )
                    : Icon(
                        item.iconData,
                        color: AppColors.primaryColor,
                        size: 32,
                      ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                        if (item.price > 0) ...[
                          const SizedBox(width: 8),
                          _ActionChip(
                            icon: Icons.monetization_on_outlined,
                            label: '${item.price.toInt()} ฿/วัน',
                          ),
                        ],
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            if (item.id != null) {
                              AppRoutes.openItemDetail(context,
                                  itemId: item.id!);
                            }
                          },
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: AppColors.hintTextColor,
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

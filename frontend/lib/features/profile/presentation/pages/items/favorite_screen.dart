import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/services/favorite_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../widgets/items/favorite_widgets.dart';

class FavoriteScreen extends StatefulWidget {
  const FavoriteScreen({super.key});

  @override
  State<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends State<FavoriteScreen> {
  bool _isLoading = true;
  List<FavoriteItemData> _items = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    FavoriteService.instance.favoritesNotifier.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    FavoriteService.instance.favoritesNotifier.removeListener(
      _onFavoritesChanged,
    );
    super.dispose();
  }

  void _onFavoritesChanged() {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favIds = await FavoriteService.instance.getFavoriteIds();

    if (favIds.isEmpty) {
      if (mounted) {
        setState(() {
          _items = [];
          _isLoading = false;
        });
      }
      return;
    }

    if (!SupabaseConfig.isInitialized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final client = SupabaseConfig.client;

      // 1. ดึงข้อมูลอุปกรณ์ที่กดถูกใจจาก Supabase
      final response = await client
          .from('item_tb')
          .select(
            'id, user_id, item_name, item_image_url, description, category, price, status',
          )
          .inFilter('id', favIds);

      final List<FavoriteItemData> loaded = [];
      final Set<String> ownerIds = {};

      for (final raw in (response as List)) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = (map['id'] as num).toInt();
        final title = map['item_name']?.toString() ?? 'อุปกรณ์';
        final ownerId = map['user_id']?.toString() ?? '';
        final price = (map['price'] as num?)?.toDouble() ?? 0.0;
        final imageUrl = _extractFirstImageUrl(map['item_image_url']);
        final category = map['category']?.toString() ?? '';

        if (ownerId.isNotEmpty) ownerIds.add(ownerId);

        loaded.add(
          FavoriteItemData(
            id: id,
            title: title,
            ownerId: ownerId,
            ownerName: 'เจ้าของอุปกรณ์',
            imageUrl: imageUrl,
            price: price,
            category: category,
          ),
        );
      }

      // 2. ดึงชื่อเจ้าของจาก profile_tb
      if (ownerIds.isNotEmpty) {
        try {
          final profiles = await client
              .from('profile_tb')
              .select('user_id, email, user_image_url')
              .inFilter('user_id', ownerIds.toList());

          final Map<String, String> nameMap = {};
          for (final p in (profiles as List)) {
            if (p is Map) {
              final uid = p['user_id']?.toString();
              final email = p['email']?.toString() ?? '';
              if (uid != null) {
                final display = email.isNotEmpty
                    ? email.split('@').first
                    : 'เจ้าของอุปกรณ์';
                nameMap[uid] = display;
              }
            }
          }

          for (final item in loaded) {
            if (nameMap.containsKey(item.ownerId)) {
              item.ownerName = nameMap[item.ownerId]!;
            }
          }
        } catch (_) {}
      }

      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'อุปกรณ์เช่าที่ถูกใจ',
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
          ? const FavoriteLoadingSkeleton()
          : _items.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: _loadFavorites,
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return FavoriteItemCard(
                    item: item,
                    onRemoveFavorite: () async {
                      await FavoriteService.instance.toggleFavorite(item.id);
                    },
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                color: AppColors.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ยังไม่มีอุปกรณ์เช่าที่ถูกใจ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'กดไอคอนหัวใจที่อุปกรณ์ที่คุณสนใจเพื่อบันทึกไว้ดูภายหลังในหน้านี้',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: AppColors.hintTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'ค้นหาอุปกรณ์เช่า',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

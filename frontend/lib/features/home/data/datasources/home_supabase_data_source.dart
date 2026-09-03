import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/supabase_client.dart';
import '../models/feed_category_model.dart';
import '../models/feed_item_model.dart';
import 'home_mock_data_source.dart';

/// Data Source สำหรับดึงข้อมูลอุปกรณ์จริงผ่าน Go Backend REST API (`/api/v1/items`)
class HomeSupabaseDataSource {
  HomeSupabaseDataSource({
    SupabaseClient? client,
    ApiClient? apiClient,
    HomeMockDataSource? fallbackDataSource,
  })  : _client = client,
        _apiClient = apiClient ?? DioApiClient(),
        _fallbackDataSource = fallbackDataSource ?? HomeMockDataSource();

  final SupabaseClient? _client;
  final ApiClient _apiClient;
  final HomeMockDataSource _fallbackDataSource;
  final Set<String> _favoriteItemIds = {};

  SupabaseClient? get client {
    if (_client != null) return _client;
    if (SupabaseConfig.isInitialized) {
      try {
        return SupabaseConfig.client;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// ดึงหมวดหมู่มาตรฐาน 11 หมวดหมู่
  Future<List<FeedCategoryModel>> fetchCategories() async {
    return _fallbackDataSource.fetchCategories();
  }

  /// แปลงชื่อหมวดหมู่จากฐานข้อมูล Supabase เป็น categoryId มาตรฐานของ UI
  static String mapDbCategoryToId(String? rawCategory) {
    if (rawCategory == null || rawCategory.trim().isEmpty) return 'other';
    final cat = rawCategory.trim().toLowerCase();

    if (cat.contains('กล้อง') ||
        cat.contains('โดรน') ||
        cat.contains('เลนส์') ||
        cat.contains('ไฟและแสง') ||
        cat.contains('โปรเจคเตอร์') ||
        cat.contains('camera')) {
      return 'camera';
    }
    if (cat.contains('เครื่องเสียง') ||
        cat.contains('จัดงาน') ||
        cat.contains('ไมโครโฟน') ||
        cat.contains('ลำโพง') ||
        cat.contains('ผลิตไฟฟ้า') ||
        cat.contains('audio')) {
      return 'audio';
    }
    if (cat.contains('คอมพิวเตอร์') ||
        cat.contains('โน้ตบุ๊ก') ||
        cat.contains('laptop') ||
        cat.contains('macbook') ||
        cat.contains('computer')) {
      return 'computer';
    }
    if (cat.contains('โทรศัพท์') ||
        cat.contains('มือถือ') ||
        cat.contains('iphone') ||
        cat.contains('samsung') ||
        cat.contains('phone')) {
      return 'phone';
    }
    if (cat.contains('เครื่องมือช่าง') ||
        cat.contains('สว่าน') ||
        cat.contains('ทำความสะอาด') ||
        cat.contains('tools')) {
      return 'tools';
    }
    if (cat.contains('เครื่องใช้ไฟฟ้า') || cat.contains('appliances')) {
      return 'appliances';
    }
    if (cat.contains('แคมป์') ||
        cat.contains('เต็นท์') ||
        cat.contains('กลางแจ้ง') ||
        cat.contains('camping')) {
      return 'camping';
    }
    if (cat.contains('กีฬา') ||
        cat.contains('จักรยาน') ||
        cat.contains('ฟิตเนส') ||
        cat.contains('sports')) {
      return 'sports';
    }
    if (cat.contains('เกม') ||
        cat.contains('playstation') ||
        cat.contains('ps5') ||
        cat.contains('nintendo') ||
        cat.contains('บัตรเข้าชม') ||
        cat.contains('gaming')) {
      return 'gaming';
    }
    if (cat.contains('ดนตรี') ||
        cat.contains('กีตาร์') ||
        cat.contains('เปียโน') ||
        cat.contains('music')) {
      return 'music';
    }

    return 'other';
  }

  /// รูปภาพสำรองคุณภาพสูงตามหมวดหมู่ สำหรับอุปกรณ์ที่ไม่มีรูปภาพในระบบ
  static String getFallbackImageForCategory(String categoryId, int index) {
    final imageMap = <String, List<String>>{
      'camera': [
        'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1502920917128-1aa500764cbd?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1526170375885-4d8ecf77b99f?q=80&w=600&auto=format&fit=crop',
      ],
      'audio': [
        'https://images.unsplash.com/photo-1545454675-3531b543be5d?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?q=80&w=600&auto=format&fit=crop',
      ],
      'computer': [
        'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1603302576837-37561b2e2302?q=80&w=600&auto=format&fit=crop',
      ],
      'phone': [
        'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1580910051074-3eb694886505?q=80&w=600&auto=format&fit=crop',
      ],
      'tools': [
        'https://images.unsplash.com/photo-1504148455328-c376907d081c?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1581244277943-fe4a9c777189?q=80&w=600&auto=format&fit=crop',
      ],
      'appliances': [
        'https://images.unsplash.com/photo-1583863788434-e58a36330cf0?q=80&w=600&auto=format&fit=crop',
      ],
      'camping': [
        'https://images.unsplash.com/photo-1510312305653-8ed496efae75?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1504280390367-361c6d9f38f4?q=80&w=600&auto=format&fit=crop',
      ],
      'sports': [
        'https://images.unsplash.com/photo-1485965120184-e220f721d03e?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1517649763962-0c623266ddc0?q=80&w=600&auto=format&fit=crop',
      ],
      'gaming': [
        'https://images.unsplash.com/photo-1606813907291-d86efa9b94db?q=80&w=600&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1550745165-9bc0b252726f?q=80&w=600&auto=format&fit=crop',
      ],
      'music': [
        'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?q=80&w=600&auto=format&fit=crop',
      ],
      'other': [
        'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?q=80&w=600&auto=format&fit=crop',
      ],
    };

    final list = imageMap[categoryId] ?? imageMap['other']!;
    return list[index % list.length];
  }

  /// ดึงข้อมูลทั้งหมดผ่าน Go Backend API (`/api/v1/items`) และแปลงเป็น `List<FeedItemModel>`
  Future<List<FeedItemModel>> _fetchAllSupabaseItems() async {
    try {
      final response = await _apiClient.get('/api/v1/items');
      if (response.statusCode == 200 && response.data is List) {
        final rawItems = response.data as List;
        if (rawItems.isNotEmpty) {
          final List<FeedItemModel> items = [];
          for (int i = 0; i < rawItems.length; i++) {
            final item = rawItems[i] is Map<String, dynamic>
                ? rawItems[i] as Map<String, dynamic>
                : Map<String, dynamic>.from(rawItems[i] as Map);
            final id = item['id'].toString();
            final title = item['item_name']?.toString() ?? 'อุปกรณ์ให้เช่า';
            final description = item['description']?.toString() ?? '';
            final rawCategory = item['category']?.toString();
            final categoryId = mapDbCategoryToId(rawCategory);
            final price = (item['price'] is num)
                ? (item['price'] as num).toInt()
                : int.tryParse(item['price']?.toString() ?? '0') ?? 0;
            final type = item['type']?.toString();
            final priceUnit = (type == 'รายชั่วโมง') ? '/ ชม.' : '/ วัน';

            // จัดการรูปภาพ (ดึงจาก item_image_url ถ้าไม่มีให้ปล่อยว่างเพื่อแสดง no picture icon)
            String imageUrl = '';
            if (item['item_image_url'] is List &&
                (item['item_image_url'] as List).isNotEmpty) {
              final firstImg =
                  (item['item_image_url'] as List).first?.toString();
              if (firstImg != null && firstImg.trim().isNotEmpty) {
                imageUrl = firstImg.trim();
              }
            }

            final ownerName = item['owner_name']?.toString().trim().isNotEmpty == true
                ? item['owner_name'].toString().trim()
                : 'Yuemnoi Verified';
            final ownerAvatar = item['owner_avatar_url']?.toString();
            const locationName = 'กรุงเทพฯ';

            // ดึงแท็กจากคำอธิบาย
            List<String> tags = [];
            if (rawCategory != null && rawCategory.isNotEmpty) {
              tags.add(rawCategory);
            }
            if (description.isNotEmpty) {
              final words = description
                  .split(RegExp(r'[,\s]+'))
                  .where((w) => w.length >= 3 && w.length <= 15)
                  .take(2)
                  .toList();
              tags.addAll(words);
            }

            final rating = 4.7 + ((i % 4) * 0.1);
            final reviewCount = 8 + (i * 3);
            final distanceKm = 0.8 + ((i % 6) * 0.6);

            items.add(
              FeedItemModel(
                id: id,
                title: title,
                categoryId: categoryId,
                price: price,
                priceUnit: priceUnit,
                rating: double.parse(rating.toStringAsFixed(1)),
                reviewCount: reviewCount,
                distanceKm: double.parse(distanceKm.toStringAsFixed(1)),
                isVerified: true,
                ownerName: ownerName,
                ownerAvatarUrl: ownerAvatar,
                imageUrl: imageUrl,
                isCurated: i < 4,
                isFavorite: _favoriteItemIds.contains(id),
                tags: tags,
                locationName: locationName,
              ),
            );
          }

          return items;
        }
        return const [];
      }
      throw const FormatException('ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาลองใหม่');
    } catch (_) {
      throw const FormatException('ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาลองใหม่');
    }
  }

  /// ดึงรายการแนะนำพิเศษ (Curated Daily) จาก Supabase
  Future<List<FeedItemModel>> fetchCuratedItems() async {
    final allItems = await _fetchAllSupabaseItems();
    final curated = allItems.where((i) => i.isCurated).toList();
    if (curated.isEmpty && allItems.isNotEmpty) {
      return allItems.take(4).toList();
    }
    return curated;
  }

  /// ดึงรายการอุปกรณ์ใกล้เคียงจาก Supabase พร้อมตัวกรองหมวดหมู่, คำค้นหา, ราคา, คะแนนรีวิว
  Future<List<FeedItemModel>> fetchNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async {
    var items = await _fetchAllSupabaseItems();

    if (categoryId != null && categoryId.isNotEmpty && categoryId != 'all') {
      items = items.where((item) => item.categoryId == categoryId).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = searchQuery.trim().toLowerCase();
      items = items.where((item) {
        final matchesTitle = item.title.toLowerCase().contains(query);
        final matchesCategory = item.categoryId.toLowerCase().contains(query);
        final matchesTags =
            item.tags.any((t) => t.toLowerCase().contains(query));
        final matchesLocation =
            item.locationName.toLowerCase().contains(query);
        final matchesOwner = item.ownerName.toLowerCase().contains(query);
        return matchesTitle ||
            matchesCategory ||
            matchesTags ||
            matchesLocation ||
            matchesOwner;
      }).toList();
    }

    if (minPrice != null) {
      items = items.where((item) => item.price >= minPrice).toList();
    }

    if (maxPrice != null) {
      items = items.where((item) => item.price <= maxPrice).toList();
    }

    if (minRating != null) {
      items = items.where((item) => item.rating >= minRating).toList();
    }

    return items;
  }

  /// สลับสถานะรายการโปรด
  Future<bool> toggleFavorite(String itemId) async {
    if (_favoriteItemIds.contains(itemId)) {
      _favoriteItemIds.remove(itemId);
      return false;
    } else {
      _favoriteItemIds.add(itemId);
      return true;
    }
  }
}

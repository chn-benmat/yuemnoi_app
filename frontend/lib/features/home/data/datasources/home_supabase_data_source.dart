import '../../../../core/cache/app_cache.dart';
import '../../../../core/cache/cache_database.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/supabase_client.dart';
import '../models/feed_category_model.dart';
import '../models/feed_item_model.dart';
import 'home_mock_data_source.dart';

/// Data Source สำหรับดึงข้อมูลอุปกรณ์จริงจาก Supabase และ Go Backend REST API (`/api/items`)
/// พร้อม fallback ไปยัง Local Cache
class HomeSupabaseDataSource {
  HomeSupabaseDataSource({
    SupabaseClient? supabaseClient,
    ApiClient? apiClient,
    HomeMockDataSource? fallbackDataSource,
    CacheDatabase? cacheDatabase,
  }) : _cacheDatabase = cacheDatabase ?? AppCache.database,
       _supabaseClient = supabaseClient,
       _apiClient = apiClient ?? DioApiClient(),
       _fallbackDataSource = fallbackDataSource ?? HomeMockDataSource();

  final CacheDatabase _cacheDatabase;
  String get _cacheOwner =>
      _activeSupabaseClient?.auth.currentUser?.id ?? 'guest';

  final SupabaseClient? _supabaseClient;
  final ApiClient _apiClient;
  final HomeMockDataSource _fallbackDataSource;
  final Set<String> _favoriteItemIds = {};

  /// ชื่อหมวดหมู่ภาษาไทยที่เป็นทางการ
  static const Map<String, String> categoryThaiNames = {
    'camera': 'กล้องและอุปกรณ์ถ่ายภาพ',
    'audio': 'เครื่องเสียงและอุปกรณ์จัดงาน',
    'computer': 'คอมพิวเตอร์และอุปกรณ์ไอที',
    'phone': 'โทรศัพท์และอุปกรณ์สื่อสาร',
    'tools': 'เครื่องมือช่างและงานก่อสร้าง',
    'appliances': 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
    'camping': 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
    'sports': 'กีฬาและออกกำลังกาย',
    'gaming': 'เกมและความบันเทิง',
    'music': 'ดนตรีและเครื่องดนตรี',
    'other': 'อื่น ๆ',
  };

  /// คำค้นหายอดนิยมและคำพ้องความหมาย (Synonyms) ภาษาไทยและภาษาอังกฤษประจำหมวดหมู่
  static const Map<String, List<String>> categoryKeywords = {
    'camera': [
      'กล้อง',
      'โดรน',
      'เลนส์',
      'ถ่ายภาพ',
      'ถ่ายรูป',
      'ไฟสตูดิโอ',
      'โปรเจคเตอร์',
      'ขาตั้งกล้อง',
      'camera',
      'canon',
      'sony',
      'fuji',
      'nikon',
      'gopro',
      'dslr',
      'mirrorless',
      'แคนนอน',
      'โซนี่',
    ],
    'audio': [
      'เครื่องเสียง',
      'ลำโพง',
      'ไมค์',
      'ไมโครโฟน',
      'มิกเซอร์',
      'หูฟัง',
      'แอมป์',
      'audio',
      'sound',
      'speaker',
      'mic',
      'jbl',
      'shure',
      'yamaha',
      'ยามาฮ่า',
    ],
    'computer': [
      'คอม',
      'คอมพิวเตอร์',
      'โน้ตบุ๊ก',
      'โน้ตบุ๊ค',
      'แล็ปท็อป',
      'ไอที',
      'computer',
      'laptop',
      'macbook',
      'pc',
      'ipad',
      'tablet',
      'แมคบุ๊ก',
    ],
    'phone': [
      'โทรศัพท์',
      'มือถือ',
      'ไอโฟน',
      'ซัมซุง',
      'phone',
      'iphone',
      'samsung',
      'android',
      'smartphone',
    ],
    'tools': [
      'เครื่องมือช่าง',
      'ช่าง',
      'สว่าน',
      'เลื่อย',
      'ค้อน',
      'บันได',
      'เครื่องฉีดน้ำ',
      'ก่อสร้าง',
      'tools',
      'bosch',
      'makita',
      'บ๊อช',
    ],
    'appliances': [
      'เครื่องใช้ไฟฟ้า',
      'เครื่องดูดฝุ่น',
      'พัดลม',
      'หม้อทอด',
      'ตู้เย็น',
      'แอร์',
      'appliances',
      'dyson',
      'ไดสัน',
    ],
    'camping': [
      'แคมป์',
      'แคมป์ปิง',
      'เต็นท์',
      'เต้นท์',
      'เก้าอี้สนาม',
      'โต๊ะพับ',
      'ถุงนอน',
      'กระติก',
      'เดินป่า',
      'กลางแจ้ง',
      'camping',
      'coleman',
      'naturehike',
      'โคลแมน',
    ],
    'sports': [
      'กีฬา',
      'ออกกำลังกาย',
      'จักรยาน',
      'ซับบอร์ด',
      'ฟิตเนส',
      'sports',
      'bike',
      'bicycle',
      'trek',
      'sup board',
    ],
    'gaming': [
      'เกม',
      'เครื่องเล่นเกม',
      'บอร์ดเกม',
      'gaming',
      'game',
      'playstation',
      'ps5',
      'ps4',
      'nintendo',
      'switch',
      'xbox',
      'นินเทนโด',
    ],
    'music': [
      'ดนตรี',
      'เครื่องดนตรี',
      'กีตาร์',
      'กีต้าร์',
      'เบส',
      'คีย์บอร์ด',
      'เปียโน',
      'กลอง',
      'music',
      'guitar',
      'piano',
    ],
  };

  List<FeedItemModel>? _cachedFeedItems;
  DateTime? _lastFetchTime;
  String? _memoryOwner;

  void clearMemoryCache() {
    _cachedFeedItems = null;
    _lastFetchTime = null;
  }

  Future<void> _saveCachedItems(
    List<FeedItemModel> items,
    String ownerId,
  ) async {
    try {
      await _cacheDatabase.writeSnapshot(
        'home',
        'ranked_feed',
        ownerId,
        items.map((item) => item.toJson()).toList(),
      );
    } catch (_) {
      // ข้อมูลจาก server ยังใช้ได้ แม้ cache ในเครื่องเขียนไม่สำเร็จ
    }
  }

  Future<List<FeedItemModel>?> _loadCachedItems(String ownerId) async {
    try {
      final entries = await _cacheDatabase.readSnapshot(
        'home',
        'ranked_feed',
        ownerId,
      );
      return entries?.map(FeedItemModel.fromJson).toList();
    } catch (_) {
      return null;
    }
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

  List<FeedItemModel> _mapRawListToFeedItems(
    List rawItems, {
    Map<String, Map<String, dynamic>>? profilesMap,
  }) {
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
      final type = item['type']?.toString().toLowerCase().trim();
      final priceUnit =
          (type == 'รายชั่วโมง' || type == 'hourly' || type == 'hour')
          ? '/ ชม.'
          : '/ วัน';

      String imageUrl = '';
      if (item['item_image_url'] is List &&
          (item['item_image_url'] as List).isNotEmpty) {
        final firstImg = (item['item_image_url'] as List).first?.toString();
        if (firstImg != null && firstImg.trim().isNotEmpty) {
          imageUrl = firstImg.trim();
        }
      } else if (item['item_image_url'] is String &&
          (item['item_image_url'] as String).trim().isNotEmpty) {
        imageUrl = (item['item_image_url'] as String).trim();
      }

      var ownerName = item['owner_name']?.toString().trim();
      var ownerAvatar = item['owner_avatar_url']?.toString();

      if (ownerName == null || ownerName.isEmpty) {
        final profile = profilesMap?[item['user_id']?.toString()];
        final displayName = profile?['display_name']?.toString().trim() ?? '';
        final email = profile?['email']?.toString() ?? '';
        if (displayName.isNotEmpty) {
          ownerName = displayName;
        } else if (email.contains('@')) {
          ownerName = email.split('@').first;
        } else if (email.isNotEmpty) {
          ownerName = email;
        } else {
          ownerName = 'ผู้ใช้งาน';
        }
        ownerAvatar ??= profile?['user_image_url']?.toString();
      }

      const locationName = 'กรุงเทพฯ';

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

      final rating = item['rating'] is num
          ? (item['rating'] as num).toDouble()
          : double.tryParse(item['rating']?.toString() ?? '') ?? 0;
      final reviewCount = item['review_count'] is num
          ? (item['review_count'] as num).toInt()
          : int.tryParse(item['review_count']?.toString() ?? '') ?? 0;
      final distanceKm = 0.8 + ((i % 6) * 0.6);

      items.add(
        FeedItemModel(
          id: id,
          title: title,
          description: description,
          categoryId: categoryId,
          rawCategory: rawCategory ?? '',
          price: price,
          priceUnit: priceUnit,
          rating: double.parse(rating.toStringAsFixed(1)),
          reviewCount: reviewCount,
          distanceKm: double.parse(distanceKm.toStringAsFixed(1)),
          isVerified:
              item['is_verified'] == true ||
              profilesMap?[item['user_id']?.toString()]?['is_verified'] == true,
          ownerName: ownerName.isEmpty ? 'ผู้ใช้งาน' : ownerName,
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

  SupabaseClient? get _activeSupabaseClient {
    if (_supabaseClient != null) return _supabaseClient;
    if (SupabaseConfig.isInitialized) return SupabaseConfig.client;
    return null;
  }

  /// ดึงข้อมูลรายการอุปกรณ์จริงจาก Supabase โดยตรง (Tier 1)
  Future<List<FeedItemModel>> _fetchFromSupabaseDirectly() async {
    final client = _activeSupabaseClient;
    if (client == null) {
      throw const FormatException('Supabase client is not available');
    }

    List<dynamic>? rawItems;
    try {
      rawItems = await client
          .from('home_feed_ranked_v')
          .select('*')
          .order('rank_position', ascending: true);
    } catch (e) {
      debugPrint(
        'Direct Supabase home_feed_ranked_v error: $e, fallback to item_tb',
      );
    }

    if (rawItems == null || rawItems.isEmpty) {
      try {
        rawItems = await client
            .from('item_tb')
            .select('*')
            .inFilter('status', ['available', 'พร้อมใช้งาน'])
            .order('created_at', ascending: false);
      } catch (e) {
        debugPrint('Direct Supabase item_tb fallback error: $e');
      }
    }

    if (rawItems == null) {
      throw const FormatException('อ่านข้อมูล Supabase ไม่สำเร็จ');
    }
    if (rawItems.isEmpty) return const [];

    final rawList = rawItems;
    final userIds = rawList
        .map((r) => (r as Map)['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    Map<String, Map<String, dynamic>> profilesMap = {};
    if (userIds.isNotEmpty) {
      try {
        final List<dynamic> profiles = await client
            .from('public_profile_v')
            .select('user_id, display_name, user_image_url, is_verified')
            .inFilter('user_id', userIds);
        for (final p in profiles) {
          final uid = (p as Map)['user_id']?.toString();
          if (uid != null) {
            profilesMap[uid] = Map<String, dynamic>.from(p);
          }
        }
      } catch (e) {
        debugPrint('Profiles query error for home items: $e');
      }
    }

    return _mapRawListToFeedItems(rawList, profilesMap: profilesMap);
  }

  /// ดึงข้อมูลทั้งหมดผ่าน Supabase Direct, Go Backend API (`/api/items`) หรือ Local Cache
  Future<List<FeedItemModel>> _fetchAllSupabaseItems({
    bool forceRefresh = false,
  }) async {
    final ownerId = _cacheOwner;
    if (_memoryOwner != ownerId) {
      clearMemoryCache();
      _favoriteItemIds.clear();
      _memoryOwner = ownerId;
    }
    if (!forceRefresh &&
        _cachedFeedItems != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inSeconds < 15) {
      return _cachedFeedItems!;
    }

    List<FeedItemModel>? freshItems;
    if (_activeSupabaseClient != null) {
      try {
        freshItems = await _fetchFromSupabaseDirectly();
      } catch (_) {
        // ลอง Go API ต่อเมื่อการอ่าน Supabase ล้มเหลวเท่านั้น
      }
    }
    if (ownerId != _cacheOwner)
      return _fetchAllSupabaseItems(forceRefresh: true);
    if (freshItems == null) {
      try {
        final response = await _apiClient.get('/api/items');
        if (response.statusCode == 200 && response.data is List) {
          freshItems = _mapRawListToFeedItems(response.data as List);
        }
      } catch (_) {
        // Cache เป็น fallback เมื่อบริการภายนอกติดต่อไม่ได้
      }
    }
    if (ownerId != _cacheOwner)
      return _fetchAllSupabaseItems(forceRefresh: true);
    if (freshItems != null) {
      _cachedFeedItems = freshItems;
      _lastFetchTime = DateTime.now();
      await _saveCachedItems(freshItems, ownerId);
      if (ownerId != _cacheOwner)
        return _fetchAllSupabaseItems(forceRefresh: true);
      return freshItems;
    }
    final cached = await _loadCachedItems(ownerId);
    if (ownerId != _cacheOwner)
      return _fetchAllSupabaseItems(forceRefresh: true);
    if (cached != null) {
      _cachedFeedItems = cached;
      return cached;
    }
    final fallbackItems = await _fallbackDataSource.fetchNearbyItems();
    if (fallbackItems.isNotEmpty) return fallbackItems;
    throw const FormatException(
      'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาลองใหม่',
    );
  }

  Future<List<FeedItemModel>> fetchCuratedItems() async {
    final allItems = await _fetchAllSupabaseItems();
    final curated = allItems.where((i) => i.isCurated).toList();
    if (curated.isEmpty && allItems.isNotEmpty) {
      return allItems.take(4).toList();
    }
    return curated;
  }

  /// ตรวจสอบว่าอุปกรณ์ตรงกับคำค้นหาหรือไม่ (รองรับภาษาไทย, ชื่ออุปกรณ์, คำอธิบาย, หมวดหมู่ และคำพ้อง)
  bool _matchesItem(
    FeedItemModel item,
    String fullQuery,
    List<String> keywords,
  ) {
    final title = item.title.toLowerCase();
    final description = item.description.toLowerCase();
    final catId = item.categoryId.toLowerCase();
    final rawCat = item.rawCategory.toLowerCase();
    final thaiCat = categoryThaiNames[item.categoryId]?.toLowerCase() ?? '';
    final location = item.locationName.toLowerCase();
    final owner = item.ownerName.toLowerCase();
    final tags = item.tags.map((t) => t.toLowerCase()).toList();
    final synonyms = categoryKeywords[item.categoryId] ?? const [];

    bool tokenMatches(String token) {
      if (title.contains(token)) return true;
      if (description.contains(token)) return true;
      if (rawCat.contains(token)) return true;
      if (thaiCat.contains(token)) return true;
      if (catId.contains(token)) return true;
      if (location.contains(token)) return true;
      if (owner.contains(token)) return true;
      if (tags.any((t) => t.contains(token))) return true;
      if (synonyms.any((syn) => syn.contains(token) || token.contains(syn))) {
        return true;
      }
      return false;
    }

    // 1. ถ้าคำค้นหาแบบเต็มตรงกับข้อมูลใดๆ
    if (tokenMatches(fullQuery)) return true;

    // 2. ถ้าเป็นคำค้นหลายคำ (แยกด้วยช่องว่าง) ทุกคำต้องตรงกับข้อมูลของอุปกรณ์
    if (keywords.length > 1) {
      return keywords.every(tokenMatches);
    }

    return false;
  }

  /// ดึงรายการอุปกรณ์ใกล้เคียงจาก Supabase / Backend พร้อมตัวกรองหมวดหมู่, คำค้นหา, ราคา, คะแนนรีวิว
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
      final rawQuery = searchQuery.trim().toLowerCase();
      final keywords = rawQuery
          .split(RegExp(r'\s+'))
          .where((k) => k.isNotEmpty)
          .toList();

      items = items.where((item) {
        return _matchesItem(item, rawQuery, keywords);
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

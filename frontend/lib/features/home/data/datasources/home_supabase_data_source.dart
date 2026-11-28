import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/cache/app_cache.dart';
import '../../../../core/cache/cache_database.dart';
import '../../../../core/models/rental_rates.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/favorite_service.dart';
import '../../domain/repositories/home_repository.dart';
import '../models/feed_category_model.dart';
import '../models/feed_item_model.dart';

/// ดึงฟีดจัดอันดับจาก Go และใช้แค็ตตาล็อกเดิมสำหรับค้นหาหรือโหลดสำรอง
/// ใช้แคชจากข้อมูลจริงของฟีดเมื่อโหลดข้อมูลสดไม่ได้
class HomeSupabaseDataSource {
  HomeSupabaseDataSource({
    SupabaseClient? supabaseClient,
    ApiClient? apiClient,
    CacheDatabase? cacheDatabase,
  }) : _cacheDatabase = cacheDatabase ?? AppCache.database,
       _supabaseClient = supabaseClient,
       _apiClient = apiClient ?? DioApiClient();

  final CacheDatabase _cacheDatabase;
  String get _cacheOwner =>
      _activeSupabaseClient?.auth.currentUser?.id ?? 'guest';

  final SupabaseClient? _supabaseClient;
  final ApiClient _apiClient;

  Future<({List<FeedItemModel> items, String? nextCursor})?> fetchRankedItems({
    double? latitude,
    double? longitude,
    List<String> recentCategories = const [],
    String? cursor,
  }) async {
    final userId = AuthSession.userId;
    final token = AuthSession.accessToken;
    if (userId != AuthSession.accountChanges.value.userId) return null;
    try {
      final response = await _apiClient.post(
        '/api/home/feed',
        data: {
          if (latitude != null && longitude != null) ...{
            'latitude': latitude,
            'longitude': longitude,
          },
          if (recentCategories.isNotEmpty)
            'recent_categories': recentCategories,
          'cursor': ?cursor,
        },
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
      );
      if (cursor != null && response.statusCode == 400) {
        throw const RankedHomeCursorInvalid();
      }
      if (response.statusCode != 200 || response.data is! Map) return null;
      final rawItems = (response.data as Map)['items'];
      final nextCursor = (response.data as Map)['next_cursor'];
      if (rawItems is! List || (nextCursor != null && nextCursor is! String)) {
        return null;
      }
      if (userId != AuthSession.userId) return null;
      await FavoriteService.instance.init();
      if (userId != AuthSession.userId) return null;
      final items = _mapRawListToFeedItems(
        rawItems,
        isRanked: true,
        userId: userId,
      );
      return (
        items: items,
        nextCursor: nextCursor is String && nextCursor.isNotEmpty
            ? nextCursor
            : null,
      );
    } on ApiClientException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static final _feedChangesByClient = Expando<Stream<void>>();

  Stream<void> watchFeedChanges() {
    final client = _activeSupabaseClient;
    if (client == null) return const Stream.empty();

    // ใช้ช่องเดียวต่อ client แม้หน้าหลักทั้งเก่าและใหม่จะยังเปิดอยู่
    return _feedChangesByClient[client] ??= _watchFeedChanges(client);
  }

  static Stream<void> _watchFeedChanges(SupabaseClient client) {
    RealtimeChannel? channel;
    late StreamSubscription<AuthState> authChanges;
    late final StreamController<void> changes;

    void leaveChannel() {
      final subscription = channel;
      channel = null;
      if (subscription != null) unawaited(client.removeChannel(subscription));
    }

    void joinChannel() {
      final subscription = client.channel(
        'home_feed',
        opts: const RealtimeChannelConfig(private: true),
      );
      channel = subscription;

      void notifyChanged() {
        if (channel == subscription) changes.add(null);
      }

      subscription
          .onBroadcast(event: 'feed_changed', callback: (_) => notifyChanged())
          .subscribe((status, _) {
            // ดึงข้อมูลหลังเชื่อมต่อเพื่อเก็บการเปลี่ยนแปลงที่เกิดระหว่างหลุด
            if (status == RealtimeSubscribeStatus.subscribed) notifyChanged();
          });
    }

    changes = StreamController<void>.broadcast(
      onListen: () {
        authChanges = client.auth.onAuthStateChange.listen((event) {
          if (event.event == AuthChangeEvent.signedOut) {
            // เข้าช่องใหม่ด้วยสิทธิ์ผู้เยี่ยมชมหลังออกจากระบบ
            leaveChannel();
            joinChannel();
          }
        }, onError: (Object _) {});
        joinChannel();
      },
      onCancel: () {
        unawaited(authChanges.cancel());
        leaveChannel();
      },
    );
    return changes.stream;
  }

  static const _categories = [
    FeedCategoryModel(id: 'all', name: 'ทั้งหมด', iconName: 'apps'),
    FeedCategoryModel(
      id: 'camera',
      name: 'กล้องและอุปกรณ์ถ่ายภาพ',
      iconName: 'photo_camera',
    ),
    FeedCategoryModel(
      id: 'audio',
      name: 'เครื่องเสียงและอุปกรณ์จัดงาน',
      iconName: 'headphones',
    ),
    FeedCategoryModel(
      id: 'computer',
      name: 'คอมพิวเตอร์และอุปกรณ์ไอที',
      iconName: 'laptop',
    ),
    FeedCategoryModel(
      id: 'phone',
      name: 'โทรศัพท์และอุปกรณ์สื่อสาร',
      iconName: 'smartphone',
    ),
    FeedCategoryModel(
      id: 'tools',
      name: 'เครื่องมือช่างและงานก่อสร้าง',
      iconName: 'construction',
    ),
    FeedCategoryModel(
      id: 'appliances',
      name: 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
      iconName: 'kitchen',
    ),
    FeedCategoryModel(
      id: 'camping',
      name: 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
      iconName: 'forest',
    ),
    FeedCategoryModel(
      id: 'sports',
      name: 'กีฬาและออกกำลังกาย',
      iconName: 'fitness_center',
    ),
    FeedCategoryModel(
      id: 'gaming',
      name: 'เกมและความบันเทิง',
      iconName: 'sports_esports',
    ),
    FeedCategoryModel(
      id: 'music',
      name: 'ดนตรีและเครื่องดนตรี',
      iconName: 'music_note',
    ),
    FeedCategoryModel(id: 'other', name: 'อื่น ๆ', iconName: 'category'),
  ];

  static final Map<String, String> _categoryNames = {
    for (final category in _categories) category.id: category.name,
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
  bool _preserveFeaturedItems = false;
  Set<String> _deferPreviouslyShownIds = {};
  static const int _curatedItemCount = 4;
  static const int _recentRecommendationWindow = 12;
  static const int _catalogPageSize = 100;
  static const int _enrichmentBatchSize = 100;
  static const _listingColumns =
      'id,user_id,item_name,item_image_url,description,category,price,type,'
      'hourly_rate,daily_rate,pickup_location,is_rental_occupied';
  static const _rankedListingColumns =
      '$_listingColumns,rating,review_count,paid_booking_count';
  static const _itemListingColumns =
      '$_listingColumns,pickup_latitude,pickup_longitude';

  String _recentItemsKey(String ownerId) =>
      'home_recent_recommendations_$ownerId';

  void clearMemoryCache({bool rotateRecommendations = true}) {
    _lastFetchTime = null;
    _preserveFeaturedItems = !rotateRecommendations;
    if (!rotateRecommendations) return;

    final cachedItems = _cachedFeedItems;
    if (cachedItems != null) {
      _deferPreviouslyShownIds = cachedItems
          .take(_curatedItemCount)
          .map((item) => item.id)
          .toSet();
    }
    _cachedFeedItems = null;
  }

  List<FeedItemModel> _keepFeaturedItems(
    List<FeedItemModel> items,
    List<FeedItemModel> previousItems,
  ) {
    final remaining = {for (final item in items) item.id: item};
    final ordered = [
      for (final item in previousItems.take(_curatedItemCount))
        ?remaining.remove(item.id),
      ...remaining.values,
    ];
    return [
      for (var index = 0; index < ordered.length; index++)
        ordered[index].copyWith(isCurated: index < _curatedItemCount),
    ];
  }

  Future<List<FeedItemModel>> _rotateRecentlyShownItems(
    List<FeedItemModel> items,
    String ownerId,
  ) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Keep the feed available even if local preference storage is unavailable.
    }
    final persistedHistory =
        prefs?.getStringList(_recentItemsKey(ownerId)) ?? const <String>[];
    final history = _deferPreviouslyShownIds.isNotEmpty
        ? [..._deferPreviouslyShownIds, ...persistedHistory]
        : persistedHistory;
    final deferredIds = history.toSet();
    final availableById = {for (final item in items) item.id: item};
    final unseenItems = items
        .where((item) => !deferredIds.contains(item.id))
        .toList();
    final featured = <FeedItemModel>[...unseenItems.take(_curatedItemCount)];
    // If the candidate pool is smaller than the recent-history window, cycle
    // from the least recently featured items instead of repeating its first row.
    final repeatOrder = unseenItems.isEmpty ? history.reversed : history;
    for (final id in repeatOrder) {
      final item = availableById[id];
      if (featured.length >= _curatedItemCount) break;
      if (item != null && !featured.any((current) => current.id == id)) {
        featured.add(item);
      }
    }
    final featuredIds = featured.map((item) => item.id).toSet();
    final rotated = <FeedItemModel>[
      ...featured,
      ...items.where((item) => !featuredIds.contains(item.id)),
    ];
    _deferPreviouslyShownIds = {};
    final diversified = [
      for (var index = 0; index < rotated.length; index++)
        rotated[index].copyWith(isCurated: index < _curatedItemCount),
    ];
    try {
      final updatedHistory = <String>[
        ...diversified.take(_curatedItemCount).map((item) => item.id),
        ...history,
      ].toSet().take(_recentRecommendationWindow).toList();
      await prefs?.setStringList(_recentItemsKey(ownerId), updatedHistory);
    } catch (_) {
      // Rotation still works for this app session without persistent storage.
    }
    return diversified;
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
  Future<List<FeedCategoryModel>> fetchCategories() async => _categories;

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
    Map<String, Map<String, dynamic>>? pickupDetails,
    bool isRanked = false,
    String? userId,
  }) {
    final List<FeedItemModel> items = [];
    final currentUserId = isRanked
        ? userId
        : _activeSupabaseClient?.auth.currentUser?.id;
    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i] is Map<String, dynamic>
          ? rawItems[i] as Map<String, dynamic>
          : Map<String, dynamic>.from(rawItems[i] as Map);
      final id = item['id'].toString();
      if (isRanked && (item['id'] == null || id.isEmpty)) {
        throw const FormatException('ไม่มีรหัสอุปกรณ์ในฟีด');
      }
      final title = item['item_name']?.toString() ?? 'อุปกรณ์ให้เช่า';
      final description = item['description']?.toString() ?? '';
      final rawCategory = item['category']?.toString();
      final categoryId = mapDbCategoryToId(rawCategory);
      // การ์ดแสดงเรตหลัก: รายชั่วโมงถ้ามี ไม่งั้นรายวัน
      final rates =
          RentalRates.fromKeys(
            item,
            hourlyKey: 'hourly_rate',
            dailyKey: 'daily_rate',
          ) ??
          RentalRates.legacy(
            price: item['price'],
            type: item['type'],
            dailyPrice: item['daily_price'],
          );
      final price = rates.hourly ?? rates.daily ?? 0;
      final priceUnit = rates.hourly != null ? '/ ชม.' : '/ วัน';

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

      final pickup = pickupDetails?[id] ?? item;
      final rawLocationName = pickup['pickup_location']?.toString().trim();
      final locationName = rawLocationName == null || rawLocationName.isEmpty
          ? 'ไม่ระบุตำแหน่ง'
          : rawLocationName;

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
          paidBookingCount: int.tryParse('${item['paid_booking_count']}') ?? 0,
          isRentalOccupied: item['is_rental_occupied'] == true,
          distanceKm: isRanked
              ? double.tryParse('${item['distance_km']}')
              : null,
          isVerified:
              item['is_verified'] == true ||
              profilesMap?[item['user_id']?.toString()]?['is_verified'] == true,
          ownerName: ownerName.isEmpty ? 'ผู้ใช้งาน' : ownerName,
          isOwner:
              currentUserId != null &&
              item['user_id']?.toString() == currentUserId,
          ownerAvatarUrl: ownerAvatar,
          imageUrl: imageUrl,
          isCurated: !isRanked && i < _curatedItemCount,
          isFavorite: FavoriteService.instance.isItemFavorite(
            int.tryParse(id) ?? -1,
          ),
          tags: tags,
          locationName: locationName,
          pickupLatitude: double.tryParse('${pickup['pickup_latitude']}'),
          pickupLongitude: double.tryParse('${pickup['pickup_longitude']}'),
        ),
      );
    }
    return items;
  }

  List<FeedItemModel> _withCurrentFavoriteState(
    Iterable<FeedItemModel> items,
  ) => items
      .map(
        (item) => item.copyWith(
          isFavorite: FavoriteService.instance.isItemFavorite(
            int.tryParse(item.id) ?? -1,
          ),
        ),
      )
      .toList(growable: false);

  SupabaseClient? get _activeSupabaseClient {
    if (_supabaseClient != null) return _supabaseClient;
    if (SupabaseConfig.isInitialized) return SupabaseConfig.client;
    return null;
  }

  Future<PostgrestList> _readCatalogPages(
    PostgrestTransformBuilder<PostgrestList> query,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += _catalogPageSize) {
      final page = await query.range(offset, offset + _catalogPageSize - 1);
      rows.addAll(page);
      if (page.length < _catalogPageSize) return rows;
    }
  }

  /// ดึงข้อมูลรายการอุปกรณ์จริงจาก Supabase โดยตรง (Tier 1)
  Future<List<FeedItemModel>> _fetchFromSupabaseDirectly() async {
    final client = _activeSupabaseClient;
    if (client == null) {
      throw const FormatException('Supabase client is not available');
    }

    PostgrestList? rawItems;
    try {
      rawItems = await _readCatalogPages(
        client
            .from('home_feed_ranked_v')
            .select(_rankedListingColumns)
            .order('rank_position', ascending: true),
      );
    } catch (e) {
      debugPrint(
        'Direct Supabase home_feed_ranked_v error: $e, fallback to item_tb',
      );
    }

    if (rawItems == null || rawItems.isEmpty) {
      try {
        rawItems = await _readCatalogPages(
          client
              .from('item_tb')
              .select(_itemListingColumns)
              .eq('owner_hidden', false)
              .eq('moderation_hidden', false)
              .inFilter('status', ['available', 'พร้อมใช้งาน'])
              .order('created_at', ascending: false)
              .order('id', ascending: false),
        );
      } catch (e) {
        debugPrint('Direct Supabase item_tb fallback error: $e');
      }
    }

    if (rawItems == null) {
      throw const FormatException('อ่านข้อมูล Supabase ไม่สำเร็จ');
    }
    if (rawItems.isEmpty) return const [];

    final (profilesMap, pickupDetails) = await (
      _fetchProfiles(client, rawItems),
      _fetchPickupDetails(rawItems),
    ).wait;
    return _mapRawListToFeedItems(
      rawItems,
      profilesMap: profilesMap,
      pickupDetails: pickupDetails,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    SupabaseClient client,
    PostgrestList items,
  ) async {
    final userIds = items
        .map((row) => row['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final profilesMap = <String, Map<String, dynamic>>{};
    for (
      var offset = 0;
      offset < userIds.length;
      offset += _enrichmentBatchSize
    ) {
      try {
        final profiles = await client
            .schema('profiles')
            .from('public_profile_v')
            .select('user_id, display_name, user_image_url, is_verified')
            .inFilter(
              'user_id',
              userIds.skip(offset).take(_enrichmentBatchSize).toList(),
            );
        for (final profile in profiles) {
          final uid = profile['user_id']?.toString();
          if (uid != null) profilesMap[uid] = profile;
        }
      } catch (e) {
        debugPrint('Profiles query error for home items: $e');
        break;
      }
    }
    return profilesMap;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchPickupDetails(
    List<dynamic> items,
  ) async {
    final client = _activeSupabaseClient;
    if (client == null) return {};

    final ids = <int>{};
    for (final item in items.cast<Map>()) {
      if (item['pickup_latitude'] != null && item['pickup_longitude'] != null) {
        continue;
      }
      final id = int.tryParse('${item['id']}');
      if (id != null) ids.add(id);
    }

    final result = <String, Map<String, dynamic>>{};
    final listingIds = ids.toList();
    for (
      var offset = 0;
      offset < listingIds.length;
      offset += _enrichmentBatchSize
    ) {
      try {
        final rows = await client
            .from('item_tb')
            .select('id,pickup_location,pickup_latitude,pickup_longitude')
            .inFilter(
              'id',
              listingIds.skip(offset).take(_enrichmentBatchSize).toList(),
            )
            .eq('owner_hidden', false)
            .eq('moderation_hidden', false)
            .inFilter('status', ['available', 'พร้อมใช้งาน']);
        for (final row in rows) {
          result['${row['id']}'] = row;
        }
      } catch (_) {
        // ฟีดยังแสดงรายการได้เมื่ออ่านพิกัดจุดรับสินค้าไม่ได้
        break;
      }
    }
    return result;
  }

  /// ดึงรายการสดก่อน และใช้ cache เป็น fallback เฉพาะฟีดที่ไม่ได้ค้นหา
  Future<List<FeedItemModel>> _fetchAllSupabaseItems({
    bool forceRefresh = false,
    bool allowOfflineCache = true,
  }) async {
    final ownerId = _cacheOwner;
    if (_memoryOwner != ownerId) {
      _cachedFeedItems = null;
      _lastFetchTime = null;
      _deferPreviouslyShownIds = {};
      _memoryOwner = ownerId;
    }
    await FavoriteService.instance.init();

    if (allowOfflineCache &&
        !forceRefresh &&
        _cachedFeedItems != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inSeconds < 15) {
      return _withCurrentFavoriteState(_cachedFeedItems!);
    }

    List<FeedItemModel>? freshItems;
    if (_activeSupabaseClient != null) {
      try {
        freshItems = await _fetchFromSupabaseDirectly();
      } catch (_) {
        // ลอง Go API ต่อเมื่อการอ่าน Supabase ล้มเหลวเท่านั้น
      }
    }
    if (ownerId != _cacheOwner) {
      return _fetchAllSupabaseItems(
        forceRefresh: true,
        allowOfflineCache: allowOfflineCache,
      );
    }
    if (freshItems == null) {
      try {
        final response = await _apiClient.get('/api/items');
        if (response.statusCode == 200 && response.data is List) {
          final rawItems = response.data as List;
          freshItems = _mapRawListToFeedItems(
            rawItems,
            pickupDetails: await _fetchPickupDetails(rawItems),
          );
        }
      } catch (_) {
        // ลองแหล่งข้อมูลถัดไปและแจ้ง error หากเชื่อมต่อไม่ได้ทั้งหมด
      }
    }
    if (ownerId != _cacheOwner) {
      return _fetchAllSupabaseItems(
        forceRefresh: true,
        allowOfflineCache: allowOfflineCache,
      );
    }
    if (freshItems != null) {
      final previousItems = _cachedFeedItems;
      freshItems = _preserveFeaturedItems && previousItems != null
          ? _keepFeaturedItems(freshItems, previousItems)
          : await _rotateRecentlyShownItems(freshItems, ownerId);
      _cachedFeedItems = freshItems;
      _lastFetchTime = DateTime.now();
      await _saveCachedItems(freshItems, ownerId);
      if (ownerId != _cacheOwner) {
        return _fetchAllSupabaseItems(
          forceRefresh: true,
          allowOfflineCache: allowOfflineCache,
        );
      }
      return _withCurrentFavoriteState(freshItems);
    }

    if (allowOfflineCache) {
      final cachedItems = await _loadCachedItems(ownerId);
      if (ownerId != _cacheOwner) {
        return _fetchAllSupabaseItems(
          forceRefresh: true,
          allowOfflineCache: allowOfflineCache,
        );
      }
      if (cachedItems != null) {
        // ใช้ลำดับใน snapshot เมื่ออ่านข้อมูลสดไม่ได้
        _cachedFeedItems = cachedItems;
        _lastFetchTime = DateTime.now();
        return _withCurrentFavoriteState(cachedItems);
      }
    }

    throw const FormatException('ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาลองใหม่');
  }

  Future<List<FeedItemModel>> fetchCuratedItems() async {
    final allItems = await _fetchAllSupabaseItems();
    final curated = allItems.where((i) => i.isCurated).toList();
    return curated.isEmpty
        ? allItems.take(_curatedItemCount).toList()
        : curated;
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
    final thaiCat = _categoryNames[item.categoryId]?.toLowerCase() ?? '';
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
    final isSearching = searchQuery?.trim().isNotEmpty == true;
    var items = await _fetchAllSupabaseItems(
      forceRefresh: isSearching,
      allowOfflineCache: !isSearching,
    );

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
    final parsedId = int.tryParse(itemId);
    if (parsedId == null) {
      throw ArgumentError.value(itemId, 'itemId', 'ต้องเป็นรหัสตัวเลข');
    }
    return FavoriteService.instance.toggleFavorite(parsedId);
  }
}

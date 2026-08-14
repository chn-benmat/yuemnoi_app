import '../models/feed_category_model.dart';
import '../models/feed_item_model.dart';

/// แหล่งข้อมูลจำลองคุณภาพสูงสำหรับหน้า Home Feed
class HomeMockDataSource {
  HomeMockDataSource();

  static const List<FeedCategoryModel> defaultCategories = [
    FeedCategoryModel(id: 'all', name: 'ทั้งหมด', iconName: 'apps'),
    FeedCategoryModel(id: 'camera', name: 'กล้องและอุปกรณ์ถ่ายภาพ', iconName: 'photo_camera'),
    FeedCategoryModel(id: 'audio', name: 'เครื่องเสียงและอุปกรณ์จัดงาน', iconName: 'headphones'),
    FeedCategoryModel(id: 'computer', name: 'คอมพิวเตอร์และอุปกรณ์ไอที', iconName: 'laptop'),
    FeedCategoryModel(id: 'phone', name: 'โทรศัพท์และอุปกรณ์สื่อสาร', iconName: 'smartphone'),
    FeedCategoryModel(id: 'tools', name: 'เครื่องมือช่างและงานก่อสร้าง', iconName: 'construction'),
    FeedCategoryModel(id: 'appliances', name: 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน', iconName: 'kitchen'),
    FeedCategoryModel(id: 'camping', name: 'แคมป์ปิงและกิจกรรมกลางแจ้ง', iconName: 'forest'),
    FeedCategoryModel(id: 'sports', name: 'กีฬาและออกกำลังกาย', iconName: 'fitness_center'),
    FeedCategoryModel(id: 'gaming', name: 'เกมและความบันเทิง', iconName: 'sports_esports'),
    FeedCategoryModel(id: 'music', name: 'ดนตรีและเครื่องดนตรี', iconName: 'music_note'),
    FeedCategoryModel(id: 'other', name: 'อื่น ๆ', iconName: 'category'),
  ];

  static final List<FeedItemModel> defaultCuratedItems = [
    const FeedItemModel(
      id: 'curated-sony-a7-3',
      title: 'Sony Alpha A7\nIII',
      categoryId: 'camera',
      price: 1000,
      priceUnit: '/ วัน',
      rating: 4.9,
      reviewCount: 128,
      distanceKm: 1.2,
      isVerified: true,
      ownerName: 'Jessica',
      ownerAvatarUrl: 'assets/images/chat_sarah.png',
      imageUrl:
          'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?q=80&w=800&auto=format&fit=crop',
      isCurated: true,
      isFavorite: false,
      tags: ['กล้องฟูลเฟรม', '4K', 'อุปกรณ์ยอดนิยม'],
      locationName: 'สยาม • กรุงเทพฯ',
    ),
    const FeedItemModel(
      id: 'curated-specialized-bike',
      title: 'Specialized\nStumpjumper',
      categoryId: 'camping',
      price: 850,
      priceUnit: '/ วัน',
      rating: 4.8,
      reviewCount: 94,
      distanceKm: 2.5,
      isVerified: true,
      ownerName: 'Jessica',
      ownerAvatarUrl: 'assets/images/chat_sarah.png',
      imageUrl:
          'https://images.unsplash.com/photo-1485965120184-e220f721d03e?q=80&w=800&auto=format&fit=crop',
      isCurated: true,
      isFavorite: true,
      tags: ['จักรยานเสือภูเขา', 'Full Suspension', 'พร้อมลุย'],
      locationName: 'บางนา • กรุงเทพฯ',
    ),
    const FeedItemModel(
      id: 'curated-dji-mini-4',
      title: 'DJI Mini 4 Pro\nFly More Combo',
      categoryId: 'camera',
      price: 1200,
      priceUnit: '/ วัน',
      rating: 5.0,
      reviewCount: 67,
      distanceKm: 3.1,
      isVerified: true,
      ownerName: 'Alex Marcus',
      ownerAvatarUrl: 'assets/images/chat_marcus.png',
      imageUrl:
          'https://images.unsplash.com/photo-1527977966376-1c8408f9f108?q=80&w=800&auto=format&fit=crop',
      isCurated: true,
      isFavorite: false,
      tags: ['โดรนถ่ายภาพ', '4K HDR', 'มีใบอนุญาต'],
      locationName: 'อารีย์ • กรุงเทพฯ',
    ),
    const FeedItemModel(
      id: 'curated-canon-r6',
      title: 'Canon EOS R6\nMark II',
      categoryId: 'camera',
      price: 1400,
      priceUnit: '/ วัน',
      rating: 4.9,
      reviewCount: 82,
      distanceKm: 0.9,
      isVerified: true,
      ownerName: 'Elena Jai',
      ownerAvatarUrl: 'assets/images/chat_elena.png',
      imageUrl:
          'https://images.unsplash.com/photo-1502920917128-1aa500764cbd?q=80&w=800&auto=format&fit=crop',
      isCurated: true,
      isFavorite: false,
      tags: ['Full Frame', 'Dual Card Slots'],
      locationName: 'เอกมัย • กรุงเทพฯ',
    ),
  ];

  static final List<FeedItemModel> defaultNearbyItems = [
    const FeedItemModel(
      id: 'nearby-switch-oled',
      title: 'Nintendo Switch Oled',
      categoryId: 'gaming',
      price: 1000,
      priceUnit: '/วัน',
      rating: 4.7,
      reviewCount: 56,
      distanceKm: 0.5,
      isVerified: true,
      ownerName: 'Jessica',
      ownerAvatarUrl: 'assets/images/chat_sarah.png',
      imageUrl:
          'https://images.unsplash.com/photo-1578303512597-8be9f1909e80?q=80&w=600&auto=format&fit=crop',
      tags: ['เกมพกพา', 'แถม 3 เกม'],
      locationName: 'สยามสแควร์',
    ),
    const FeedItemModel(
      id: 'nearby-macbook-pro-m2',
      title: 'MacBook Pro M2',
      categoryId: 'computer',
      price: 2000,
      priceUnit: '/วัน',
      rating: 4.9,
      reviewCount: 110,
      distanceKm: 1.1,
      isVerified: true,
      ownerName: 'Marcus J.',
      ownerAvatarUrl: 'assets/images/chat_marcus.png',
      imageUrl:
          'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?q=80&w=600&auto=format&fit=crop',
      tags: ['RAM 16GB', 'SSD 512GB', 'ตัดต่อวิดีโอ'],
      locationName: 'สามย่าน มิตรทาวน์',
    ),
    const FeedItemModel(
      id: 'nearby-polaroid-sx70',
      title: 'Polaroid SX-70',
      categoryId: 'camera',
      price: 500,
      priceUnit: '/ชั่วโมง',
      rating: 4.6,
      reviewCount: 38,
      distanceKm: 2.3,
      isVerified: true,
      ownerName: 'Elena ใจดี',
      ownerAvatarUrl: 'assets/images/chat_elena.png',
      imageUrl:
          'https://images.unsplash.com/photo-1526170375885-4d8ecf77b99f?q=80&w=600&auto=format&fit=crop',
      tags: ['กล้องวินเทจ', 'ฟิล์มโพลารอยด์'],
      locationName: 'อารีย์ ซอย 4',
    ),
    const FeedItemModel(
      id: 'nearby-sony-lens-2470',
      title: 'Sony FE 24-70mm F2.8 GM II',
      categoryId: 'camera',
      price: 800,
      priceUnit: '/วัน',
      rating: 4.9,
      reviewCount: 73,
      distanceKm: 3.1,
      isVerified: true,
      ownerName: 'Sarah Jenkins',
      ownerAvatarUrl: 'assets/images/chat_sarah.png',
      imageUrl:
          'https://images.unsplash.com/photo-1617005082133-548c4dd27f35?q=80&w=600&auto=format&fit=crop',
      tags: ['เลนส์มาสเตอร์', 'G-Master'],
      locationName: 'ทองหล่อ',
    ),
    const FeedItemModel(
      id: 'nearby-gopro-12',
      title: 'GoPro HERO 12 Black Creator Ed.',
      categoryId: 'camera',
      price: 450,
      priceUnit: '/วัน',
      rating: 4.8,
      reviewCount: 92,
      distanceKm: 3.8,
      isVerified: true,
      ownerName: 'Alex Marcus',
      ownerAvatarUrl: 'assets/images/chat_marcus.png',
      imageUrl:
          'https://images.unsplash.com/photo-1565849904461-04a58ad377e0?q=80&w=600&auto=format&fit=crop',
      tags: ['กันน้ำ', 'บันทึก 5.3K', 'อุปกรณ์เสริมครบ'],
      locationName: 'ลาดพร้าว',
    ),
    const FeedItemModel(
      id: 'nearby-naturehike-tent',
      title: 'เต็นท์ Naturehike Village 13',
      categoryId: 'camping',
      price: 650,
      priceUnit: '/วัน',
      rating: 4.9,
      reviewCount: 45,
      distanceKm: 4.2,
      isVerified: true,
      ownerName: 'Elena ใจดี',
      ownerAvatarUrl: 'assets/images/chat_elena.png',
      imageUrl:
          'https://images.unsplash.com/photo-1504280390367-361c6d9f38f4?q=80&w=600&auto=format&fit=crop',
      tags: ['เต็นท์กางไว', 'พักได้ 4-6 คน', 'กันฝน'],
      locationName: 'รามอินทรา',
    ),
    const FeedItemModel(
      id: 'nearby-marshall-speaker',
      title: 'Marshall Stanmore III Bluetooth',
      categoryId: 'audio',
      price: 400,
      priceUnit: '/วัน',
      rating: 4.8,
      reviewCount: 61,
      distanceKm: 5.0,
      isVerified: true,
      ownerName: 'Jessica',
      ownerAvatarUrl: 'assets/images/chat_sarah.png',
      imageUrl:
          'https://images.unsplash.com/photo-1545454675-3531b543be5d?q=80&w=600&auto=format&fit=crop',
      tags: ['เสียงเบสทรงพลัง', 'เชื่อม Bluetooth 5.2'],
      locationName: 'พระราม 9',
    ),
    const FeedItemModel(
      id: 'nearby-iphone-15-pro',
      title: 'iPhone 15 Pro Max 256GB',
      categoryId: 'phone',
      price: 900,
      priceUnit: '/วัน',
      rating: 4.9,
      reviewCount: 142,
      distanceKm: 1.8,
      isVerified: true,
      ownerName: 'Marcus J.',
      ownerAvatarUrl: 'assets/images/chat_marcus.png',
      imageUrl:
          'https://images.unsplash.com/photo-1695048133142-1a20484d2569?q=80&w=600&auto=format&fit=crop',
      tags: ['ไทเทเนียม', 'กล้องซูม 5x', 'แบตอึด'],
      locationName: 'สาทร',
    ),
    const FeedItemModel(
      id: 'nearby-makita-drill',
      title: 'สว่านกระแทกไร้สาย Makita 18V',
      categoryId: 'tools',
      price: 350,
      priceUnit: '/วัน',
      rating: 4.8,
      reviewCount: 34,
      distanceKm: 2.7,
      isVerified: true,
      ownerName: 'สมศักดิ์ ช่างยนต์',
      imageUrl:
          'https://images.unsplash.com/photo-1504148455328-c376907d081c?q=80&w=600&auto=format&fit=crop',
      tags: ['เครื่องมือช่าง', 'แบตเตอรี่ 2 ก้อน'],
      locationName: 'บางกะปิ',
    ),
    const FeedItemModel(
      id: 'nearby-dyson-purifier',
      title: 'เครื่องฟอกอากาศ Dyson Purifier Hot+Cool',
      categoryId: 'appliances',
      price: 500,
      priceUnit: '/วัน',
      rating: 4.9,
      reviewCount: 48,
      distanceKm: 1.5,
      isVerified: true,
      ownerName: 'Elena ใจดี',
      ownerAvatarUrl: 'assets/images/chat_elena.png',
      imageUrl:
          'https://images.unsplash.com/photo-1585771724684-38269d6639fd?q=80&w=600&auto=format&fit=crop',
      tags: ['กรอง PM2.5', 'ระบบอุ่นและเย็น'],
      locationName: 'สุขุมวิท 39',
    ),
    const FeedItemModel(
      id: 'nearby-yamaha-guitar',
      title: 'กีตาร์โปร่งไฟฟ้า Yamaha FG-TA',
      categoryId: 'music',
      price: 400,
      priceUnit: '/วัน',
      rating: 4.9,
      reviewCount: 52,
      distanceKm: 3.4,
      isVerified: true,
      ownerName: 'Sarah Jenkins',
      ownerAvatarUrl: 'assets/images/chat_sarah.png',
      imageUrl:
          'https://images.unsplash.com/photo-1510915361894-db8b60106cb1?q=80&w=600&auto=format&fit=crop',
      tags: ['เสียงใสกังวาน', 'TransAcoustic'],
      locationName: 'อารีย์',
    ),
    const FeedItemModel(
      id: 'nearby-yonex-racket',
      title: 'ไม้แบดมินตัน Yonex Astrox 88D Pro',
      categoryId: 'sports',
      price: 250,
      priceUnit: '/วัน',
      rating: 4.7,
      reviewCount: 29,
      distanceKm: 2.1,
      isVerified: true,
      ownerName: 'Marcus J.',
      ownerAvatarUrl: 'assets/images/chat_marcus.png',
      imageUrl:
          'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?q=80&w=600&auto=format&fit=crop',
      tags: ['เอ็น BG65 26lbs', 'ไม้แข่งขัน'],
      locationName: 'ดินแดง',
    ),
  ];

  final Set<String> _favoriteItemIds = {'curated-specialized-bike'};

  Future<List<FeedCategoryModel>> fetchCategories() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return defaultCategories;
  }

  Future<List<FeedItemModel>> fetchCuratedItems() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return defaultCuratedItems.map((item) {
      return item.copyWith(isFavorite: _favoriteItemIds.contains(item.id));
    }).toList();
  }

  Future<List<FeedItemModel>> fetchNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    var items = List<FeedItemModel>.from(defaultNearbyItems);

    if (categoryId != null && categoryId.isNotEmpty && categoryId != 'all') {
      items = items.where((item) => item.categoryId == categoryId).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = searchQuery.trim().toLowerCase();
      items = items.where((item) {
        final matchesTitle = item.title.toLowerCase().contains(query);
        final matchesCategory = item.categoryId.toLowerCase().contains(query);
        final matchesTags = item.tags.any((t) => t.toLowerCase().contains(query));
        final matchesLocation = item.locationName.toLowerCase().contains(query);
        return matchesTitle || matchesCategory || matchesTags || matchesLocation;
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

    return items.map((item) {
      return item.copyWith(isFavorite: _favoriteItemIds.contains(item.id));
    }).toList();
  }

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

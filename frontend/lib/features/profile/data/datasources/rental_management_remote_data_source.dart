import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/rental_income.dart';
import '../models/rental_booking_model.dart';

// คำอธิบาย: Data Source จัดการการดึงและอัปเดตข้อมูลการเช่า/ปล่อยเช่า, ส่งมอบ, คืนของ และรายได้
class RentalManagementRemoteDataSource {
  RentalManagementRemoteDataSource({
    ApiClient? apiClient,
    SupabaseClient? client,
  }) : _apiClient = apiClient,
       _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabaseClient => _client ?? SupabaseConfig.client;

  ApiClient? _apiClient;
  ApiClient get _backendClient => _apiClient ??= DioApiClient();
  Future<List<RentalBookingModel>> getRentingBookings(String userId) async {
    if ((_client == null && !SupabaseConfig.isInitialized) || userId.isEmpty)
      return [];

    try {
      final client = _supabaseClient;
      final rentingResp = await client
          .from('booking_tb')
          .select(
            'id, user_id, item_id, start_date, end_date, start_at, end_at, price, total_price, status, type, pickup_location, latitude, longitude, pickup_note, created_at',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> rawBookings =
          List<Map<String, dynamic>>.from(rentingResp as List);

      // กรองสถานะ reject ออกจากหน้ารายการสถานะ
      final validBookings = rawBookings.where((b) {
        final s = (b['status']?.toString() ?? '').toLowerCase().trim();
        return s != 'rejected' && s != 'reject';
      }).toList();

      if (validBookings.isEmpty) return [];

      final itemIds = validBookings
          .map((b) => (b['item_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      final itemsMap = await _fetchItemsMap(itemIds);
      final partnerUserIds = <String>{};
      for (final item in itemsMap.values) {
        final ownerId = item['user_id']?.toString();
        if (ownerId != null && ownerId.isNotEmpty) {
          partnerUserIds.add(ownerId);
        }
      }

      final (userNames, userPhones) = await _fetchProfilesMap(partnerUserIds);

      final List<RentalBookingModel> result = [];
      for (final b in validBookings) {
        final itemId = (b['item_id'] as num?)?.toInt();
        final itemData = itemId != null ? itemsMap[itemId] : null;
        final ownerId = itemData?['user_id']?.toString() ?? '';

        result.add(
          RentalBookingModel.fromSupabase(
            booking: b,
            itemData: itemData,
            partnerName: userNames[ownerId],
            partnerPhone: userPhones[ownerId],
            isOwner: false,
          ),
        );
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<RentalBookingModel>> getLendingBookings(String userId) async {
    if ((_client == null && !SupabaseConfig.isInitialized) || userId.isEmpty)
      return [];

    try {
      final client = _supabaseClient;
      final myItemsResp = await client
          .from('item_tb')
          .select('id')
          .eq('user_id', userId);

      final myItemIds = (myItemsResp as List)
          .map((it) => (it['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();

      if (myItemIds.isEmpty) return [];

      final lendingResp = await client
          .from('booking_tb')
          .select(
            'id, user_id, item_id, start_date, end_date, start_at, end_at, price, total_price, status, type, pickup_location, latitude, longitude, pickup_note, created_at',
          )
          .inFilter('item_id', myItemIds)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> rawBookings =
          List<Map<String, dynamic>>.from(lendingResp as List);

      // กรองสถานะ reject ออกจากหน้ารายการสถานะ
      final validBookings = rawBookings.where((b) {
        final s = (b['status']?.toString() ?? '').toLowerCase().trim();
        return s != 'rejected' && s != 'reject';
      }).toList();

      if (validBookings.isEmpty) return [];

      final itemIds = validBookings
          .map((b) => (b['item_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      final itemsMap = await _fetchItemsMap(itemIds);
      final partnerUserIds = <String>{};
      for (final b in validBookings) {
        final renterId = b['user_id']?.toString();
        if (renterId != null && renterId.isNotEmpty) {
          partnerUserIds.add(renterId);
        }
      }

      final (userNames, userPhones) = await _fetchProfilesMap(partnerUserIds);

      final List<RentalBookingModel> result = [];
      for (final b in validBookings) {
        final itemId = (b['item_id'] as num?)?.toInt();
        final itemData = itemId != null ? itemsMap[itemId] : null;
        final renterId = b['user_id']?.toString() ?? '';

        result.add(
          RentalBookingModel.fromSupabase(
            booking: b,
            itemData: itemData,
            partnerName: userNames[renterId],
            partnerPhone: userPhones[renterId],
            isOwner: true,
          ),
        );
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<RentalBookingModel>> getRentalHistory(String userId) async {
    return getRentingBookings(userId);
  }

  Future<void> updateBookingStatus({
    required int bookingId,
    required String status,
  }) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('กรุณาเข้าสู่ระบบก่อนดำเนินการ');
    }

    final String endpoint;
    if (status == 'active') {
      endpoint = '/api/rentals/$bookingId/handover';
    } else if (status == 'completed') {
      endpoint = '/api/rentals/$bookingId/return';
    } else {
      endpoint = '/api/rentals/$bookingId/status';
    }

    await _backendClient.post(
      endpoint,
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<RentalIncomeSummary> getRentalIncome(String userId) async {
    // โครงสร้างสำหรับ Dashboard รายได้ และ Transaction ประวัติ
    const totalIncome = 12500.0;
    const pendingIncome = 1200.0;
    final history = [
      const RentalIncomeEntry(
        itemName: 'Sony A7 IV',
        date: '12 ส.ค. 2026',
        duration: 'เช่า 3 วัน',
        amount: 2400,
        status: 'เสร็จสิ้น',
      ),
      const RentalIncomeEntry(
        itemName: 'DJI Mavic Pro',
        date: '10 ส.ค. 2026',
        duration: 'เช่า 1 วัน',
        amount: 800,
        status: 'เสร็จสิ้น',
      ),
      const RentalIncomeEntry(
        itemName: 'MacBook Pro M2',
        date: '5 ส.ค. 2026',
        duration: 'เช่า 5 วัน',
        amount: 4500,
        status: 'เสร็จสิ้น',
      ),
      const RentalIncomeEntry(
        itemName: 'Sony A7 IV',
        date: '1 ส.ค. 2026',
        duration: 'เช่า 2 วัน',
        amount: 1600,
        status: 'เสร็จสิ้น',
      ),
      const RentalIncomeEntry(
        itemName: 'เลนส์ FE 50mm f/1.8',
        date: '28 ก.ค. 2026',
        duration: 'เช่า 4 วัน',
        amount: 1200,
        status: 'เสร็จสิ้น',
      ),
    ];

    return RentalIncomeSummary(
      totalIncome: totalIncome,
      pendingIncome: pendingIncome,
      transactions: history,
    );
  }

  Future<Map<int, Map<String, dynamic>>> _fetchItemsMap(
    List<int> itemIds,
  ) async {
    if (itemIds.isEmpty) return {};
    final Map<int, Map<String, dynamic>> itemsMap = {};
    try {
      final itemsResp = await _supabaseClient
          .from('item_tb')
          .select(
            'id, user_id, item_name, category, item_image_url, price, type',
          )
          .inFilter('id', itemIds);

      for (final it in (itemsResp as List)) {
        if (it is Map) {
          final id = (it['id'] as num?)?.toInt();
          if (id != null) {
            itemsMap[id] = Map<String, dynamic>.from(it);
          }
        }
      }
    } catch (_) {}
    return itemsMap;
  }

  Future<(Map<String, String>, Map<String, String>)> _fetchProfilesMap(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return (<String, String>{}, <String, String>{});
    final Map<String, String> userNames = {};
    final Map<String, String> userPhones = {};
    try {
      final profilesResp = await _supabaseClient
          .from('public_profile_v')
          .select('user_id, display_name')
          .inFilter('user_id', userIds.toList());

      for (final p in (profilesResp as List)) {
        if (p is Map) {
          final uid = p['user_id']?.toString();
          final displayName = p['display_name']?.toString() ?? 'ผู้ใช้งาน';
          if (uid != null) {
            userNames[uid] = displayName;
          }
        }
      }
    } catch (_) {}
    return (userNames, userPhones);
  }
}

import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/rental_handover_code.dart';
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
    if ((_client == null && !SupabaseConfig.isInitialized) || userId.isEmpty) {
      throw StateError('ไม่สามารถเชื่อมต่อหรือยืนยันบัญชีเพื่อโหลดประวัติการเช่าได้');
    }

    try {
      final client = _supabaseClient;
      final rentingResp = await client
          .from('booking_tb')
          .select(
            'id, user_id, item_id, start_date, end_date, start_at, end_at, price, total_price, status, type, pickup_location, pickup_note, created_at',
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
      throw StateError('โหลดประวัติการเช่าไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่');
    }
  }

  Future<List<RentalBookingModel>> getLendingBookings(String userId) async {
    if ((_client == null && !SupabaseConfig.isInitialized) || userId.isEmpty) {
      throw StateError('ไม่สามารถเชื่อมต่อหรือยืนยันบัญชีเพื่อโหลดรายการปล่อยเช่าได้');
    }

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
            'id, user_id, item_id, start_date, end_date, start_at, end_at, price, total_price, status, type, pickup_location, pickup_note, created_at',
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
      throw StateError('โหลดรายการปล่อยเช่าไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่');
    }
  }

  Future<List<RentalBookingModel>> getRentalHistory(String userId) async {
    return getRentingBookings(userId);
  }

  Future<RentalHandoverCode> createHandoverCode({required int bookingId}) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('กรุณาเข้าสู่ระบบก่อนดำเนินการ');
    }
    final response = await _backendClient.post(
      '/api/rentals/$bookingId/handover-code',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200 || response.data is! Map) {
      final data = response.data;
      throw StateError(
        data is Map
            ? data['error']?.toString() ?? 'สร้างรหัสส่งมอบไม่สำเร็จ'
            : 'สร้างรหัสส่งมอบไม่สำเร็จ',
      );
    }
    final code = (response.data as Map)['code']?.toString() ?? '';
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw StateError('เซิร์ฟเวอร์ส่งรหัสส่งมอบไม่ถูกต้อง');
    }
    final expiresAtValue = (response.data as Map)['expires_at']?.toString();
    final expiresAt = expiresAtValue == null ? null : DateTime.tryParse(expiresAtValue);
    if (expiresAt == null) {
      throw StateError('เซิร์ฟเวอร์ไม่ส่งเวลาหมดอายุของรหัสส่งมอบ');
    }
    return RentalHandoverCode(code: code, expiresAt: expiresAt.toLocal());
  }

  Future<void> updateBookingStatus({
    required int bookingId,
    required String status,
  }) async {
    if (status == 'active') {
      throw StateError('กรุณายืนยันรหัสส่งมอบจากผู้เช่าก่อน');
    }
    throw StateError('กรุณาดำเนินการผ่านขั้นตอนตรวจสภาพและยืนยันการคืน');
  }

  Future<void> completeHandover({
    required int bookingId,
    required String code,
  }) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('กรุณาเข้าสู่ระบบก่อนดำเนินการ');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw StateError('กรุณากรอกรหัสส่งมอบ 6 หลักจากผู้เช่า');
    }
    final response = await _backendClient.post(
      '/api/rentals/$bookingId/handover',
      headers: {'Authorization': 'Bearer $token'},
      data: {'code': code},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final data = response.data;
      throw StateError(
        data is Map
            ? data['error']?.toString() ?? 'ยืนยันรหัสส่งมอบไม่สำเร็จ'
            : 'ยืนยันรหัสส่งมอบไม่สำเร็จ',
      );
    }
  }

  Future<RentalIncomeSummary> getRentalIncome(String userId) async {
    return RentalIncomeSummary(
      totalIncome: 0,
      pendingIncome: 0,
      transactions: const [],
      isAvailable: false,
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
            'id, user_id, item_name, category, item_image_url, price, type, pickup_latitude, pickup_longitude',
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
    } catch (_) {
      throw StateError('โหลดข้อมูลอุปกรณ์ในประวัติไม่สำเร็จ');
    }
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
          .schema('profiles')
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

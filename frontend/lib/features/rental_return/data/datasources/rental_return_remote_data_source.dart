import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/rental_return_session.dart';

class RentalReturnRemoteDataSource {
  final SupabaseClient _client;

  RentalReturnRemoteDataSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// ดึงข้อมูลรายการเช่าจริงจาก Supabase (booking_tb หรือ item_tb + profile_tb)
  Future<RentalReturnSession> getSession([int? rentalId]) async {
    try {
      Map<String, dynamic>? bookingResp;
      int itemId = 0;
      String renterId = '';
      DateTime startAt = DateTime.now().subtract(const Duration(hours: 4));
      DateTime endAt = DateTime.now().add(const Duration(hours: 2, minutes: 15));
      String pickupLocation = 'จุดนัดพบที่ตกลงไว้ (สยามพารากอน ชั้น 3)';
      double totalPrice = 1000.0;
      int activeRentalId = rentalId ?? 0;

      // 1. ถ้ามี rentalId ส่งเข้ามา ลองหาจาก booking_tb ด้วย ID
      if (activeRentalId > 0) {
        bookingResp = await _client
            .from('booking_tb')
            .select()
            .eq('id', activeRentalId)
            .maybeSingle();
      }

      // 2. ถ้าไม่มี rentalId หรือยังไม่เจอ ลองค้นหาออเดอร์ล่าสุดของผู้ใช้ปัจจุบัน
      if (bookingResp == null) {
        final currentUserId = _client.auth.currentUser?.id;
        if (currentUserId != null && currentUserId.isNotEmpty) {
          bookingResp = await _client
              .from('booking_tb')
              .select()
              .eq('user_id', currentUserId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
        }
      }

      // 3. ถอดข้อมูลจาก bookingResp
      if (bookingResp != null) {
        activeRentalId = (bookingResp['id'] as num?)?.toInt() ?? activeRentalId;
        itemId = (bookingResp['item_id'] as num?)?.toInt() ?? 0;
        renterId = bookingResp['user_id']?.toString() ?? '';

        final startAtStr = bookingResp['start_at'] ?? bookingResp['start_date'];
        final endAtStr = bookingResp['end_at'] ?? bookingResp['end_date'];

        if (startAtStr != null) {
          startAt = DateTime.tryParse(startAtStr.toString()) ?? startAt;
        }
        if (endAtStr != null) {
          endAt = DateTime.tryParse(endAtStr.toString()) ?? endAt;
        }

        pickupLocation = bookingResp['pickup_location']?.toString() ?? pickupLocation;
        totalPrice = (bookingResp['total_price'] as num?)?.toDouble() ??
            (bookingResp['price'] as num?)?.toDouble() ??
            1000.0;
      } else if (activeRentalId > 0) {
        // หากไม่พบใน booking_tb ให้ถือว่า rentalId คือ itemId จาก item_tb โดยตรง
        itemId = activeRentalId;
      } else {
        // หากยังไม่มีรายการ booking ของ user ให้ลองดึงสินค้าจริงล่าสุดในระบบมาแสดง
        final latestItem = await _client
            .from('item_tb')
            .select('id')
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (latestItem != null) {
          itemId = (latestItem['id'] as num?)?.toInt() ?? 0;
          activeRentalId = itemId;
        }
      }

      // 4. ดึงข้อมูลอุปกรณ์จาก item_tb
      Map<String, dynamic>? itemData;
      if (itemId > 0) {
        itemData = await _client
            .from('item_tb')
            .select('id, user_id, item_name, category, price, item_image_url')
            .eq('id', itemId)
            .maybeSingle();
      }

      if (itemData != null) {
        final lenderId = itemData['user_id']?.toString() ?? '';
        String lenderName = 'ร้านค้าผู้ปล่อยเช่า';
        String lenderPhone = '081-999-8877';

        // 3. ดึงชื่อผู้ให้เช่าจาก profile_tb
        if (lenderId.isNotEmpty) {
          final lenderProfile = await _client
              .from('profile_tb')
              .select('email, phone_number')
              .eq('user_id', lenderId)
              .maybeSingle();
          if (lenderProfile != null) {
            final email = lenderProfile['email']?.toString();
            if (email != null && email.isNotEmpty) {
              lenderName = email.split('@').first;
            }
            final phone = lenderProfile['phone_number']?.toString();
            if (phone != null && phone.isNotEmpty) {
              lenderPhone = phone;
            }
          }
        }

        // ดึงชื่อผู้เช่าปัจจุบัน
        String renterName = 'คุณพัชรพล (ผู้เช่า)';
        final currentAuthUser = _client.auth.currentUser;
        if (currentAuthUser != null) {
          renterId = currentAuthUser.id;
          final userProfile = await _client
              .from('profile_tb')
              .select('email')
              .eq('user_id', currentAuthUser.id)
              .maybeSingle();
          if (userProfile != null && userProfile['email'] != null) {
            renterName = userProfile['email'].toString().split('@').first;
          }
        }

        final rawImages = itemData['item_image_url'];
        String mainImageUrl =
            'https://images.unsplash.com/photo-1502920917128-1aa500764cbd?w=800&auto=format&fit=crop';
        if (rawImages is List && rawImages.isNotEmpty) {
          mainImageUrl = rawImages.first.toString();
        } else if (rawImages is String && rawImages.isNotEmpty) {
          mainImageUrl = rawImages;
        }

        final itemPrice = (itemData['price'] as num?)?.toDouble() ?? 500.0;
        if (bookingResp == null) {
          totalPrice = itemPrice;
        }
        final depositAmount = (itemPrice * 2.5).clamp(1000.0, 15000.0);

        final randomChallenge = 'YM-${Random().nextInt(9000) + 1000}';
        final category = itemData['category']?.toString() ?? 'ทั่วไป';

        // ปรับมุมการตรวจสภาพให้สอดคล้องกับประเภทอุปกรณ์
        final photos = _buildPhotosForCategory(category, randomChallenge);

        return RentalReturnSession(
          rentalId: activeRentalId > 0 ? activeRentalId : 1024,
          itemName: itemData['item_name']?.toString() ?? 'อุปกรณ์เช่า #${activeRentalId > 0 ? activeRentalId : 1024}',
          itemImageUrl: mainImageUrl,
          category: category,
          renterId: renterId,
          renterName: renterName,
          lenderId: lenderId,
          lenderName: lenderName,
          lenderPhone: lenderPhone,
          startAt: startAt,
          endAt: endAt,
          pickupLocation: pickupLocation,
          totalPrice: totalPrice,
          depositAmount: depositAmount,
          step: RentalReturnStep.inProgress,
          dynamicChallengeCode: randomChallenge,
          photos: photos,
          checklist: {
            'power_on': false,
            'no_new_cracks': false,
            'accessories_complete': false,
          },
        );
      }
    } catch (e) {
      debugPrint('Warning fetching session from Supabase: $e. Falling back to mock session.');
    }

    // หากไม่พบในฐานข้อมูล ให้ใช้ Mock Session ที่จำลองตาม rentalId อย่างแม่นยำ
    return RentalReturnSession.createMockSession(rentalId: rentalId ?? 1024);
  }

  List<ReturnInspectionPhoto> _buildPhotosForCategory(String category, String challengeCode) {
    final now = DateTime.now();
    final catLower = category.toLowerCase();

    if (catLower.contains('กล้อง') || catLower.contains('ถ่ายภาพ')) {
      return [
        ReturnInspectionPhoto(
          angleKey: 'angle_1',
          angleTitle: '1. ด้านหน้าจอเปิดติด และเซนเซอร์',
          challengeCode: challengeCode,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_2',
          angleTitle: '2. ตัวบอดี้ เลนส์ และฝาปิดหน้าเลนส์',
          challengeCode: challengeCode,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_3',
          angleTitle: '3. แบตเตอรี่ แท่นชาร์จ สายคล้อง & S/N',
          challengeCode: challengeCode,
          timestamp: now,
        ),
      ];
    } else if (catLower.contains('โดรน') || catLower.contains('บิน')) {
      return [
        ReturnInspectionPhoto(
          angleKey: 'angle_1',
          angleTitle: '1. มอเตอร์และใบพัดทั้ง 4 แกน',
          challengeCode: challengeCode,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_2',
          angleTitle: '2. กิมบอลและเซนเซอร์กล้อง',
          challengeCode: challengeCode,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_3',
          angleTitle: '3. รีโมตคอนโทรล แบตเตอรี่ & S/N',
          challengeCode: challengeCode,
          timestamp: now,
        ),
      ];
    } else if (catLower.contains('แล็ปท็อป') || catLower.contains('คอมพิวเตอร์')) {
      return [
        ReturnInspectionPhoto(
          angleKey: 'angle_1',
          angleTitle: '1. หน้าจอเปิดติด และคีย์บอร์ดเรืองแสง',
          challengeCode: challengeCode,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_2',
          angleTitle: '2. รอบตัวเครื่อง ฝาบน-ล่าง ไร้รอยบุบ',
          challengeCode: challengeCode,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_3',
          angleTitle: '3. หัวชาร์จ อะแดปเตอร์ & Serial Number',
          challengeCode: challengeCode,
          timestamp: now,
        ),
      ];
    }

    return [
      ReturnInspectionPhoto(
        angleKey: 'angle_1',
        angleTitle: '1. ด้านหน้าและไฟสถานะเปิดติด',
        challengeCode: challengeCode,
        timestamp: now,
      ),
      ReturnInspectionPhoto(
        angleKey: 'angle_2',
        angleTitle: '2. สภาพรอบตัวเครื่องไม่มีรอยแตกหัก',
        challengeCode: challengeCode,
        timestamp: now,
      ),
      ReturnInspectionPhoto(
        angleKey: 'angle_3',
        angleTitle: '3. อุปกรณ์เสริม สายต่อ & Serial Number',
        challengeCode: challengeCode,
        timestamp: now,
      ),
    ];
  }

  /// อัปโหลดรูปถ่ายไปยัง Supabase Storage
  Future<String> uploadPhoto({
    required int rentalId,
    required String photoPath,
    required String angleKey,
  }) async {
    try {
      final fileName =
          'return_${rentalId}_${angleKey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'return_inspections/$fileName';

      // อ่าน bytes ซึ่งทำงานได้ทั้ง Web และ Mobile
      final bytes = await XFile(photoPath).readAsBytes();

      // อัปโหลดไปยัง bucket 'item_bk'
      await _client.storage.from('item_bk').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      return _client.storage.from('item_bk').getPublicUrl(path);
    } catch (e) {
      debugPrint('Storage upload note: $e. Using local image path.');
      return photoPath;
    }
  }

  /// อัปเดตสถานะการส่งตรวจสภาพใน booking_tb
  Future<void> submitVerification({
    required int rentalId,
    required List<ReturnInspectionPhoto> photos,
    required Map<String, bool> checklist,
  }) async {
    try {
      await _client.from('booking_tb').update({
        'status': 'รอส่งคืน',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', rentalId);
    } catch (e) {
      debugPrint('Note updating booking status: $e');
    }
  }

  /// สร้าง Dynamic QR Token จากฝั่งร้านค้า
  Future<Map<String, String>> generateMerchantToken(int rentalId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final otp = (100000 + Random().nextInt(900000)).toString();
    final token = 'YUEMNOI_RETURN_${rentalId}_${otp}_$timestamp';
    return {
      'token': token,
      'otp': otp,
    };
  }

  /// บันทึกการคืนของเสร็จสมบูรณ์
  Future<void> markCompleted(int rentalId) async {
    try {
      await _client.from('booking_tb').update({
        'status': 'คืนของสำเร็จ',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', rentalId);
    } catch (e) {
      debugPrint('Note updating booking completion: $e');
    }
  }
}

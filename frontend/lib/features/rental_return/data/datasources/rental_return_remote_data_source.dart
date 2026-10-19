import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/rental_return_session.dart';

class RentalReturnRemoteDataSource {
  final SupabaseClient? _customClient;

  RentalReturnRemoteDataSource({SupabaseClient? client})
    : _customClient = client;

  SupabaseClient? get _client =>
      _customClient ??
      (SupabaseConfig.isInitialized ? SupabaseConfig.client : null);

  /// ดึงข้อมูลรายการเช่าจริงจาก Supabase (booking_tb หรือ item_tb + profile_tb)
  Future<RentalReturnSession> getSession([int? rentalId]) async {
    try {
      final client = _client;
      if (client == null) {
        return RentalReturnSession.createMockSession(rentalId: rentalId);
      }
      Map<String, dynamic>? bookingResp;
      int itemId = 0;
      String renterId = '';
      DateTime startAt = DateTime.now().subtract(const Duration(hours: 4));
      DateTime endAt = DateTime.now().add(
        const Duration(hours: 2, minutes: 15),
      );
      String pickupLocation = 'จุดนัดพบที่ตกลงไว้ (สยามพารากอน ชั้น 3)';
      double totalPrice = 1000.0;
      int activeRentalId = rentalId ?? 0;

      // 1. ถ้ามี rentalId ส่งเข้ามา ลองหาจาก booking_tb ด้วย ID
      if (activeRentalId > 0) {
        bookingResp = await client
            .from('booking_tb')
            .select()
            .eq('id', activeRentalId)
            .maybeSingle();
      }

      // 2. ถ้าไม่มี rentalId หรือยังไม่เจอ ลองค้นหาออเดอร์ล่าสุดของผู้ใช้ปัจจุบัน
      if (bookingResp == null) {
        final currentUserId = client.auth.currentUser?.id;
        if (currentUserId != null && currentUserId.isNotEmpty) {
          bookingResp = await client
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

        pickupLocation =
            bookingResp['pickup_location']?.toString() ?? pickupLocation;
        totalPrice =
            (bookingResp['total_price'] as num?)?.toDouble() ??
            (bookingResp['price'] as num?)?.toDouble() ??
            1000.0;
      } else if (activeRentalId > 0) {
        // หากไม่พบใน booking_tb ให้ถือว่า rentalId คือ itemId จาก item_tb โดยตรง
        itemId = activeRentalId;
      } else {
        // หากยังไม่มีรายการ booking ของ user ให้ลองดึงสินค้าจริงล่าสุดในระบบมาแสดง
        final latestItem = await client
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
        itemData = await client
            .from('item_tb')
            .select('id, user_id, item_name, category, price, item_image_url')
            .eq('id', itemId)
            .maybeSingle();
      }

      if (itemData != null) {
        final lenderId = itemData['user_id']?.toString() ?? '';
        String lenderName = 'ร้านค้าผู้ปล่อยเช่า';
        String lenderPhone = '081-999-8877';

        // 3. ดึงชื่อผู้ให้เช่าจาก public_profile_v
        if (lenderId.isNotEmpty) {
          final lenderProfile = await client
              .from('public_profile_v')
              .select('display_name, email, phone')
              .eq('user_id', lenderId)
              .maybeSingle();
          if (lenderProfile != null) {
            final displayName =
                lenderProfile['display_name']?.toString().trim() ?? '';
            final email = lenderProfile['email']?.toString() ?? '';
            if (displayName.isNotEmpty) {
              lenderName = displayName;
            } else if (email.isNotEmpty) {
              lenderName = email.split('@').first;
            }
            final phone = lenderProfile['phone']?.toString();
            if (phone != null && phone.isNotEmpty) {
              lenderPhone = phone;
            }
          }
        }

        // ดึงชื่อผู้เช่าปัจจุบัน
        String renterName = 'คุณพัชรพล (ผู้เช่า)';
        final currentAuthUser = client.auth.currentUser;
        if (currentAuthUser != null) {
          renterId = currentAuthUser.id;
          final userProfile = await client
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

        final effectiveOrderId = activeRentalId > 0 ? activeRentalId : 1024;
        final orderChallenge =
            'YM-${effectiveOrderId.toString().padLeft(5, '0')}';
        final category = itemData['category']?.toString() ?? 'ทั่วไป';

        // ตรวจสอบว่ามี return_photos ที่ลูกค้าเคยส่งไว้ใน booking_tb หรือไม่
        List<ReturnInspectionPhoto> photos = [];
        final rawPhotos = bookingResp?['return_photos'];
        if (rawPhotos != null && rawPhotos.toString().isNotEmpty) {
          try {
            final decoded = rawPhotos is List
                ? rawPhotos
                : jsonDecode(rawPhotos.toString());
            if (decoded is List) {
              photos = decoded.map((item) {
                final map = item is Map<String, dynamic>
                    ? item
                    : Map<String, dynamic>.from(item as Map);
                return ReturnInspectionPhoto(
                  angleKey: map['angleKey']?.toString() ?? 'angle_1',
                  angleTitle:
                      map['angleTitle']?.toString() ?? 'ภาพถ่ายสภาพเครื่อง',
                  localPath: map['localPath']?.toString(),
                  imageUrl: map['imageUrl']?.toString(),
                  challengeCode:
                      map['challengeCode']?.toString() ?? orderChallenge,
                  timestamp:
                      DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
                      DateTime.now(),
                  locationText: map['locationText']?.toString(),
                );
              }).toList();
            }
          } catch (e) {
            debugPrint('Failed to decode return_photos: $e');
          }
        }

        // หากยังไม่มีภาพถ่ายส่งมา ให้สร้างมุมตามหมวดหมู่อุปกรณ์
        if (photos.isEmpty) {
          photos = _buildPhotosForCategory(category, orderChallenge);
        }

        final dbStatus = bookingResp?['status']
            ?.toString()
            .toLowerCase()
            .trim();
        RentalReturnStep initialStep = RentalReturnStep.inProgress;
        if (dbStatus == 'คืนของสำเร็จ' || dbStatus == 'completed') {
          initialStep = RentalReturnStep.completed;
        } else if (photos.any((p) => p.hasPhoto) ||
            dbStatus == 'รอส่งคืน' ||
            dbStatus == 'awaiting_return') {
          initialStep = RentalReturnStep.lenderInspecting;
        }

        return RentalReturnSession(
          rentalId: effectiveOrderId,
          itemId: itemId > 0 ? itemId : null,
          itemName:
              itemData['item_name']?.toString() ??
              'อุปกรณ์เช่า #${effectiveOrderId.toString().padLeft(5, '0')}',
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
          step: initialStep,
          dynamicChallengeCode: orderChallenge,
          photos: photos,
          checklist: {
            'power_on': photos.any((p) => p.hasPhoto),
            'no_new_cracks': photos.any((p) => p.hasPhoto),
            'accessories_complete': photos.any((p) => p.hasPhoto),
          },
        );
      }
    } catch (e) {
      debugPrint(
        'Warning fetching session from Supabase: $e. Falling back to mock session.',
      );
    }

    // หากไม่พบในฐานข้อมูล ให้ใช้ Mock Session ที่จำลองตาม rentalId อย่างแม่นยำ
    return RentalReturnSession.createMockSession(rentalId: rentalId ?? 1024);
  }

  List<ReturnInspectionPhoto> _buildPhotosForCategory(
    String category,
    String challengeCode,
  ) {
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
    } else if (catLower.contains('แล็ปท็อป') ||
        catLower.contains('คอมพิวเตอร์')) {
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
      final client = _client;
      if (client == null) return photoPath;

      final booking = await client
          .from('booking_tb')
          .select('item_id')
          .eq('id', rentalId)
          .single();
      final itemId = (booking['item_id'] as num).toInt();
      final item = await client
          .from('item_tb')
          .select('user_id')
          .eq('id', itemId)
          .single();
      final ownerId = item['user_id'] as String;

      final fileName =
          'return_${rentalId}_${angleKey}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final path = '$ownerId/$itemId/$fileName';

      // อ่าน bytes ซึ่งทำงานได้ทั้ง Web และ Mobile
      final bytes = await XFile(photoPath).readAsBytes();

      // อัปโหลดไปยัง bucket 'item_bk'
      await client.storage
          .from('item_bk')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              contentType: 'image/jpeg',
            ),
          );

      return client.storage.from('item_bk').getPublicUrl(path);
    } catch (e) {
      debugPrint('Storage upload note: $e. Using local image path.');
      return photoPath;
    }
  }

  /// อัปเดตสถานะการส่งตรวจสภาพใน booking_tb และบันทึกภาพถ่ายสภาพเครื่อง
  Future<void> submitVerification({
    required int rentalId,
    required List<ReturnInspectionPhoto> photos,
    required Map<String, bool> checklist,
  }) async {
    try {
      final client = _client;
      if (client == null) return;

      final List<Map<String, dynamic>> photosData = [];
      for (final p in photos) {
        String? finalImageUrl = p.imageUrl;
        if ((finalImageUrl == null || finalImageUrl.isEmpty) &&
            p.localPath != null &&
            p.localPath!.isNotEmpty) {
          try {
            finalImageUrl = await uploadPhoto(
              rentalId: rentalId,
              photoPath: p.localPath!,
              angleKey: p.angleKey,
            );
          } catch (e) {
            debugPrint('Failed to upload photo for ${p.angleKey}: $e');
            finalImageUrl = p.localPath;
          }
        }
        photosData.add({
          'angleKey': p.angleKey,
          'angleTitle': p.angleTitle,
          'localPath': p.localPath,
          'imageUrl': finalImageUrl,
          'challengeCode': p.challengeCode,
          'timestamp': p.timestamp.toUtc().toIso8601String(),
          'locationText': p.locationText,
        });
      }

      final photosJson = jsonEncode(photosData);
      final challengeCode = photos.isNotEmpty
          ? photos.first.challengeCode
          : 'YM-${rentalId.toString().padLeft(5, '0')}';

      await client
          .from('booking_tb')
          .update({
            'status': 'รอส่งคืน',
            'return_photos': photosJson,
            'challenge_code': challengeCode,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', rentalId);
    } catch (e) {
      debugPrint('Note updating booking status and return photos: $e');
    }
  }

  /// สร้าง Dynamic QR Token จากฝั่งร้านค้า
  Future<Map<String, String>> generateMerchantToken(int rentalId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final otp = (100000 + Random().nextInt(900000)).toString();
    final token = 'YUEMNOI_RETURN_${rentalId}_${otp}_$timestamp';
    return {'token': token, 'otp': otp};
  }

  /// บันทึกการคืนของเสร็จสมบูรณ์
  Future<void> markCompleted(int rentalId) async {
    try {
      final client = _client;
      if (client == null) return;

      await client
          .from('booking_tb')
          .update({
            'status': 'คืนของสำเร็จ',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', rentalId);
    } catch (e) {
      debugPrint('Note updating booking completion: $e');
    }
  }
}

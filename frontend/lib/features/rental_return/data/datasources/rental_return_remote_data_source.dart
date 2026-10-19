import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/rental_return_session.dart';

class RentalReturnRemoteDataSource {
  RentalReturnRemoteDataSource({
    SupabaseClient? client,
    ApiClient? apiClient,
    String? Function()? accessToken,
  }) : _api = apiClient ?? DioApiClient(),
       _accessToken = accessToken ?? (() => AuthSession.accessToken);

  final ApiClient _api;
  final String? Function() _accessToken;

  Map<String, String> get _headers {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw StateError('กรุณาเข้าสู่ระบบก่อนดำเนินการ');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _result(ApiResponse response) {
    final data = response.data;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data is Map
            ? data['error']?.toString() ?? 'ไม่สามารถดำเนินการเช่าได้'
            : 'ไม่สามารถดำเนินการเช่าได้',
      );
    }
    if (data is! Map) throw StateError('ข้อมูลการเช่าไม่ถูกต้อง');
    return Map<String, dynamic>.from(data);
  }

  Future<RentalReturnSession> getSession([int? rentalId]) async {
    if (rentalId == null || rentalId <= 0)
      throw StateError('กรุณาเลือกรายการเช่าที่ต้องการคืน');
    final data = _result(
      await _api.get(
        '/api/rentals/$rentalId/return-session',
        headers: _headers,
      ),
    );
    final booking = Map<String, dynamic>.from(data['booking'] as Map);
    final item = Map<String, dynamic>.from(data['item'] as Map);
    final returnState = Map<String, dynamic>.from(
      data['return_state'] as Map? ?? {},
    );
    final status = booking['status']?.toString();
    if (![
      'active',
      'awaiting_return',
      'return_ready',
      'completed',
    ].contains(status)) {
      throw StateError('รายการนี้ยังไม่อยู่ในขั้นตอนคืนอุปกรณ์');
    }
    final challenge = 'YM-${rentalId.toString().padLeft(5, '0')}';
    final rawPhotos = returnState['photos'] as List? ?? [];
    final photos = rawPhotos.map((raw) {
      final photo = Map<String, dynamic>.from(raw as Map);
      return ReturnInspectionPhoto(
        angleKey: photo['angleKey']?.toString() ?? 'angle_1',
        angleTitle: photo['angleTitle']?.toString() ?? 'ภาพตรวจสภาพ',
        imageUrl: photo['imageUrl']?.toString(),
        challengeCode: photo['challengeCode']?.toString() ?? challenge,
        timestamp:
            DateTime.tryParse(photo['timestamp']?.toString() ?? '') ??
            DateTime.now(),
      );
    }).toList();
    if (photos.isEmpty) {
      for (var i = 1; i <= 3; i++) {
        photos.add(
          ReturnInspectionPhoto(
            angleKey: 'angle_$i',
            angleTitle: 'ภาพตรวจสภาพ $i',
            challengeCode: challenge,
            timestamp: DateTime.now(),
          ),
        );
      }
    }
    var image = item['item_image_url'];
    if (image is String && image.startsWith('[')) {
      try {
        image = jsonDecode(image);
      } catch (_) {}
    }
    final checklist = Map<String, dynamic>.from(
      returnState['checklist'] as Map? ?? {},
    );
    return RentalReturnSession(
      rentalId: rentalId,
      itemId:
          (item['id'] as num?)?.toInt() ?? (booking['item_id'] as num?)?.toInt(),
      itemName: item['item_name']?.toString() ?? 'อุปกรณ์เช่า',
      itemImageUrl: image is List
          ? image.firstOrNull?.toString() ?? ''
          : image?.toString() ?? '',
      category: item['category']?.toString() ?? 'ทั่วไป',
      renterId: booking['user_id']?.toString() ?? '',
      renterName: data['renter_name']?.toString() ?? 'ผู้เช่า',
      lenderId: data['owner_id']?.toString() ?? '',
      lenderName: data['owner_name']?.toString() ?? 'ผู้ปล่อยเช่า',
      lenderPhone: '',
      startAt: DateTime.parse(booking['start_at'].toString()).toLocal(),
      endAt: DateTime.parse(booking['end_at'].toString()).toLocal(),
      pickupLocation: booking['pickup_location']?.toString() ?? '',
      totalPrice: (booking['total_price'] as num?)?.toDouble() ?? 0,
      depositAmount: 0,
      step: switch (status) {
        'completed' => RentalReturnStep.completed,
        'awaiting_return' => RentalReturnStep.lenderInspecting,
        'return_ready' => RentalReturnStep.merchantQrReady,
        _ => RentalReturnStep.inProgress,
      },
      dynamicChallengeCode: challenge,
      photos: photos,
      checklist: {
        'power_on': checklist['power_on'] == true,
        'no_new_cracks': checklist['no_new_cracks'] == true,
        'accessories_complete': checklist['accessories_complete'] == true,
      },
      isLenderConfirmed: status == 'return_ready' || status == 'completed',
    );
  }

  // ส่งรูปต้นฉบับพร้อมข้อมูลครั้งเดียว ให้ backend ตรวจสิทธิ์และเก็บหลักฐานก่อนเปลี่ยนสถานะ
  Future<void> submitVerification({
    required int rentalId,
    required List<ReturnInspectionPhoto> photos,
    required Map<String, bool> checklist,
  }) async {
    final files = <ApiUpload>[];
    for (final photo in photos) {
      if (photo.localPath == null || photo.localPath!.isEmpty)
        throw StateError('กรุณาถ่ายภาพตรวจสภาพให้ครบ');
      files.add(
        ApiUpload(
          fieldName: 'photos',
          bytes: await XFile(photo.localPath!).readAsBytes(),
          fileName: '${photo.angleKey}.jpg',
        ),
      );
    }
    _result(
      await _api.postMultipart(
        '/api/rentals/$rentalId/return-evidence',
        fields: {'checklist': jsonEncode(checklist)},
        files: files,
        headers: _headers,
      ),
    );
  }

  Future<Map<String, String>> generateMerchantToken(int rentalId) async {
    final result = _result(
      await _api.post(
        '/api/rentals/$rentalId/return-inspection',
        data: {'checked': true},
        headers: _headers,
      ),
    );
    return result.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> markCompleted(int rentalId, {required String tokenOrOtp}) async {
    _result(
      await _api.post(
        '/api/rentals/$rentalId/return',
        data: {'token_or_otp': tokenOrOtp.trim()},
        headers: _headers,
      ),
    );
  }

  Future<void> cancelRental({
    required int rentalId,
    required String reason,
    required String note,
    required List<XFile> photos,
  }) async {
    final files = <ApiUpload>[];
    for (final photo in photos) {
      files.add(
        ApiUpload(
          fieldName: 'photos',
          bytes: await photo.readAsBytes(),
          fileName: photo.name,
        ),
      );
    }
    _result(
      await _api.postMultipart(
        '/api/rentals/$rentalId/cancel',
        fields: {'reason': reason, 'note': note},
        files: files,
        headers: _headers,
      ),
    );
  }

  Future<String> uploadPhoto({
    required int rentalId,
    required String photoPath,
    required String angleKey,
  }) async {
    throw StateError('กรุณาส่งภาพทั้งหมดผ่านขั้นตอนตรวจสภาพการคืน');
  }
}

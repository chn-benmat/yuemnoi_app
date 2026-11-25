import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/models/pickup_location.dart';
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
    if (rentalId == null || rentalId <= 0) {
      throw StateError('กรุณาเลือกรายการเช่าที่ต้องการคืน');
    }
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
        angleTitle: photo['angleTitle']?.toString() ?? 'ภาพตรวจสภาพ',
        imageUrl: photo['imageUrl']?.toString(),
        challengeCode: photo['challengeCode']?.toString() ?? challenge,
        timestamp:
            DateTime.tryParse(photo['timestamp']?.toString() ?? '') ??
            DateTime.now(),
      );
    }).toList();
    var image = item['item_image_url'];
    if (image is String && image.startsWith('[')) {
      try {
        image = jsonDecode(image);
      } catch (_) {}
    }
    final bookingLocation = booking['pickup_location']?.toString().trim() ?? '';
    final itemLocation = item['pickup_location']?.toString().trim() ?? '';
    final location = bookingLocation.isEmpty ? itemLocation : bookingLocation;
    final bookingPoint = PickupLocation.fromJson({
      'pickup_location': location,
      'pickup_address': booking['pickup_address'],
      'pickup_note': booking['pickup_note'],
      'pickup_latitude': booking['latitude'],
      'pickup_longitude': booking['longitude'],
    });
    // ใช้หมุดจากประกาศกับรายการเก่าเมื่อเป็นสถานที่เดียวกับที่นัดไว้
    final returnPoint =
        bookingPoint ??
        (location == itemLocation ? PickupLocation.fromJson(item) : null);
    return RentalReturnSession(
      rentalId: rentalId,
      itemId:
          (item['id'] as num?)?.toInt() ??
          (booking['item_id'] as num?)?.toInt(),
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
      pickupLocation: location,
      returnPoint: returnPoint,
      totalPrice: (booking['total_price'] as num?)?.toDouble() ?? 0,
      depositAmount: 0,
      step: switch (status) {
        'completed' => RentalReturnStep.completed,
        'awaiting_return' ||
        'return_ready' => RentalReturnStep.lenderInspecting,
        _ => RentalReturnStep.inProgress,
      },
      photos: photos,
    );
  }

  Future<void> confirmReceipt(int rentalId) async {
    final result = _result(
      await _api.post(
        '/api/rentals/$rentalId/return-confirmation',
        data: {'checked': true},
        headers: _headers,
      ),
    );
    if (result['status'] != 'completed') {
      throw StateError('เซิร์ฟเวอร์ยังไม่ยืนยันว่าคืนอุปกรณ์สำเร็จ');
    }
  }

  Future<void> cancelRental({
    required int rentalId,
    required String reason,
    required String note,
    required List<XFile> photos,
  }) async {
    try {
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
    } on ApiClientException catch (error) {
      final message = switch (error.type) {
        ApiClientErrorType.timeout => 'การยกเลิกใช้เวลานานเกินไป กรุณาลองใหม่',
        ApiClientErrorType.connection =>
          'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
        ApiClientErrorType.invalidResponse =>
          'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง กรุณาลองใหม่',
      };
      throw StateError(message);
    }
  }
}

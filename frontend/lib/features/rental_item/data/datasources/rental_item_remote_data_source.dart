import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/rental_item.dart';
import '../models/rental_item_model.dart';

class RentalItemRemoteException implements Exception {
  const RentalItemRemoteException(this.message);

  final String message;
}

class RentalItemRemoteDataSource {
  RentalItemRemoteDataSource({ApiClient? client})
    : _client =
          client ?? DioApiClient(requestTimeout: const Duration(seconds: 45));

  static const _itemsPath = '/api/v1/items';
  final ApiClient _client;

  Future<RentalItem> create(RentalItemDraft draft) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const RentalItemRemoteException('กรุณาเข้าสู่ระบบก่อนเพิ่มอุปกรณ์');
    }

    try {
      final response = await _client.postMultipart(
        _itemsPath,
        fields: {
          'item_name': draft.name.trim(),
          'category': draft.category.trim(),
          'description': draft.description.trim(),
          'type': draft.rentalType,
          'price': draft.price.toString(),
        },
        files: draft.images
            .map(
              (image) => ApiUpload(
                fieldName: 'images',
                bytes: image.bytes,
                fileName: image.fileName,
              ),
            )
            .toList(growable: false),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 201) {
        try {
          return RentalItemModel.fromJson(response.data).toEntity();
        } on FormatException {
          throw const RentalItemRemoteException(
            'ข้อมูลอุปกรณ์ที่ได้รับไม่ถูกต้อง',
          );
        }
      }

      final serverMessage = response.data['error'];
      if (serverMessage is String && serverMessage.trim().isNotEmpty) {
        throw RentalItemRemoteException(serverMessage);
      }
      if (response.statusCode == 401) {
        throw const RentalItemRemoteException(
          'เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง',
        );
      }
      throw const RentalItemRemoteException(
        'เพิ่มอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่',
      );
    } on ApiClientException catch (error) {
      throw RentalItemRemoteException(switch (error.type) {
        ApiClientErrorType.timeout => 'อัปโหลดใช้เวลานานเกินไป กรุณาลองใหม่',
        ApiClientErrorType.connection => 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้',
        ApiClientErrorType.invalidResponse => 'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง',
      });
    }
  }

  void close() => _client.close();
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/rental_return/data/datasources/rental_return_remote_data_source.dart';
import 'package:frontend/features/rental_return/data/repositories/rental_return_repository_impl.dart';
import 'package:frontend/features/rental_return/domain/entities/rental_return_session.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements ApiClient {}

void main() {
  late _Api api;
  late RentalReturnRemoteDataSource source;
  setUp(() {
    api = _Api();
    source = RentalReturnRemoteDataSource(
      apiClient: api,
      accessToken: () => 'session-token',
    );
  });

  test(
    'completion sends user input to server and propagates invalid challenge',
    () async {
      when(
        () => api.post(
          '/api/rentals/73/return',
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async =>
            const ApiResponse(statusCode: 400, data: {'error': 'รหัสหมดอายุ'}),
      );
      final repository = RentalReturnRepositoryImpl(remoteDataSource: source);
      await expectLater(
        repository.completeReturnWithToken(rentalId: 73, tokenOrOtp: '123456'),
        throwsStateError,
      );
      verify(
        () => api.post(
          '/api/rentals/73/return',
          data: {'token_or_otp': '123456'},
          headers: {'Authorization': 'Bearer session-token'},
        ),
      ).called(1);
    },
  );

  test('owner inspection uses server-issued challenge and expiry', () async {
    when(
      () => api.post(
        '/api/rentals/73/return-inspection',
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {
          'token': 'server-qr',
          'otp': '654321',
          'expires_at': '2026-10-19T10:05:00Z',
        },
      ),
    );
    final challenge = await source.generateMerchantToken(73);
    expect(challenge['token'], 'server-qr');
    expect(challenge['otp'], '654321');
    verify(
      () => api.post(
        '/api/rentals/73/return-inspection',
        data: {'checked': true},
        headers: {'Authorization': 'Bearer session-token'},
      ),
    ).called(1);
  });

  test(
    'session uses canonical state and signed evidence without demo deposit',
    () async {
      when(
        () => api.get(
          '/api/rentals/73/return-session',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {
            'booking': {
              'id': 73,
              'user_id': 'renter',
              'status': 'return_ready',
              'start_at': '2026-10-19T01:00:00Z',
              'end_at': '2026-10-20T01:00:00Z',
              'total_price': 100,
            },
            'item': {
              'item_name': 'Camera',
              'item_image_url': ['https://example.test/item.jpg'],
            },
            'owner_id': 'owner',
            'owner_name': 'Owner',
            'renter_name': 'Renter',
            'return_state': {
              'photos': [
                {
                  'angleKey': 'angle_1',
                  'imageUrl': 'https://example.test/signed-evidence',
                  'timestamp': '2026-10-19T01:00:00Z',
                },
              ],
            },
          },
        ),
      );
      final session = await source.getSession(73);
      expect(session.step, RentalReturnStep.merchantQrReady);
      expect(
        session.photos.single.imageUrl,
        'https://example.test/signed-evidence',
      );
      expect(session.merchantOtp, isNull);
      expect(session.depositAmount, 0);
    },
  );

  test(
    'missing rental or session fails instead of creating mock success',
    () async {
      await expectLater(source.getSession(), throwsStateError);
      final signedOut = RentalReturnRemoteDataSource(
        apiClient: api,
        accessToken: () => null,
      );
      await expectLater(signedOut.getSession(73), throwsStateError);
      verifyZeroInteractions(api);
    },
  );

  test(
    'cancellation uploads actual image plus reason and propagates rejection',
    () async {
      final directory = await Directory.systemTemp.createTemp('rental-cancel');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/evidence.jpg');
      await file.writeAsBytes([1, 2, 3]);
      when(
        () => api.postMultipart(
          '/api/rentals/73/cancel',
          fields: any(named: 'fields'),
          files: any(named: 'files'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 409,
          data: {'error': 'รายการเริ่มเช่าแล้ว'},
        ),
      );
      await expectLater(
        source.cancelRental(
          rentalId: 73,
          reason: 'เครื่องเปิดไม่ติด',
          note: 'ตรวจตอนรับของ',
          photos: [XFile(file.path)],
        ),
        throwsStateError,
      );
      final captured = verify(
        () => api.postMultipart(
          '/api/rentals/73/cancel',
          fields: captureAny(named: 'fields'),
          files: captureAny(named: 'files'),
          headers: any(named: 'headers'),
        ),
      ).captured;
      expect(captured.first, {
        'reason': 'เครื่องเปิดไม่ติด',
        'note': 'ตรวจตอนรับของ',
      });
      final uploads = captured.last as List<ApiUpload>;
      expect(uploads.single.fieldName, 'photos');
      expect(uploads.single.bytes, [1, 2, 3]);
    },
  );
}

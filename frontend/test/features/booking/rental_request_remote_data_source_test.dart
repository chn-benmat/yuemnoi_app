import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/booking/data/datasources/rental_request_remote_data_source.dart';
import 'package:frontend/features/booking/domain/entities/rental_request.dart';
import 'package:mocktail/mocktail.dart';

class MockRentalApiClient extends Mock implements ApiClient {}

void main() {
  late MockRentalApiClient client;
  late RentalRequestRemoteDataSource source;

  setUp(() {
    client = MockRentalApiClient();
    source = RentalRequestRemoteDataSource(client: client);
    AuthSession.saveAccessToken('test-token');
  });
  tearDown(AuthSession.clear);

  test(
    'prepare and final confirmation use separate authenticated requests',
    () async {
      final draft = RentalRequestDraft(
        itemId: 7,
        startAt: DateTime.utc(2026, 10, 18, 2),
        endAt: DateTime.utc(2026, 10, 19, 2),
        rentalType: 'daily',
        pickupLocation: 'Pickup',
        offerMessageId: '11',
      );
      when(
        () => client.post(
          '/api/rentals',
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 201,
          data: {'id': 25, 'status': 'pending'},
        ),
      );
      when(
        () => client.post(
          '/api/rentals/25/confirm',
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {'id': 25, 'status': 'confirmed'},
        ),
      );
      expect(
        await source.submit(draft),
        const RentalRequestResult(id: 25, status: 'pending'),
      );
      verifyNever(
        () => client.post(
          '/api/rentals/25/confirm',
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      );
      expect(
        await source.confirm(
          rentalId: 25,
          offerMessageId: '11',
          paymentMethod: 'cash',
        ),
        const RentalRequestResult(id: 25, status: 'confirmed'),
      );
      verify(
        () => client.post(
          '/api/rentals/25/confirm',
          data: {'offer_message_id': '11', 'payment_method': 'cash'},
          headers: {'Authorization': 'Bearer test-token'},
        ),
      ).called(1);
    },
  );

  test(
    'confirmation requires a session and preserves server rejection',
    () async {
      AuthSession.clear();
      await expectLater(
        source.confirm(
          rentalId: 25,
          offerMessageId: '11',
          paymentMethod: 'cash',
        ),
        throwsA(isA<RentalRequestRemoteException>()),
      );
      verifyZeroInteractions(client);
      AuthSession.saveAccessToken('test-token');
      when(
        () => client.post(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 409,
          data: {'error': 'ข้อเสนอถูกแก้ไขแล้ว'},
        ),
      );
      await expectLater(
        source.confirm(
          rentalId: 25,
          offerMessageId: '11',
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<RentalRequestRemoteException>().having(
            (e) => e.message,
            'message',
            'ข้อเสนอถูกแก้ไขแล้ว',
          ),
        ),
      );
    },
  );
}

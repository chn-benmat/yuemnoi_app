import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/item_detail/data/datasources/item_detail_remote_data_source.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Api extends Mock implements ApiClient {}

class _Client extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

void main() {
  late _Api api;
  late ItemDetailRemoteDataSource source;
  setUp(() {
    api = _Api();
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    addTearDown(client.dispose);
    source = ItemDetailRemoteDataSource(client: client, apiClient: api);
    AuthSession.saveAccessToken('owner-token');
  });
  tearDown(AuthSession.clear);

  test(
    'basic info saves photos, description, and both rental prices together',
    () async {
      final client = _Client();
      final auth = _Auth();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(
        User(
          id: 'owner',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
      final scopedSource = ItemDetailRemoteDataSource(
        client: client,
        apiClient: api,
      );
      when(
        () => api.put(
          '/api/items/7',
          headers: any(named: 'headers'),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {'id': 7, 'user_id': 'owner'},
        ),
      );
      await scopedSource.update(
        ItemEditDraft(
          itemId: 7,
          name: 'Camera',
          category: 'กล้อง',
          description: 'Description',
          rentalType: 'รายชั่วโมง',
          price: 75,
          additionalDailyPrice: 410,
          retainedImageUrls: ['https://example.com/photo.jpg'],
          newImages: [],
        ),
      );
      verify(
        () => api.put(
          '/api/items/7',
          headers: {'Authorization': 'Bearer owner-token'},
          data: {
            'item_name': 'Camera',
            'category': 'กล้อง',
            'description': 'Description',
            'type': 'รายชั่วโมง',
            'price': 75,
            'daily_price': 410,
            'item_image_url': ['https://example.com/photo.jpg'],
          },
        ),
      ).called(1);
      verifyNever(() => api.get(any(), headers: any(named: 'headers')));
    },
  );

  test('unhide sends explicit false with owner bearer to Go only', () async {
    when(
      () => api.put(
        '/api/items/7',
        headers: any(named: 'headers'),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {'id': 7, 'user_id': 'owner', 'owner_hidden': false},
      ),
    );
    final item = await source.setVisibility(7, hidden: false);
    expect(item.ownerHidden, false);
    verify(
      () => api.put(
        '/api/items/7',
        headers: {'Authorization': 'Bearer owner-token'},
        data: {'owner_hidden': false},
      ),
    ).called(1);
  });

  test(
    'delete accepts only server success and preserves conflict message',
    () async {
      when(
        () => api.delete('/api/items/7', headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 409,
          data: {'error': 'อุปกรณ์มีประวัติการจอง'},
        ),
      );
      await expectLater(
        source.delete(7),
        throwsA(
          isA<ItemDetailRemoteException>().having(
            (e) => e.message,
            'message',
            'อุปกรณ์มีประวัติการจอง',
          ),
        ),
      );
      when(
        () => api.delete('/api/items/7', headers: any(named: 'headers')),
      ).thenAnswer((_) async => const ApiResponse(statusCode: 204, data: null));
      await source.delete(7);
      verify(
        () => api.delete(
          '/api/items/7',
          headers: {'Authorization': 'Bearer owner-token'},
        ),
      ).called(2);
    },
  );

  test('missing app session prevents both mutation requests', () async {
    AuthSession.clear();
    await expectLater(
      source.delete(7),
      throwsA(isA<ItemDetailRemoteException>()),
    );
    await expectLater(
      source.setVisibility(7, hidden: true),
      throwsA(isA<ItemDetailRemoteException>()),
    );
    verifyZeroInteractions(api);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/profile/data/datasources/user_items_remote_data_source.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  test('favorites retain the account name belonging to each item', () async {
    final api = _MockApiClient();
    for (final id in [11, 22]) {
      when(() => api.get('/api/items/$id')).thenAnswer(
        (_) async => ApiResponse(
          statusCode: 200,
          data: {
            'id': id,
            'user_id': 'owner-$id',
            'item_name': 'Item $id',
            'owner_name': 'Account $id',
          },
        ),
      );
    }
    when(
      () => api.get('/api/items/33'),
    ).thenAnswer((_) async => const ApiResponse(statusCode: 404, data: {}));
    final source = UserItemsRemoteDataSource(
      apiClient: api,
      getFavoriteIds: () async => [22, 33, 11],
    );

    final items = await source.getFavorites();

    expect(items.map((item) => item.id), [22, 11]);
    expect(items.map((item) => item.toEntity().ownerName), [
      'Account 22',
      'Account 11',
    ]);
  });

  test('API failures are reported instead of showing an empty list', () async {
    final api = _MockApiClient();
    when(
      () => api.get('/api/items/11'),
    ).thenAnswer((_) async => const ApiResponse(statusCode: 500, data: {}));
    final source = UserItemsRemoteDataSource(
      apiClient: api,
      getFavoriteIds: () async => [11],
    );
    await expectLater(
      source.getFavorites(),
      throwsA(isA<ApiClientException>()),
    );
  });
}

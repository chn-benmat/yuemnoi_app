import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/home/data/datasources/home_supabase_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this.response);

  ApiResponse response;
  Object? failure;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    if (failure case final error?) throw error;
    return response;
  }

  @override
  Future<ApiResponse> delete(String path, {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) => throw UnimplementedError();

  @override
  Future<Stream<String>> postStream(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) => throw UnimplementedError();

  @override
  Future<ApiResponse> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<ApiUpload> files = const [],
    Map<String, String>? headers,
  }) => throw UnimplementedError();

  @override
  Future<ApiResponse> put(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) => throw UnimplementedError();

  @override
  Future<ApiResponse> putMultipart(
    String path, {
    required Map<String, String> fields,
    List<ApiUpload> files = const [],
    Map<String, String>? headers,
  }) => throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('preserves backend rank and maps real review metrics', () async {
    final api = _FakeApiClient(
      const ApiResponse(
        statusCode: 200,
        data: [
          {
            'id': 29,
            'item_name': 'popular camera',
            'category': 'กล้อง',
            'price': 900,
            'rating': 4.8,
            'review_count': 12,
          },
          {
            'id': 8,
            'item_name': 'fresh audio',
            'category': 'เครื่องเสียง',
            'price': 500,
            'rating': 0,
            'review_count': 0,
          },
          {
            'id': 15,
            'item_name': 'game console',
            'category': 'เครื่องเล่นเกม',
            'price': 700,
            'rating': 4.2,
            'review_count': 3,
          },
        ],
      ),
    );
    final dataSource = HomeSupabaseDataSource(apiClient: api);

    final items = await dataSource.fetchNearbyItems();

    expect(items.map((item) => item.id), ['29', '8', '15']);
    expect(items.first.rating, 4.8);
    expect(items.first.reviewCount, 12);
    expect(items[1].rating, 0);
    expect(items[1].reviewCount, 0);

    final searched = await dataSource.fetchNearbyItems(searchQuery: 'fresh');
    expect(searched.map((item) => item.id), ['8']);
  });

  test('uses ranked local cache when backend is unavailable', () async {
    final api = _FakeApiClient(
      const ApiResponse(
        statusCode: 200,
        data: [
          {'id': 29, 'item_name': 'first', 'rating': 4.8, 'review_count': 2},
          {'id': 8, 'item_name': 'second', 'rating': 0, 'review_count': 0},
        ],
      ),
    );
    final dataSource = HomeSupabaseDataSource(apiClient: api);
    await dataSource.fetchNearbyItems();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    api.failure = const ApiClientException(ApiClientErrorType.connection);
    dataSource.clearMemoryCache();
    final cachedItems = await dataSource.fetchNearbyItems();

    expect(cachedItems.map((item) => item.id), ['29', '8']);
    expect(cachedItems.first.rating, 4.8);
  });

  test(
    'successful empty backend response does not restore stale cache',
    () async {
      final api = _FakeApiClient(
        const ApiResponse(
          statusCode: 200,
          data: [
            {'id': 29, 'item_name': 'stale item'},
          ],
        ),
      );
      final dataSource = HomeSupabaseDataSource(apiClient: api);
      await dataSource.fetchNearbyItems();

      api.response = const ApiResponse(statusCode: 200, data: []);
      dataSource.clearMemoryCache();
      final items = await dataSource.fetchNearbyItems();

      expect(items, isEmpty);
    },
  );
}

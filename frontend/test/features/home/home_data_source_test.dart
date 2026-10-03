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

  test('searches items with Thai title, description, category and synonyms', () async {
    final api = _FakeApiClient(
      const ApiResponse(
        statusCode: 200,
        data: [
          {
            'id': 1,
            'item_name': 'กล้อง Canon EOS R50',
            'description': 'กล้องมิเรอร์เลส เซนเซอร์ APS-C ถ่ายภาพ 4K คมชัด',
            'category': 'กล้องและอุปกรณ์ถ่ายภาพ',
            'price': 650,
          },
          {
            'id': 19,
            'item_name': 'เต็นท์ Coleman Instant Cabin 4 คน',
            'description': 'เต็นท์กันฝนและลมแรง กางและพับเก็บเสร็จใน 1 นาที เหมาะสำหรับแคมป์ปิ้ง',
            'category': 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
            'price': 450,
          },
          {
            'id': 16,
            'item_name': 'เครื่องดูดฝุ่นไร้สาย Dyson V12 Detect Slim',
            'description': 'หัวดูดเลเซอร์ตรวจจับฝุ่นละอองขนาดเล็ก พลังดูดสูง',
            'category': 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
            'price': 450,
          },
          {
            'id': 13,
            'item_name': 'สว่านกระแทกไร้สาย Bosch 18V',
            'description': 'สว่านแบตเตอรี่ไร้สายพร้อมชุดดอกเจาะปูน ไม้ เหล็ก',
            'category': 'เครื่องมือช่างและงานก่อสร้าง',
            'price': 250,
          },
        ],
      ),
    );
    final dataSource = HomeSupabaseDataSource(apiClient: api);

    // 1. ค้นหาด้วยชื่อภาษาไทย "กล้อง"
    final searchByTitle = await dataSource.fetchNearbyItems(searchQuery: 'กล้อง');
    expect(searchByTitle.map((i) => i.id), contains('1'));
    expect(searchByTitle.map((i) => i.id), isNot(contains('19')));

    // 2. ค้นหาด้วยคำที่อยู่ในคำอธิบาย (Description) "กันฝน"
    final searchByDesc = await dataSource.fetchNearbyItems(searchQuery: 'กันฝน');
    expect(searchByDesc.map((i) => i.id), ['19']);

    // 3. ค้นหาด้วยคำอธิบาย "เลเซอร์"
    final searchByDysonDesc = await dataSource.fetchNearbyItems(searchQuery: 'เลเซอร์');
    expect(searchByDysonDesc.map((i) => i.id), ['16']);

    // 4. ค้นหาด้วยชื่อหมวดหมู่ภาษาไทย "เครื่องมือช่าง"
    final searchByCategory = await dataSource.fetchNearbyItems(searchQuery: 'เครื่องมือช่าง');
    expect(searchByCategory.map((i) => i.id), ['13']);

    // 5. ค้นหาด้วยคำพ้อง/Synonyms ภาษาไทย เช่น "เต้นท์" (มีไม้โท)
    final searchBySynonym = await dataSource.fetchNearbyItems(searchQuery: 'เต้นท์');
    expect(searchBySynonym.map((i) => i.id), ['19']);

    // 6. ค้นหาหลายคำ (Multi-keyword) "กล้อง canon"
    final searchMulti = await dataSource.fetchNearbyItems(searchQuery: 'กล้อง canon');
    expect(searchMulti.map((i) => i.id), ['1']);
  });
}

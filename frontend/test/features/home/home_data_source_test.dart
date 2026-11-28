import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:frontend/core/cache/app_cache.dart';
import 'package:frontend/core/cache/cache_database.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/services/recommendation_location_service.dart';
import 'package:frontend/features/home/data/datasources/home_supabase_data_source.dart';
import 'package:frontend/features/home/data/repositories/home_repository_impl.dart';
import 'package:frontend/features/home/domain/usecases/rank_items_by_distance.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient implements ApiClient {
  _FakeApiClient(this.response);

  ApiResponse response;
  Object? failure;
  Future<ApiResponse> Function()? onGet;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    if (onGet != null) return onGet!();
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

class _MockSupabase extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

User _user(String id) => User(
  id: id,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final database = CacheDatabase(NativeDatabase.memory());
    AppCache.useDatabase(database);
    addTearDown(database.close);
  });

  test('receives feed changes after reconnecting and signing out', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final joins = StreamController<(WebSocket, List<dynamic>)>();
    final sockets = <WebSocket>[];
    final left = Completer<void>();
    var leaveCount = 0;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((message) {
        if (socket.readyState != WebSocket.open) return;
        final frame = jsonDecode(message as String) as List<dynamic>;
        socket.add(
          jsonEncode([
            frame[0],
            frame[1],
            frame[2],
            'phx_reply',
            {'status': 'ok', 'response': <String, dynamic>{}},
          ]),
        );
        if (frame[3] == 'phx_join') joins.add((socket, frame));
        if (frame[3] == 'phx_leave' && ++leaveCount == 2) left.complete();
      });
    });

    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'sb_publishable_test',
    );
    final source = HomeSupabaseDataSource(supabaseClient: client);
    final connection = StreamIterator(joins.stream);
    final changes = StreamIterator(source.watchFeedChanges());
    addTearDown(() async {
      await changes.cancel();
      await connection.cancel();
      await client.dispose();
      await Future.wait(sockets.map((socket) => socket.close()));
      await server.close(force: true);
      await joins.close();
    });

    final initialSync = changes.moveNext();
    expect(await connection.moveNext(), isTrue);
    final (socket, join) = connection.current;
    expect(join[2], 'realtime:home_feed');
    expect(join[4]['config']['private'], isTrue);
    expect(await initialSync, isTrue);

    final changed = changes.moveNext();
    socket.add(
      jsonEncode([
        join[0],
        null,
        join[2],
        'broadcast',
        {
          'type': 'broadcast',
          'event': 'feed_changed',
          'payload': <String, dynamic>{},
        },
      ]),
    );
    expect(await changed, isTrue);

    final reconnectSync = changes.moveNext();
    await socket.close();
    expect(await connection.moveNext(), isTrue);
    expect(await reconnectSync, isTrue);

    final signedOutSync = changes.moveNext();
    await client.auth.signOut();
    expect(
      await connection.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(await signedOutSync, isTrue);

    await changes.cancel();
    await left.future;
  });

  test(
    'successful empty Supabase response replaces a stale snapshot',
    () async {
      await AppCache.database.writeSnapshot('home', 'ranked_feed', 'guest', [
        {'id': 'stale', 'title': 'old item'},
      ]);
      final client = SupabaseClient(
        'https://example.test',
        'public-test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      final api = _FakeApiClient(
        const ApiResponse(statusCode: 503, data: null),
      );
      final source = HomeSupabaseDataSource(
        apiClient: api,
        supabaseClient: client,
      );
      expect(await source.fetchNearbyItems(), isEmpty);
      expect(
        await AppCache.database.readSnapshot('home', 'ranked_feed', 'guest'),
        isEmpty,
      );
    },
  );

  test('an offline feed request uses the stored feed snapshot', () async {
    final api = _FakeApiClient(const ApiResponse(statusCode: 200, data: []));
    final source = HomeSupabaseDataSource(apiClient: api);
    expect(await source.fetchNearbyItems(), isEmpty);
    api.failure = const ApiClientException(ApiClientErrorType.connection);
    source.clearMemoryCache();
    expect(await source.fetchNearbyItems(), isEmpty);
  });

  test(
    'retains occupied status in the feed and clears it on refresh',
    () async {
      final api = _FakeApiClient(
        const ApiResponse(
          statusCode: 200,
          data: [
            {'id': 1, 'item_name': 'Camera', 'is_rental_occupied': true},
          ],
        ),
      );
      final source = HomeSupabaseDataSource(apiClient: api);
      expect(
        (await source.fetchNearbyItems()).single.toJson(),
        containsPair('is_rental_occupied', true),
      );

      api.response = const ApiResponse(
        statusCode: 200,
        data: [
          {'id': 1, 'item_name': 'Camera', 'is_rental_occupied': false},
        ],
      );
      source.clearMemoryCache();
      expect(
        (await source.fetchNearbyItems()).single.toJson(),
        containsPair('is_rental_occupied', false),
      );
    },
  );

  test('the API rental count is retained in the offline feed', () async {
    final api = _FakeApiClient(
      const ApiResponse(
        statusCode: 200,
        data: [
          {'id': 1, 'item_name': 'Camera', 'paid_booking_count': 3},
        ],
      ),
    );
    final source = HomeSupabaseDataSource(apiClient: api);
    expect((await source.fetchNearbyItems()).single.paidBookingCount, 3);
    api.failure = const ApiClientException(ApiClientErrorType.connection);
    source.clearMemoryCache();
    expect((await source.fetchNearbyItems()).single.paidBookingCount, 3);
  });

  test(
    'a previous account location does not provide a feed distance',
    () async {
      final api = _FakeApiClient(
        const ApiResponse(
          statusCode: 200,
          data: [
            {'id': 'camera', 'item_name': 'Camera', 'distance_km': 1.8},
          ],
        ),
      );
      final source = HomeSupabaseDataSource(apiClient: api);
      expect((await source.fetchNearbyItems()).single.distanceKm, isNull);
    },
  );

  test('ranks pickup points from the permitted phone position', () async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var permission = LocationPermission.whileInUse;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'checkPermission' => permission.index,
        'isLocationServiceEnabled' => true,
        'getCurrentPosition' => {
          'latitude': 13.0,
          'longitude': 100.0,
          'timestamp': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          'accuracy': 100.0,
        },
        _ => throw StateError('Unexpected location method: ${call.method}'),
      };
    });
    final location = RecommendationLocationService.instance;
    addTearDown(() async {
      permission = LocationPermission.denied;
      await location.refresh();
      messenger.setMockMethodCallHandler(channel, null);
    });

    final client = SupabaseClient(
      'https://example.test',
      'public-test-key',
      httpClient: MockClient((request) async {
        final body = switch (request.url.path) {
          '/rest/v1/home_feed_ranked_v' =>
            '[{"id":1,"item_name":"Far"},{"id":2,"item_name":"Near","paid_booking_count":3},{"id":3,"item_name":"Unknown"}]',
          '/rest/v1/item_tb' =>
            '[{"id":1,"pickup_latitude":14,"pickup_longitude":100},'
                '{"id":2,"pickup_latitude":13.01,"pickup_longitude":100}]',
          _ => throw StateError('Unexpected request: ${request.url.path}'),
        };
        return http.Response(
          body,
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final repository = HomeRepositoryImpl(
      dataSource: HomeSupabaseDataSource(supabaseClient: client),
    );
    final items = await repository.getNearbyItems();

    await location.refresh();
    final nearby = rankItemsByDistance(items, location.position.value);
    expect(nearby.map((item) => item.id), ['2', '1', '3']);
    expect(nearby.map((item) => item.paidBookingCount), [3, 0, 0]);
    expect(nearby.first.distanceKm, closeTo(1.11, 0.02));
    expect(nearby.last.distanceKm, isNull);

    permission = LocationPermission.denied;
    await location.refresh();
    final ordinaryFeed = rankItemsByDistance(items, location.position.value);
    expect(ordinaryFeed.map((item) => item.id), ['1', '2', '3']);
    expect(ordinaryFeed.map((item) => item.distanceKm), everyElement(isNull));
  });

  test('search reads projected ranked listings beyond the first page', () async {
    final rankedQueries = <Map<String, String>>[];
    final profileFilters = <String>[];
    final rows = [
      for (var id = 1; id <= 101; id++)
        {
          'id': id,
          'user_id': 'owner-$id',
          'item_name': id == 101 ? 'แคมป์กันฝน' : 'Camera $id',
          'category': id == 101 ? 'แคมป์ปิง' : 'กล้อง',
          'pickup_location': 'กรุงเทพ',
          'rating': 4.8,
          'review_count': 2,
          'paid_booking_count': 3,
          'is_rental_occupied': true,
        },
    ];
    final client = SupabaseClient(
      'https://example.test',
      'public-test-key',
      httpClient: MockClient((request) async {
        final query = request.url.queryParameters;
        final List<Object> result;
        switch (request.url.path) {
          case '/rest/v1/home_feed_ranked_v':
            rankedQueries.add(query);
            final offset = int.tryParse(query['offset'] ?? '') ?? 0;
            final limit = int.tryParse(query['limit'] ?? '') ?? 100;
            result = rows.skip(offset).take(limit).toList();
          case '/rest/v1/item_tb':
            result = [];
          case '/rest/v1/public_profile_v':
            final owners = query['user_id']!;
            profileFilters.add(owners);
            result = owners.contains('"owner-101"')
                ? [
                    {
                      'user_id': 'owner-101',
                      'display_name': 'เจ้าของเต็นท์',
                      'is_verified': true,
                    },
                  ]
                : [];
          default:
            throw StateError('Unexpected request: ${request.url.path}');
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final source = HomeSupabaseDataSource(supabaseClient: client);

    final items = await source.fetchNearbyItems(
      searchQuery: 'กันฝน เจ้าของเต็นท์',
    );

    expect(items.single.id, '101');
    expect(items.single.locationName, 'กรุงเทพ');
    expect(items.single.rating, 4.8);
    expect(items.single.reviewCount, 2);
    expect(items.single.paidBookingCount, 3);
    expect(items.single.isRentalOccupied, isTrue);
    expect(items.single.isVerified, isTrue);
    expect(profileFilters.first.split(','), hasLength(100));
    expect(profileFilters.last, 'in.("owner-101")');
    expect(rankedQueries.map((query) => query['offset']), ['0', '100']);
    expect(rankedQueries.map((query) => query['limit']), everyElement('100'));
    expect(
      rankedQueries.map((query) => query['order']),
      everyElement('rank_position.asc.nullslast'),
    );
    expect(
      rankedQueries.first['select'],
      'id,user_id,item_name,item_image_url,description,category,price,type,'
      'pickup_location,is_rental_occupied,rating,review_count,paid_booking_count',
    );
  });

  test('an empty ranked view uses a projected visible-item page', () async {
    final itemQueries = <Map<String, String>>[];
    final client = SupabaseClient(
      'https://example.test',
      'public-test-key',
      httpClient: MockClient((request) async {
        final body = switch (request.url.path) {
          '/rest/v1/home_feed_ranked_v' => '[]',
          '/rest/v1/item_tb' => () {
            itemQueries.add(request.url.queryParameters);
            return '[{"id":7,"item_name":"Camera",'
                '"pickup_location":"กรุงเทพ","pickup_latitude":13.01,'
                '"pickup_longitude":100,"is_rental_occupied":true}]';
          }(),
          _ => throw StateError('Unexpected request: ${request.url.path}'),
        };
        return http.Response(
          body,
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final source = HomeSupabaseDataSource(supabaseClient: client);

    final item = (await source.fetchNearbyItems()).single;

    expect(item.id, '7');
    expect(item.pickupLatitude, 13.01);
    expect(item.isRentalOccupied, isTrue);
    final query = itemQueries.single;
    expect(
      query['select'],
      'id,user_id,item_name,item_image_url,description,category,price,type,'
      'pickup_location,is_rental_occupied,pickup_latitude,pickup_longitude',
    );
    expect(query['owner_hidden'], 'eq.false');
    expect(query['moderation_hidden'], 'eq.false');
    expect(query['status'], 'in.("available","พร้อมใช้งาน")');
    expect(query['order'], 'created_at.desc.nullslast,id.desc.nullslast');
    expect(query['offset'], '0');
    expect(query['limit'], '100');
  });

  test(
    'a cold feed reports a connection failure without sample listings',
    () async {
      final api = _FakeApiClient(const ApiResponse(statusCode: 200, data: []))
        ..failure = const ApiClientException(ApiClientErrorType.connection);
      final source = HomeSupabaseDataSource(apiClient: api);

      await expectLater(source.fetchCuratedItems(), throwsFormatException);
      await expectLater(source.fetchNearbyItems(), throwsFormatException);
    },
  );

  test(
    'a delayed request cannot publish the previous account into the next cache',
    () async {
      final client = _MockSupabase();
      final auth = _MockAuth();
      User current = _user('alice');
      when(() => client.auth).thenReturn(auth);
      when(() => auth.currentUser).thenAnswer((_) => current);
      final response = Completer<ApiResponse>();
      final started = Completer<void>();
      var calls = 0;
      final api = _FakeApiClient(const ApiResponse(statusCode: 200, data: []));
      api.onGet = () {
        if (++calls == 1) {
          started.complete();
          return response.future;
        }
        return Future.value(
          const ApiResponse(
            statusCode: 200,
            data: [
              {'id': 'bob-item', 'item_name': 'new account'},
            ],
          ),
        );
      };
      final source = HomeSupabaseDataSource(
        apiClient: api,
        supabaseClient: client,
      );
      final pending = source.fetchNearbyItems();
      await started.future;
      current = _user('bob');
      response.complete(
        const ApiResponse(
          statusCode: 200,
          data: [
            {'id': 'alice-item', 'item_name': 'old account'},
          ],
        ),
      );
      expect((await pending).single.id, 'bob-item');
      final cached = await AppCache.database.readSnapshot(
        'home',
        'ranked_feed',
        'bob',
      );
      expect(cached!.single['id'], 'bob-item');
      expect(
        await AppCache.database.readSnapshot('home', 'ranked_feed', 'alice'),
        isNull,
      );
    },
  );

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

  test(
    'background updates keep featured items, remove hidden items, and use fresh details',
    () async {
      final api = _FakeApiClient(
        ApiResponse(
          statusCode: 200,
          data: [
            for (var id = 1; id <= 6; id++) {'id': id, 'item_name': 'Item $id'},
          ],
        ),
      );
      final source = HomeSupabaseDataSource(apiClient: api);
      expect((await source.fetchCuratedItems()).map((item) => item.id), [
        '1',
        '2',
        '3',
        '4',
      ]);

      api.response = const ApiResponse(
        statusCode: 200,
        data: [
          {'id': 6, 'item_name': 'Item 6'},
          {'id': 3, 'item_name': 'Item 3 edited', 'is_rental_occupied': true},
          {'id': 5, 'item_name': 'Item 5'},
          {'id': 4, 'item_name': 'Item 4'},
          {'id': 2, 'item_name': 'Item 2'},
        ],
      );
      source.clearMemoryCache(rotateRecommendations: false);

      final featured = await source.fetchCuratedItems();
      expect(featured.map((item) => item.id), ['2', '3', '4', '6']);
      expect(featured[1].title, 'Item 3 edited');
      expect(featured[1].isRentalOccupied, isTrue);
      expect((await source.fetchNearbyItems()).map((item) => item.id), [
        '2',
        '3',
        '4',
        '6',
        '5',
      ]);
    },
  );

  test(
    'refresh rotates previously featured items out of the first four',
    () async {
      final api = _FakeApiClient(
        const ApiResponse(
          statusCode: 200,
          data: [
            {'id': 1, 'item_name': 'Item 1'},
            {'id': 2, 'item_name': 'Item 2'},
            {'id': 3, 'item_name': 'Item 3'},
            {'id': 4, 'item_name': 'Item 4'},
            {'id': 5, 'item_name': 'Item 5'},
            {'id': 6, 'item_name': 'Item 6'},
          ],
        ),
      );
      final dataSource = HomeSupabaseDataSource(apiClient: api);

      final firstLoad = await dataSource.fetchNearbyItems();
      expect(firstLoad.take(4).map((item) => item.id), ['1', '2', '3', '4']);

      dataSource.clearMemoryCache();
      final refreshed = await dataSource.fetchNearbyItems();
      expect(refreshed.take(4).map((item) => item.id), ['5', '6', '1', '2']);
      expect(
        refreshed
            .take(2)
            .map((item) => item.id)
            .toSet()
            .intersection(firstLoad.take(4).map((item) => item.id).toSet()),
        isEmpty,
      );
      expect(refreshed.take(4).every((item) => item.isCurated), isTrue);
      expect(refreshed.skip(4).every((item) => !item.isCurated), isTrue);

      final nextSession = await HomeSupabaseDataSource(
        apiClient: api,
      ).fetchNearbyItems();
      expect(nextSession.take(2).map((item) => item.id), ['4', '3']);
      expect(
        nextSession
            .take(2)
            .map((item) => item.id)
            .toSet()
            .intersection(refreshed.take(4).map((item) => item.id).toSet()),
        isEmpty,
      );
    },
  );

  test(
    'maps ownership for the current account and keeps it in cached items',
    () async {
      final client = _MockSupabase();
      final auth = _MockAuth();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(_user('alice'));
      final api = _FakeApiClient(
        const ApiResponse(
          statusCode: 200,
          data: [
            {'id': 7, 'item_name': 'My camera', 'user_id': 'alice'},
            {'id': 8, 'item_name': 'Other camera', 'user_id': 'bob'},
            {'id': 9, 'item_name': 'Unknown owner'},
          ],
        ),
      );
      final source = HomeSupabaseDataSource(
        apiClient: api,
        supabaseClient: client,
      );
      final items = await source.fetchNearbyItems();
      expect(items.map((item) => item.toJson()['is_owner']), [
        true,
        false,
        false,
      ]);

      api.failure = const ApiClientException(ApiClientErrorType.connection);
      source.clearMemoryCache();
      final cached = await source.fetchNearbyItems();
      expect(cached.map((item) => item.toJson()['is_owner']), [
        true,
        false,
        false,
      ]);
    },
  );

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

  test(
    'searches items with Thai title, description, category and synonyms',
    () async {
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
              'description':
                  'เต็นท์กันฝนและลมแรง กางและพับเก็บเสร็จใน 1 นาที เหมาะสำหรับแคมป์ปิ้ง',
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
      final searchByTitle = await dataSource.fetchNearbyItems(
        searchQuery: 'กล้อง',
      );
      expect(searchByTitle.map((i) => i.id), contains('1'));
      expect(searchByTitle.map((i) => i.id), isNot(contains('19')));

      // 2. ค้นหาด้วยคำที่อยู่ในคำอธิบาย (Description) "กันฝน"
      final searchByDesc = await dataSource.fetchNearbyItems(
        searchQuery: 'กันฝน',
      );
      expect(searchByDesc.map((i) => i.id), ['19']);

      // 3. ค้นหาด้วยคำอธิบาย "เลเซอร์"
      final searchByDysonDesc = await dataSource.fetchNearbyItems(
        searchQuery: 'เลเซอร์',
      );
      expect(searchByDysonDesc.map((i) => i.id), ['16']);

      // 4. ค้นหาด้วยชื่อหมวดหมู่ภาษาไทย "เครื่องมือช่าง"
      final searchByCategory = await dataSource.fetchNearbyItems(
        searchQuery: 'เครื่องมือช่าง',
      );
      expect(searchByCategory.map((i) => i.id), ['13']);

      // 5. ค้นหาด้วยคำพ้อง/Synonyms ภาษาไทย เช่น "เต้นท์" (มีไม้โท)
      final searchBySynonym = await dataSource.fetchNearbyItems(
        searchQuery: 'เต้นท์',
      );
      expect(searchBySynonym.map((i) => i.id), ['19']);

      // 6. ค้นหาหลายคำ (Multi-keyword) "กล้อง canon"
      final searchMulti = await dataSource.fetchNearbyItems(
        searchQuery: 'กล้อง canon',
      );
      expect(searchMulti.map((i) => i.id), ['1']);
    },
  );
}

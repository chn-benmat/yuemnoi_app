import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/cache/cache_database.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_session_validator.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/home/data/datasources/home_supabase_data_source.dart';
import 'package:frontend/features/home/data/repositories/home_repository_impl.dart';
import 'package:frontend/features/home/domain/usecases/get_home_feed_usecase.dart';
import 'package:frontend/features/home/presentation/bloc/home_bloc.dart';
import 'package:frontend/features/home/presentation/bloc/home_event.dart';
import 'package:frontend/features/home/presentation/bloc/home_state.dart';
import 'package:frontend/features/home/presentation/pages/home_feed_view.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

class _FeedApi extends Fake implements ApiClient {
  bool rankedAvailable = true;
  bool expiredCursor = false;
  Completer<ApiResponse>? nextPage;
  final requests = <Map<String, dynamic>>[];
  final tokens = <String?>[];

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async => ApiResponse(
    statusCode: 200,
    data: path == '/api/auth/session'
        ? {'user_id': 'feed-test-user'}
        : [_card(91)],
  );

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    expect(path, '/api/home/feed');
    requests.add(data!);
    tokens.add(headers?['Authorization']);
    if (!rankedAvailable) return const ApiResponse(statusCode: 404, data: null);
    if (data['cursor'] != null) {
      if (expiredCursor) return const ApiResponse(statusCode: 400, data: null);
      if (nextPage case final pending?) return pending.future;
    }
    return ApiResponse(
      statusCode: 200,
      data: switch (data['cursor']) {
        null => {
          'items': [
            for (final id in [21, 10, 15, 8, 25, 26, 27, 28])
              _card(id, distanceKm: data['latitude'] == null ? null : 2.0),
          ],
          'next_cursor': 'next-page',
        },
        'next-page' => {
          'items': [_card(28), _card(32), _card(31)],
          'next_cursor': null,
        },
        _ => throw StateError('Unexpected cursor'),
      },
    );
  }
}

Map<String, dynamic> _card(int id, {double? distanceKm}) => {
  'id': id,
  'item_name': 'Item $id',
  'category': 'camera',
  'price': 500,
  'type': 'daily',
  'rating': 4.5,
  'review_count': 2,
  'paid_booking_count': 3,
  'item_image_url': <String>[],
  'owner_name': 'Owner',
  'is_rental_occupied': id == 10,
  'pickup_location': 'Pickup $id',
  'pickup_latitude': 13.75,
  'pickup_longitude': 100.5,
  'distance_km': distanceKm ?? (id == 21 ? 12.5 : 1.0),
};

HomeBloc _startHome(
  _FeedApi api, {
  ValueNotifier<LatLng?>? position,
  Stream<void> feedChanges = const Stream.empty(),
}) {
  final db = CacheDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repository = HomeRepositoryImpl(
    dataSource: HomeSupabaseDataSource(apiClient: api, cacheDatabase: db),
  );
  final bloc = HomeBloc(
    homeRepository: repository,
    getHomeFeed: GetHomeFeedUseCase(repository),
    position: position,
    feedChanges: feedChanges,
  );
  addTearDown(bloc.close);
  bloc.add(const LoadHomeFeedStarted());
  return bloc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('consumes the API card fields in server order', () async {
    final bloc = _startHome(_FeedApi());
    final state =
        await bloc.stream.firstWhere((s) => s is HomeLoaded) as HomeLoaded;

    expect(state.nearbyItems.map((item) => item.id), [
      '21',
      '10',
      '15',
      '8',
      '25',
      '26',
      '27',
      '28',
    ]);
    expect(state.nearbyItems.first.distanceKm, 12.5);
    expect(state.nearbyItems.first.locationName, 'Pickup 21');
    expect(state.nearbyItems.first.pickupLatitude, 13.75);
    expect(state.nearbyItems[1].isRentalOccupied, isTrue);
  });

  test(
    'loads the existing catalog when the ranked endpoint is unavailable',
    () async {
      final api = _FeedApi()..rankedAvailable = false;
      final bloc = _startHome(api);
      final state =
          await bloc.stream.firstWhere((s) => s is HomeLoaded) as HomeLoaded;

      expect(api.requests, hasLength(1));
      expect(state.nearbyItems.map((item) => item.id), ['91']);
    },
  );

  test('reloads page one with coordinates that arrive after startup', () async {
    final position = ValueNotifier<LatLng?>(null);
    addTearDown(position.dispose);
    final api = _FeedApi();
    final bloc = _startHome(api, position: position);
    await bloc.stream.firstWhere((s) => s is HomeLoaded);

    final loaded = bloc.stream.firstWhere(
      (s) => s is HomeLoaded && s.nearbyItems.first.distanceKm == 2.0,
    );
    position.value = const LatLng(13.75, 100.5);
    await loaded;

    expect(api.requests, [
      {},
      {'latitude': 13.75, 'longitude': 100.5},
    ]);
  });

  test('refreshes once after the server rejects a cursor', () async {
    final api = _FeedApi()..expiredCursor = true;
    final bloc = _startHome(api);
    await bloc.stream.firstWhere((s) => s is HomeLoaded);

    final reloaded = bloc.stream
        .skipWhile((s) => s is! HomeLoaded || !s.isLoadingMore)
        .firstWhere((s) => s is HomeLoaded && !s.isLoadingMore);
    bloc.add(const LoadMoreHomeFeedRequested('next-page'));
    final state = await reloaded as HomeLoaded;

    expect(api.requests.map((request) => request['cursor']), [
      null,
      'next-page',
      null,
    ]);
    expect(state.nearbyItems.first.id, '21');
  });

  test(
    'drops old account interests and an in-flight page after sign out',
    () async {
      final api = _FeedApi();
      final session = Session.fromJson({
        'access_token': 'header.eyJleHAiOjQxMDI0NDQ4MDB9.signature',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'feed-test-user',
          'aud': 'authenticated',
          'created_at': '2026-10-17T00:00:00Z',
        },
      })!;
      await AuthSession.accept(
        session,
        validator: AppSessionValidator(client: api),
      );
      addTearDown(AuthSession.clear);
      final bloc = _startHome(api);
      await bloc.stream.firstWhere((s) => s is HomeLoaded);

      bloc.captureCategoryInterest()('camping');
      final refresh = bloc.stream
          .skipWhile((s) => s is! HomeLoaded || !s.isRefreshing)
          .firstWhere((s) => s is HomeLoaded && !s.isRefreshing);
      bloc.add(const RefreshHomeFeedRequested());
      await refresh;

      api.nextPage = Completer<ApiResponse>();
      final loadingMore = bloc.stream.firstWhere(
        (s) => s is HomeLoaded && s.isLoadingMore,
      );
      bloc.add(const LoadMoreHomeFeedRequested('next-page'));
      await loadingMore;

      final reloaded = bloc.stream
          .skipWhile((s) => s is! HomeLoading)
          .firstWhere((s) => s is HomeLoaded);
      AuthSession.clear();
      api.nextPage!.complete(
        ApiResponse(
          statusCode: 200,
          data: {
            'items': [_card(99)],
            'next_cursor': null,
          },
        ),
      );
      final guestFeed = await reloaded as HomeLoaded;

      expect(api.tokens, [
        for (var index = 0; index < 3; index++) 'Bearer ${session.accessToken}',
        null,
      ]);
      expect(api.requests[1]['recent_categories'], ['camping']);
      expect(api.requests.last, isEmpty);
      expect(
        guestFeed.nearbyItems.map((item) => item.id),
        isNot(contains('99')),
      );
    },
  );

  test('keeps appended pages visible on a passive catalog refresh', () async {
    final changes = StreamController<void>();
    addTearDown(changes.close);
    final api = _FeedApi();
    final bloc = _startHome(api, feedChanges: changes.stream);
    await bloc.stream.firstWhere((s) => s is HomeLoaded);

    final appended = bloc.stream.firstWhere(
      (s) => s is HomeLoaded && s.nearbyItems.length == 10,
    );
    bloc.add(const LoadMoreHomeFeedRequested('next-page'));
    await appended;
    changes.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(api.requests, hasLength(2));
    expect((bloc.state as HomeLoaded).nearbyItems.last.id, '31');
  });

  testWidgets('appends the next ranked page once near the bottom', (
    tester,
  ) async {
    final api = _FeedApi();
    final bloc = (await tester.runAsync(() async {
      final bloc = _startHome(api);
      await bloc.stream.firstWhere((state) => state is HomeLoaded);
      return bloc;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const HomeFeedView()),
      ),
    );
    await tester.pumpAndSettle();

    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.runAsync(() async {
      final appended = bloc.stream.firstWhere(
        (state) => state is HomeLoaded && state.nearbyItems.length == 10,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await appended.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();

    final state = bloc.state as HomeLoaded;
    expect(api.requests.map((request) => request['cursor']), [
      null,
      'next-page',
    ]);
    expect(state.nearbyItems.map((item) => item.id), [
      '21',
      '10',
      '15',
      '8',
      '25',
      '26',
      '27',
      '28',
      '32',
      '31',
    ]);
  });
}

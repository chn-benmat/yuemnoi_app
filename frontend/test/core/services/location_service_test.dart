import 'package:dio/dio.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/location_service.dart';

void main() {
  test('street fallback retains the approximate-address marker', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'name': 'ถนนพุดตานใน',
                  'display_name': 'ถนนพุดตานใน, ดุสิต, กรุงเทพมหานคร',
                  'latitude': 13.772,
                  'longitude': 100.513,
                  'is_approximate': true,
                },
              ],
            ),
          );
        },
      ),
    );
    final client = DioApiClient(dio: dio, appSecret: '');
    addTearDown(client.close);
    final results = await LocationService(
      apiClient: client,
    ).suggestLocations('719/259 พุดตาน');
    expect(results.single.isApproximate, isTrue);
    expect(results.single.name, 'ถนนพุดตานใน');
  });
  test(
    'suggestions use their own API instead of autocomplete on Nominatim search',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/api/locations/suggest');
            expect(options.queryParameters['q'], 'สวนเบญ');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {
                    'name': 'สวนเบญจกิติ',
                    'display_name': 'สวนเบญจกิติ, กรุงเทพมหานคร',
                    'latitude': 13.7292243,
                    'longitude': 100.5585211,
                  },
                ],
              ),
            );
          },
        ),
      );
      final client = DioApiClient(dio: dio, appSecret: '');
      addTearDown(client.close);
      final results = await LocationService(
        apiClient: client,
      ).suggestLocations('สวนเบญ');
      expect(results.single.name, 'สวนเบญจกิติ');
      expect(results.single.latitude, 13.7292243);
    },
  );
  for (final query in ['สวนเบญจกิติ', 'Benchakitti Park']) {
    test(
      'real place search preserves name/address/coordinates for $query',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.path, '/api/locations/search');
              expect(options.queryParameters['q'], query);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {
                      'name': 'สวนเบญจกิติ',
                      'display_name': 'สวนเบญจกิติ, เขตคลองเตย, กรุงเทพมหานคร',
                      'latitude': 13.7292243,
                      'longitude': 100.5585211,
                      'type': 'park',
                    },
                  ],
                ),
              );
            },
          ),
        );
        final client = DioApiClient(dio: dio, appSecret: '');
        addTearDown(client.close);
        final results = await LocationService(
          apiClient: client,
        ).searchLocations(query);
        expect(results, hasLength(1));
        expect(results.single.name, 'สวนเบญจกิติ');
        expect(results.single.displayName, contains('คลองเตย'));
        expect(results.single.latitude, 13.7292243);
        expect(results.single.longitude, 100.5585211);
      },
    );
  }
  test('empty upstream search does not substitute curated landmarks', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: []),
          );
        },
      ),
    );
    final client = DioApiClient(dio: dio, appSecret: '');
    addTearDown(client.close);
    expect(
      await LocationService(apiClient: client).searchLocations('สยาม'),
      isEmpty,
    );
  });
  test(
    'search service failure must not masquerade as no real places',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );
      await expectLater(
        LocationService(
          apiClient: DioApiClient(dio: dio, appSecret: ''),
        ).searchLocations('สวนเบญจกิติ'),
        throwsA(isA<ApiClientException>()),
      );
    },
  );
  test('Google Maps URL uses the selected coordinates without a place ID', () {
    final uri = LocationService.buildGoogleMapsUri(13.7115884, 100.4341077);

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['query'], '13.7115884,100.4341077');
    expect(uri.queryParameters, isNot(contains('query_place_id')));
  });

  test('interprets explicit coordinates and handles malformed map URLs', () {
    expect(
      LocationService.pinFromQuery(' 13.7467785, 100.534954 ')?.latitude,
      13.7467785,
    );
    expect(
      LocationService.pinFromQuery(
        'https://www.google.com/maps?q=13.7467785%2C100.534954',
      )?.longitude,
      100.534954,
    );
    expect(
      LocationService.pinFromQuery(
        'https://www.google.com/maps/search/?query=%FF',
      ),
      isNull,
    );
    expect(
      LocationService.pinFromQuery(
        'https://www.google.com/maps/@13.7467785,100.534954,17z',
      ),
      isNull,
    );
    expect(LocationService.pinFromQuery('13.7467785, 181'), isNull);
  });

  test(
    'reverse geocoding near a landmark uses the actual pinned coordinates',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/api/locations/reverse');
            expect(options.queryParameters, {'lat': 13.7118, 'lon': 100.4343});
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'name': 'ทางเข้าด้านข้าง',
                  'display_name': 'ทางเข้าด้านข้าง ถนนเพชรเกษม',
                  'latitude': 13.712,
                  'longitude': 100.434,
                },
              ),
            );
          },
        ),
      );
      final client = DioApiClient(dio: dio, appSecret: '');
      addTearDown(client.close);
      final result = await LocationService(
        apiClient: client,
      ).reverseGeocode(13.7118, 100.4343);
      expect(result?.name, 'ทางเข้าด้านข้าง');
      expect(result?.latitude, 13.7118);
      expect(result?.longitude, 100.4343);
    },
  );

  test('known locations resolve to their own landmark coordinates', () {
    for (final landmark in LocationService.popularLandmarks) {
      final coordinates = LocationService.resolveCoordinates(
        locationName: landmark.name,
      );

      expect(coordinates.latitude, landmark.latitude, reason: landmark.name);
      expect(coordinates.longitude, landmark.longitude, reason: landmark.name);
    }
  });

  test(
    'explicitly selected coordinates take precedence over landmark data',
    () {
      final coordinates = LocationService.resolveCoordinates(
        locationName: 'ซีคอน บางแค',
        latitude: 13.7001,
        longitude: 100.4001,
      );

      expect(coordinates.latitude, 13.7001);
      expect(coordinates.longitude, 100.4001);
    },
  );

  test('legacy Seacon Bangkae coordinates resolve to the corrected pin', () {
    final coordinates = LocationService.resolveCoordinates(
      locationName: 'ซีคอน บางแค',
      latitude: 13.7126,
      longitude: 100.4332,
    );

    expect(coordinates.latitude, 13.7115884);
    expect(coordinates.longitude, 100.4341077);
  });
}

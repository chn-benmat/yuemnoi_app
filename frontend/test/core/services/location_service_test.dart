import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/location_service.dart';

void main() {
  test('Google Maps URL uses the selected coordinates without a place ID', () {
    final uri = LocationService.buildGoogleMapsUri(13.7115884, 100.4341077);

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['query'], '13.7115884,100.4341077');
    expect(uri.queryParameters, isNot(contains('query_place_id')));
  });

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

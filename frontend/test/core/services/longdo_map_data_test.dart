import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';
import 'package:frontend/core/services/longdo_map_data.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test(
    'accepts valid Longdo places and ignores missing or invalid coordinates',
    () {
      final places = parseLongdoPlaces({
        'data': [
          {
            'name': ' Library ',
            'address': ' Bangkok ',
            'lat': '0',
            'lon': 100.5,
          },
          {
            'name': 'Station',
            'location': {'lat': 13.74, 'lon': 100.53},
          },
          {'name': 'Outside', 'lat': 0, 'lon': 181},
          {'name': 'Unknown', 'lat': 0},
          {'lat': 13, 'lon': 100},
        ],
      });
      expect(places.map((place) => place.name), ['Library', 'Station']);
      expect(places.first.address, 'Bangkok');
      expect(places.first.latitude, 0);
      expect(parseLongdoPlaces({'data': []}), isEmpty);
    },
  );

  test('reads latitude and longitude as one pair', () {
    expect(mapPoint('0', 100.5), const LatLng(0, 100.5));
    expect(mapPoint('NaN', 100), isNull);
    expect(mapPoint(13.7, null), isNull);
  });

  test(
    'uses the place covering the pin and preserves its exact coordinates',
    () {
      const pin = LatLng(13.7463, 100.5349);
      final place = parseLongdoPinAddress({
        'aoi': ' สยามพารากอน ',
        'subdistrict': 'แขวงปทุมวัน',
        'district': 'เขตปทุมวัน',
        'province': 'กรุงเทพมหานคร',
        'postcode': 10330,
      }, pin);
      expect(place?.name, 'สยามพารากอน');
      expect(place?.address, 'แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร 10330');
      expect(place?.latitude, pin.latitude);
      expect(place?.longitude, pin.longitude);
    },
  );

  test('uses the road for an unnamed pin and handles missing addresses', () {
    const pin = LatLng(13.7553, 100.5002);
    final place = parseLongdoPinAddress({
      'road': 'ตรอกศิลป์',
      'subdistrict': 'แขวงบวรนิเวศ',
      'province': 'กรุงเทพมหานคร',
    }, pin);
    expect(place?.name, 'ตรอกศิลป์');
    expect(place?.address, 'ตรอกศิลป์ แขวงบวรนิเวศ กรุงเทพมหานคร');
    expect(parseLongdoPinAddress({'geocode': '123'}, pin), isNull);
  });
}

import 'package:latlong2/latlong.dart';

import '../models/pickup_location.dart';

List<PickupLocation> parseLongdoPlaces(Object? payload) {
  final rows = payload is Map ? payload['data'] : payload;
  if (rows is! List)
    throw const FormatException('Invalid Longdo search result');

  final places = <PickupLocation>[];
  for (final row in rows.whereType<Map>()) {
    final location = row['location'];
    final coordinates = location is Map ? location : row;
    final point = mapPoint(coordinates['lat'], coordinates['lon']);
    final name = row['name'];
    if (point == null || name is! String || name.trim().isEmpty) continue;
    final address = row['address'];
    places.add(
      PickupLocation(
        name: name.trim(),
        address: address is String ? address.trim() : '',
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }
  return places;
}

PickupLocation? parseLongdoPinAddress(Object? payload, LatLng point) {
  final row = payload is Map && payload['data'] is Map
      ? payload['data']
      : payload;
  if (row is! Map) return null;

  String value(String key) => switch (row[key]) {
    final String text => text.trim(),
    final int postcode when key == 'postcode' => '$postcode',
    _ => '',
  };

  final area = [
    value('road'),
    value('subdistrict'),
    value('district'),
    value('province'),
  ].where((part) => part.isNotEmpty);
  final place = PickupLocation(
    name: [
      value('aoi'),
      value('name'),
      ...area,
      value('address'),
    ].firstWhere((part) => part.isNotEmpty, orElse: () => ''),
    address: value('address').isNotEmpty
        ? value('address')
        : {
            ...area,
            value('postcode'),
          }.where((part) => part.isNotEmpty).join(' '),
    latitude: point.latitude,
    longitude: point.longitude,
  );
  return place.isValid ? place : null;
}

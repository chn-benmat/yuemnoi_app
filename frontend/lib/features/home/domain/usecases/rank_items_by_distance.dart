import 'package:latlong2/latlong.dart';

import '../entities/feed_item.dart';

List<FeedItem> rankItemsByDistance(List<FeedItem> items, LatLng? position) {
  if (position == null) return items;

  const distance = DistanceHaversine(roundResult: false);
  final ranked = <({int index, FeedItem item})>[];
  for (final (index, item) in items.indexed) {
    final latitude = item.pickupLatitude;
    final longitude = item.pickupLongitude;
    final distanceKm =
        latitude != null &&
            latitude >= -90 &&
            latitude <= 90 &&
            longitude != null &&
            longitude >= -180 &&
            longitude <= 180
        ? distance.as(
            LengthUnit.Kilometer,
            position,
            LatLng(latitude, longitude),
          )
        : null;
    ranked.add((index: index, item: item.copyWith(distanceKm: distanceKm)));
  }
  ranked.sort((a, b) {
    final order = (a.item.distanceKm ?? double.infinity).compareTo(
      b.item.distanceKm ?? double.infinity,
    );
    return order == 0 ? a.index.compareTo(b.index) : order;
  });
  return ranked.map((entry) => entry.item).toList();
}

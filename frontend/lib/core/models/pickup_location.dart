import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

class PickupLocation extends Equatable {
  const PickupLocation({
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
  });

  final String name;
  final String address;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => _validCoordinates(latitude, longitude);

  static bool _validCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  bool get isValid =>
      name.trim().isNotEmpty && utf8.encode(name.trim()).length <= 500;

  static PickupLocation? fromJson(Map<String, dynamic> json) {
    final latitude = double.tryParse('${json['pickup_latitude']}');
    final longitude = double.tryParse('${json['pickup_longitude']}');
    final hasCoordinates = _validCoordinates(latitude, longitude);
    final value = PickupLocation(
      name: '${json['pickup_location'] ?? ''}',
      address: '${json['pickup_address'] ?? ''}',
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null,
    );
    return value.name.trim().isNotEmpty ? value : null;
  }

  Map<String, dynamic> toJson() => {
    'pickup_location': name.trim(),
    'pickup_address': address.trim(),
    if (hasCoordinates) 'pickup_latitude': latitude,
    if (hasCoordinates) 'pickup_longitude': longitude,
  };

  @override
  List<Object?> get props => [name, address, latitude, longitude];
}

LatLng? mapPoint(Object? latitude, Object? longitude) {
  final lat = double.tryParse('$latitude');
  final lon = double.tryParse('$longitude');
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 90 ||
      lon.abs() > 180) {
    return null;
  }
  return LatLng(lat, lon);
}

LatLng? matchingListingPoint(
  String? bookedName,
  String? listingName,
  LatLng? listingPoint,
) {
  final name = bookedName?.trim() ?? '';
  return name.isEmpty || name == listingName?.trim() ? listingPoint : null;
}

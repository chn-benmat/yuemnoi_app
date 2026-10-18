import 'package:equatable/equatable.dart';

class PickupLocation extends Equatable {
  const PickupLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.note = '',
  });

  final String name;
  final String address;
  final String note;
  final double latitude;
  final double longitude;

  bool get isValid =>
      name.trim().isNotEmpty &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static PickupLocation? fromJson(Map<String, dynamic> json) {
    final lat = double.tryParse('${json['pickup_latitude']}');
    final lng = double.tryParse('${json['pickup_longitude']}');
    if (lat == null || lng == null) return null;
    final value = PickupLocation(
      name: '${json['pickup_location'] ?? ''}',
      address: '${json['pickup_address'] ?? ''}',
      note: '${json['pickup_note'] ?? ''}',
      latitude: lat,
      longitude: lng,
    );
    return value.isValid ? value : null;
  }

  Map<String, dynamic> toJson() => {
    'pickup_location': name.trim(),
    'pickup_address': address.trim(),
    'pickup_note': note.trim(),
    'pickup_latitude': latitude,
    'pickup_longitude': longitude,
  };

  @override
  List<Object?> get props => [name, address, note, latitude, longitude];
}

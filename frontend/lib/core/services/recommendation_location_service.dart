import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class RecommendationLocationService {
  RecommendationLocationService._();

  static final instance = RecommendationLocationService._();

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final _position = ValueNotifier<LatLng?>(null);
  Future<void>? _refreshing;

  ValueListenable<LatLng?> get position => _position;

  Future<void> refresh({bool requestPermission = false}) =>
      _refreshing ??= _refresh(requestPermission).whenComplete(() {
        _refreshing = null;
      });

  Future<void> _refresh(bool requestPermission) async {
    if (!isSupported) {
      _position.value = null;
      return;
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (requestPermission && permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final isAllowed =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      if (!isAllowed || !await Geolocator.isLocationServiceEnabled()) {
        _position.value = null;
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _position.value = LatLng(position.latitude, position.longitude);
    } catch (_) {
      _position.value = null;
    }
  }
}

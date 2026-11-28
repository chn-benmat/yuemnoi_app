import 'package:geolocator/geolocator.dart';

Future<Position?> getMapDevicePosition({bool requestPermission = true}) async {
  var permission = await Geolocator.checkPermission();
  if (requestPermission && permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    return null;
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 10),
    ),
  );
}

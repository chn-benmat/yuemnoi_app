import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_client.dart';

/// ข้อมูลผลลัพธ์สถานที่จากการค้นหาหรือปักหมุด
class LocationSearchResult {
  final String name;
  final String displayName;
  final double latitude;
  final double longitude;
  final String? type;
  final bool isApproximate;
  final String? originalName;

  const LocationSearchResult({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.type,
    this.isApproximate = false,
    this.originalName,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  @override
  String toString() => '$name ($latitude, $longitude)';
}

/// ข้อมูลเส้นทางการเดินทางและระยะทาง
class DrivingRouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const DrivingRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// ระยะทางในรูปแบบที่อ่านง่าย เช่น "3.5 กม." หรือ "850 ม."
  String get formattedDistance {
    if (distanceMeters >= 1000) {
      final km = distanceMeters / 1000.0;
      return '${km.toStringAsFixed(1)} กม.';
    } else {
      return '${distanceMeters.toStringAsFixed(0)} ม.';
    }
  }

  /// เวลาเดินทางโดยประมาณ เช่น "15 นาที" หรือ "1 ชม. 20 นาที"
  String get formattedDuration {
    final totalMinutes = (durationSeconds / 60).round();
    if (totalMinutes < 1) {
      return '< 1 นาที';
    } else if (totalMinutes < 60) {
      return '$totalMinutes นาที';
    } else {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return mins > 0 ? '$hours ชม. $mins นาที' : '$hours ชม.';
    }
  }
}

/// บริการจัดการพิกัด แผนที่ และการค้นหาสถานที่
class LocationService {
  LocationService({ApiClient? apiClient})
    : _apiClient = apiClient ?? DioApiClient();
  static final LocationService instance = LocationService();
  Position? _lastPosition;
  final Map<String, ({LatLng start, DrivingRouteResult route, DateTime at})>
  _routeCache = {};

  DrivingRouteResult? cachedDrivingRoute(LatLng start, LatLng destination) {
    final entry =
        _routeCache['${destination.latitude},${destination.longitude}'];
    if (entry == null ||
        DateTime.now().difference(entry.at) > const Duration(minutes: 5) ||
        const Distance().as(LengthUnit.Meter, entry.start, start) > 100)
      return null;
    return entry.route;
  }

  Future<void> preloadDrivingRoute(LatLng destination) async {
    final last = await getLastKnownPosition();
    if (last == null) return;
    final start = LatLng(last.latitude, last.longitude);
    if (cachedDrivingRoute(start, destination) == null) {
      await fetchDrivingRoute(start, destination);
    }
  }

  Future<Position?> getLastKnownPosition() async {
    if (_lastPosition != null) return _lastPosition;
    try {
      // ป้องกันการรอไม่จบเมื่อบริการตำแหน่งของเครื่องค้าง
      return await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      return null;
    }
  }

  final ApiClient _apiClient;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'User-Agent': 'YuemnoiApp/1.0 (contact: info@yuemnoi.com)',
        'Accept-Language': 'th,en;q=0.9',
      },
    ),
  );

  /// พิกัดเริ่มต้น (กรุงเทพมหานคร / ซีคอน บางแค)
  static const LatLng defaultBangkokLocation = LatLng(13.7115884, 100.4341077);

  /// รายการสถานที่ยอดนิยมและจุดนัดรับอุปกรณ์ที่พบบ่อย (พร้อมพิกัดแม่นยำ)
  static const List<LocationSearchResult> popularLandmarks = [
    LocationSearchResult(
      name: 'ซีคอน บางแค',
      displayName: 'ถนนเพชรเกษม แขวงบางหว้า เขตภาษีเจริญ กรุงเทพมหานคร',
      latitude: 13.7115884,
      longitude: 100.4341077,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'สยามพารากอน (Siam Paragon)',
      displayName: '991 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร',
      latitude: 13.7467785,
      longitude: 100.5349540,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'เซ็นทรัล ลาดพร้าว (Central Ladprao)',
      displayName: '1693 ถนนพหลโยธิน แขวงจตุจักร เขตจตุจักร กรุงเทพมหานคร',
      latitude: 13.8168385,
      longitude: 100.5613613,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'ไอคอนสยาม (ICONSIAM)',
      displayName: '299 ถนนเจริญนคร แขวงคลองต้นไทร เขตคลองสาน กรุงเทพมหานคร',
      latitude: 13.7268227,
      longitude: 100.5102940,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'เซ็นทรัลเวิลด์ (Central World)',
      displayName: '999/9 ถนนพระรามที่ 1 แขวงปทุมวัน เขตปทุมวัน กรุงเทพมหานคร',
      latitude: 13.7465769,
      longitude: 100.5390414,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'เมกา บางนา (Mega Bangna)',
      displayName: '39 หมู่ 6 ถนนบางนา-ตราด ตำบลบางแก้ว อำเภอบางพลี สมุปราการ',
      latitude: 13.6470643,
      longitude: 100.6805081,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'ฟิวเจอร์พาร์ค รังสิต',
      displayName: '94 ถนนพหลโยธิน ตำบลประชาธิปัตย์ อำเภอธัญบุรี ปทุมธานี',
      latitude: 13.9889524,
      longitude: 100.6184404,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'เดอะมอลล์ บางแค',
      displayName: '518 ถนนเพชรเกษม แขวงบางแคเหนือ เขตบางแค กรุงเทพมหานคร',
      latitude: 13.7109713,
      longitude: 100.4080676,
      type: 'ห้างสรรพสินค้า',
    ),
    LocationSearchResult(
      name: 'BTS สยาม (CEN)',
      displayName: 'สถานีรถไฟฟ้า BTS สยาม ถนนพระรามที่ 1 กรุงเทพมหานคร',
      latitude: 13.7456249,
      longitude: 100.5342129,
      type: 'สถานีรถไฟฟ้า',
    ),
    LocationSearchResult(
      name: 'BTS หมอชิต / MRT สวนจตุจักร',
      displayName: 'สถานีหมอชิต/จตุจักร ถนนพหลโยธิน แขวงจตุจักร กรุงเทพมหานคร',
      latitude: 13.8027222,
      longitude: 100.5538887,
      type: 'สถานีรถไฟฟ้า',
    ),
    LocationSearchResult(
      name: 'BTS อโศก / MRT สุขุมวิท',
      displayName: 'สี่แยกอโศกมนตรี ถนนสุขุมวิท เขตวัฒนา กรุงเทพมหานคร',
      latitude: 13.7371261,
      longitude: 100.5602488,
      type: 'สถานีรถไฟฟ้า',
    ),
    LocationSearchResult(
      name: 'จุฬาลงกรณ์มหาวิทยาลัย',
      displayName: '254 ถนนพญาไท แขวงวังใหม่ เขตปทุมวัน กรุงเทพมหานคร',
      latitude: 13.7430893,
      longitude: 100.5328725,
      type: 'สถานศึกษา',
    ),
    LocationSearchResult(
      name: 'มหาวิทยาลัยเกษตรศาสตร์ (บางเขน)',
      displayName: '50 ถนนงามวงศ์วาน แขวงลาดยาว เขตจตุจักร กรุงเทพมหานคร',
      latitude: 13.8482589,
      longitude: 100.5675435,
      type: 'สถานศึกษา',
    ),
  ];

  static const Map<String, LatLng> _legacyPopularLandmarkCoordinates = {
    'ซีคอน บางแค': LatLng(13.7126, 100.4332),
    'สยามพารากอน (Siam Paragon)': LatLng(13.7460, 100.5349),
    'เซ็นทรัล ลาดพร้าว (Central Ladprao)': LatLng(13.8164, 100.5612),
    'ไอคอนสยาม (ICONSIAM)': LatLng(13.7267, 100.5108),
    'เซ็นทรัลเวิลด์ (Central World)': LatLng(13.7469, 100.5398),
    'เมกา บางนา (Mega Bangna)': LatLng(13.6468, 100.6806),
    'ฟิวเจอร์พาร์ค รังสิต': LatLng(13.9892, 100.6177),
    'เดอะมอลล์ บางแค': LatLng(13.7135, 100.4067),
    'BTS สยาม (CEN)': LatLng(13.7456, 100.5342),
    'BTS หมอชิต / MRT สวนจตุจักร': LatLng(13.8024, 100.5538),
    'BTS อโศก / MRT สุขุมวิท': LatLng(13.7371, 100.5604),
    'จุฬาลงกรณ์มหาวิทยาลัย': LatLng(13.7383, 100.5323),
    'มหาวิทยาลัยเกษตรศาสตร์ (บางเขน)': LatLng(13.8479, 100.5724),
  };

  static LatLng resolveCoordinates({
    required String locationName,
    double? latitude,
    double? longitude,
  }) {
    final normalizedName = locationName.trim().toLowerCase();
    LocationSearchResult? matchedLandmark;
    for (final landmark in popularLandmarks) {
      final normalizedLandmark = landmark.name.toLowerCase();
      if (normalizedName == normalizedLandmark ||
          normalizedName.contains(normalizedLandmark) ||
          normalizedLandmark.contains(normalizedName)) {
        matchedLandmark = landmark;
        break;
      }
    }

    if (latitude != null && longitude != null) {
      if (matchedLandmark != null) {
        final legacy = _legacyPopularLandmarkCoordinates[matchedLandmark.name];
        final usesLegacyCoordinates =
            legacy != null &&
            (latitude - legacy.latitude).abs() < 0.0000001 &&
            (longitude - legacy.longitude).abs() < 0.0000001;
        if (usesLegacyCoordinates) {
          return matchedLandmark.latLng;
        }
      }
      return LatLng(latitude, longitude);
    }

    if (matchedLandmark != null) {
      return matchedLandmark.latLng;
    }

    return defaultBangkokLocation;
  }

  /// ค้นหาสถานที่จริงเมื่อผู้ใช้กดค้นหา ผ่าน backend ที่รวมโควตาและแคช
  Future<List<LocationSearchResult>> searchLocations(String query) async {
    return _fetchPlaces('/api/locations/search', query);
  }

  Future<List<LocationSearchResult>> suggestLocations(String query) async {
    return _fetchPlaces('/api/locations/suggest', query);
  }

  Future<List<LocationSearchResult>> _fetchPlaces(
    String path,
    String query,
  ) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    final response = await _apiClient.get(
      path,
      queryParameters: {'q': cleanQuery},
    );
    if (response.statusCode != 200 || response.data is! List) {
      throw StateError('Location search unavailable (${response.statusCode})');
    }
    return (response.data as List).map(_parsePlace).toList();
  }

  static LocationSearchResult _parsePlace(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid place');
    }
    final lat = double.tryParse(value['latitude'].toString());
    final lon = double.tryParse(value['longitude'].toString());
    final name = value['name']?.toString().trim() ?? '';
    final address = value['display_name']?.toString().trim() ?? '';
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        name.isEmpty ||
        address.isEmpty) {
      throw const FormatException('Invalid place coordinates or address');
    }
    return LocationSearchResult(
      name: name,
      displayName: address,
      latitude: lat,
      longitude: lon,
      type: value['type']?.toString(),
      isApproximate: value['is_approximate'] == true,
      originalName: value['original_name']?.toString(),
    );
  }

  /// แปลงพิกัดที่ผู้ใช้เลือกผ่านโควตาเดียวกับการค้นหา
  Future<LocationSearchResult?> reverseGeocode(double lat, double lon) async {
    try {
      final response = await _apiClient.get(
        '/api/locations/reverse',
        queryParameters: {'lat': lat, 'lon': lon},
      );
      if (response.statusCode == 200) {
        final address = _parsePlace(response.data);
        // ผลค้นหาที่อยู่เป็นของสิ่งที่อยู่ใกล้ที่สุด พิกัดยังใช้จุดที่ผู้ใช้เลือก
        return LocationSearchResult(
          name: address.name,
          displayName: address.displayName,
          latitude: lat,
          longitude: lon,
          type: address.type,
          originalName: address.originalName,
        );
      }
    } catch (_) {
      // ยังยืนยันพิกัดที่เลือกได้เมื่อบริการที่อยู่ไม่พร้อม
    }
    return LocationSearchResult(
      name: 'พิกัดที่ปักหมุด',
      displayName: '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
      latitude: lat,
      longitude: lon,
    );
  }

  static final _coordinatePair = RegExp(
    r'^([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)$',
  );

  static LocationSearchResult? pinFromQuery(String query) {
    var text = query.trim();
    final uri = Uri.tryParse(text);
    if (uri != null &&
        uri.scheme == 'https' &&
        const {
          'www.google.com',
          'google.com',
          'maps.google.com',
        }.contains(uri.host) &&
        (uri.host == 'maps.google.com' ||
            uri.path == '/maps' ||
            uri.path.startsWith('/maps/'))) {
      // ใช้เฉพาะพิกัดหมุดในคำค้น ละเว้นตำแหน่งกล้องของแผนที่
      try {
        final parameters = uri.queryParameters;
        text = (parameters['query'] ?? parameters['q'] ?? '').trim();
      } on FormatException {
        return null;
      }
    }
    final match = _coordinatePair.firstMatch(text);
    if (match == null) return null;
    final lat = double.parse(match[1]!);
    final lon = double.parse(match[2]!);
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return LocationSearchResult(
      name: 'ปักหมุดตามพิกัด',
      displayName: '$lat, $lon',
      latitude: lat,
      longitude: lon,
    );
  }

  /// ดึงพิกัดตำแหน่งปัจจุบันของผู้ใช้จาก GPS
  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition = position;
      return position;
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return getLastKnownPosition();
    }
  }

  /// สตรีมติดตามตำแหน่งพิกัดแบบ Real-time เมื่อผู้ใช้เคลื่อนที่
  Stream<Position>? getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 3,
  }) {
    try {
      final locationSettings = LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
      return Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).map((position) {
        _lastPosition = position;
        return position;
      });
    } catch (e) {
      debugPrint('Error getting position stream: $e');
      return null;
    }
  }

  /// เปิดตำแหน่งในแอป Google Maps หรือเบราว์เซอร์ภายนอก
  static Uri buildGoogleMapsUri(double latitude, double longitude) =>
      _googleMapsSearchUri('$latitude,$longitude');

  static Uri _googleMapsSearchUri(String query) => Uri.https(
    'www.google.com',
    '/maps/search/',
    {'api': '1', 'query': query},
  );

  static Future<bool> openInExternalMaps(double latitude, double longitude) =>
      _openMapUri(buildGoogleMapsUri(latitude, longitude));

  static Future<bool> searchInExternalMaps(String query) =>
      _openMapUri(_googleMapsSearchUri(query.trim()));

  static Future<bool> _openMapUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Cannot launch map: $e');
      return false;
    }
  }

  /// ดึงข้อมูลเส้นทางการขับรถบนถนนจริงระหว่างสองพิกัด (ผ่าน OSRM)
  Future<DrivingRouteResult?> fetchDrivingRoute(
    LatLng start,
    LatLng destination,
  ) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson';

      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['code'] == 'Ok') {
          final routes = data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final firstRoute = routes[0] as Map<String, dynamic>;
            final distance =
                (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
            final duration =
                (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

            final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
            final coordinates = geometry?['coordinates'] as List?;

            final points = <LatLng>[];
            if (coordinates != null) {
              for (final coord in coordinates) {
                if (coord is List && coord.length >= 2) {
                  final lon = (coord[0] as num).toDouble();
                  final lat = (coord[1] as num).toDouble();
                  points.add(LatLng(lat, lon));
                }
              }
            }

            if (points.isNotEmpty) {
              final result = DrivingRouteResult(
                points: points,
                distanceMeters: distance,
                durationSeconds: duration,
              );
              if (_routeCache.length >= 8)
                _routeCache.remove(_routeCache.keys.first);
              _routeCache['${destination.latitude},${destination.longitude}'] =
                  (start: start, route: result, at: DateTime.now());
              return result;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching driving route from OSRM: $e');
    }

    // Fallback: ถ้า OSRM ติดต่อไม่ได้ ให้ลากเส้นตรงระหว่าง 2 จุดพร้อมคำนวณระยะทาง
    final distanceMeters = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      destination.latitude,
      destination.longitude,
    );
    // ประมาณความเร็วในเมือง 25 กม./ชม. = ~416 ม./นาที
    final estimatedSeconds = (distanceMeters / 416.0) * 60;

    return DrivingRouteResult(
      points: [start, destination],
      distanceMeters: distanceMeters,
      durationSeconds: estimatedSeconds,
    );
  }
}

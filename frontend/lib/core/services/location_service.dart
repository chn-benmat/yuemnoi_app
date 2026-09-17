import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// ข้อมูลผลลัพธ์สถานที่จากการค้นหาหรือปักหมุด
class LocationSearchResult {
  final String name;
  final String displayName;
  final double latitude;
  final double longitude;
  final String? type;

  const LocationSearchResult({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.type,
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
  LocationService._();
  static final LocationService instance = LocationService._();

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

  /// ค้นหาสถานที่ตามคำค้น (Search Geocoding)
  Future<List<LocationSearchResult>> searchLocations(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return popularLandmarks;

    // 1. ตรวจสอบกับรายการสถานที่ยอดนิยมที่มีก่อนเพื่อความรวดเร็ว
    final matchedLandmarks = popularLandmarks.where((item) {
      return item.name.toLowerCase().contains(cleanQuery.toLowerCase()) ||
          item.displayName.toLowerCase().contains(cleanQuery.toLowerCase());
    }).toList();

    // 2. ค้นหาจาก OpenStreetMap Nominatim API
    try {
      final response = await _dio.get<dynamic>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': cleanQuery,
          'format': 'json',
          'addressdetails': '1',
          'countrycodes': 'th',
          'limit': '10',
        },
      );

      final List<LocationSearchResult> apiResults = [];
      if (response.data is List) {
        for (final item in response.data as List) {
          if (item is Map<String, dynamic>) {
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat != null && lon != null) {
              final rawName = item['name']?.toString() ?? '';
              final displayName = item['display_name']?.toString() ?? '';
              final type = item['type']?.toString() ?? '';

              String title = rawName;
              if (title.isEmpty) {
                final parts = displayName.split(',');
                title = parts.isNotEmpty ? parts.first.trim() : displayName;
              }

              // ตรวจสอบไม่ให้ซ้ำกับ landmark ที่มีอยู่แล้ว
              final isDuplicate = matchedLandmarks.any(
                (l) =>
                    (l.latitude - lat).abs() < 0.0005 &&
                    (l.longitude - lon).abs() < 0.0005,
              );

              if (!isDuplicate) {
                apiResults.add(
                  LocationSearchResult(
                    name: title,
                    displayName: displayName,
                    latitude: lat,
                    longitude: lon,
                    type: type,
                  ),
                );
              }
            }
          }
        }
      }

      return [...matchedLandmarks, ...apiResults];
    } catch (e) {
      debugPrint('Error searching locations: $e');
      return matchedLandmarks;
    }
  }

  /// แปลงพิกัดเป็นชื่อสถานที่และที่อยู่ (Reverse Geocoding)
  Future<LocationSearchResult?> reverseGeocode(double lat, double lon) async {
    // 1. ตรวจสอบสถานที่ยอดนิยมที่มีพิกัดใกล้เคียงมาก่อน (< 100 เมตร)
    for (final landmark in popularLandmarks) {
      if ((landmark.latitude - lat).abs() < 0.001 &&
          (landmark.longitude - lon).abs() < 0.001) {
        return landmark;
      }
    }

    // 2. เรียก Nominatim Reverse API
    try {
      final response = await _dio.get<dynamic>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lon,
          'format': 'json',
          'addressdetails': '1',
          'accept-language': 'th,en',
        },
      );

      if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        final displayName = map['display_name']?.toString() ?? '';
        final address = map['address'] as Map<String, dynamic>?;

        String placeName = '';
        if (map['name'] != null && map['name'].toString().isNotEmpty) {
          placeName = map['name'].toString();
        } else if (address != null) {
          placeName =
              address['amenity']?.toString() ??
              address['shop']?.toString() ??
              address['building']?.toString() ??
              address['road']?.toString() ??
              address['neighbourhood']?.toString() ??
              address['suburb']?.toString() ??
              address['city_district']?.toString() ??
              '';
        }

        if (placeName.isEmpty) {
          final parts = displayName.split(',');
          placeName = parts.isNotEmpty ? parts.first.trim() : 'พิกัดที่เลือก';
        }

        return LocationSearchResult(
          name: placeName,
          displayName: displayName.isNotEmpty
              ? displayName
              : 'พิกัด: $lat, $lon',
          latitude: lat,
          longitude: lon,
        );
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
    }

    return LocationSearchResult(
      name: 'พิกัดที่ปักหมุด',
      displayName: '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
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

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('Error getting current position: $e');
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
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
      return Geolocator.getPositionStream(locationSettings: locationSettings);
    } catch (e) {
      debugPrint('Error getting position stream: $e');
      return null;
    }
  }

  /// เปิดตำแหน่งในแอป Google Maps หรือเบราว์เซอร์ภายนอก
  static Uri buildGoogleMapsUri(double latitude, double longitude) {
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
  }

  static Future<void> openInExternalMaps(
    double latitude,
    double longitude,
  ) async {
    final googleMapsUrl = buildGoogleMapsUri(latitude, longitude);

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(
          Uri.parse('https://maps.google.com/?q=$latitude,$longitude'),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('Cannot launch map: $e');
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
              return DrivingRouteResult(
                points: points,
                distanceMeters: distance,
                durationSeconds: duration,
              );
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

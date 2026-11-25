import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../network/supabase_client.dart';

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

  String? get _accountId {
    if (!SupabaseConfig.isInitialized) return null;
    final auth = SupabaseConfig.client.auth;
    final user = auth.currentUser;
    if (auth.currentSession?.isExpired != false ||
        user == null ||
        user.appMetadata['provider'] == 'anonymous' ||
        user.appMetadata['is_anonymous'] == true ||
        user.appMetadata['dashboard_only'] == true) {
      return null;
    }
    return user.id;
  }

  Future<String?> findSavedAccountLocationOwner() async {
    final userId = _accountId;
    if (userId == null) return null;
    final row = await SupabaseConfig.client
        .from('user_recommendation_locations')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : userId;
  }

  Future<void> deleteSavedAccountLocation(String userId) async {
    if (userId != _accountId) throw StateError('บัญชีเปลี่ยนระหว่างทำรายการ');
    await SupabaseConfig.client
        .from('user_recommendation_locations')
        .delete()
        .eq('user_id', userId);
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/supabase_client.dart';

class RecommendationLocation {
  const RecommendationLocation({
    required this.latitude,
    required this.longitude,
    required this.source,
    required this.label,
    required this.recommendationEnabled,
    required this.consentedAt,
    required this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final String source;
  final String? label;
  final bool recommendationEnabled;
  final DateTime? consentedAt;
  final DateTime? updatedAt;

  factory RecommendationLocation.fromJson(Map<String, dynamic> json) {
    return RecommendationLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      source: json['source']?.toString() ?? 'manual',
      label: json['location_label']?.toString(),
      recommendationEnabled: json['recommendation_enabled'] == true,
      consentedAt: DateTime.tryParse(json['consented_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}

class RecommendationLocationServiceException implements Exception {
  const RecommendationLocationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RecommendationLocationService {
  RecommendationLocationService._();
  static final RecommendationLocationService instance =
      RecommendationLocationService._();

  static const _onboardingKey = 'recommendation_location_prompted_v1';
  static const _pendingLatitudeKey = 'recommendation_location_pending_lat';
  static const _pendingLongitudeKey = 'recommendation_location_pending_lon';
  static const _pendingSourceKey = 'recommendation_location_pending_source';
  static const _pendingLabelKey = 'recommendation_location_pending_label';

  /// Notifies the home feed when the saved recommendation point changes.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<bool> get hasCompletedFirstRunPrompt async =>
      (await SharedPreferences.getInstance()).getBool(_onboardingKey) ?? false;

  Future<void> completeFirstRunPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  Future<void> savePendingForSignedInUser({
    required double latitude,
    required double longitude,
    required String source,
    required String label,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pendingLatitudeKey, latitude);
    await prefs.setDouble(_pendingLongitudeKey, longitude);
    await prefs.setString(_pendingSourceKey, source);
    await prefs.setString(_pendingLabelKey, label);
  }

  Future<void> syncPendingForSignedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    final latitude = prefs.getDouble(_pendingLatitudeKey);
    final longitude = prefs.getDouble(_pendingLongitudeKey);
    if (latitude == null || longitude == null) return;
    try {
      await save(
        latitude: latitude,
        longitude: longitude,
        source: prefs.getString(_pendingSourceKey) ?? 'gps',
        label: prefs.getString(_pendingLabelKey) ?? 'ตำแหน่งปัจจุบัน',
      );
      await clearPending();
    } catch (_) {
      // Keep consented coordinates locally and retry after the next sign-in.
    }
  }

  Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingLatitudeKey);
    await prefs.remove(_pendingLongitudeKey);
    await prefs.remove(_pendingSourceKey);
    await prefs.remove(_pendingLabelKey);
  }

  String get _userId {
    if (!SupabaseConfig.isInitialized) {
      throw const RecommendationLocationServiceException(
        'ยังเชื่อมต่อระบบบัญชีไม่ได้',
      );
    }
    final session = SupabaseConfig.client.auth.currentSession;
    final user = SupabaseConfig.client.auth.currentUser;
    if (session == null || session.isExpired || user == null) {
      throw const RecommendationLocationServiceException(
        'กรุณาเข้าสู่ระบบก่อนตั้งค่าตำแหน่ง',
      );
    }
    if (user.appMetadata['provider'] == 'anonymous' ||
        user.appMetadata['is_anonymous'] == true ||
        user.appMetadata['dashboard_only'] == true) {
      throw const RecommendationLocationServiceException(
        'บัญชีนี้ไม่สามารถบันทึกตำแหน่งแนะนำสินค้าได้',
      );
    }
    return user.id;
  }

  Future<RecommendationLocation?> load() async {
    final userId = _userId;
    final row = await SupabaseConfig.client
        .from('user_recommendation_locations')
        .select(
          'latitude,longitude,source,location_label,recommendation_enabled,consented_at,updated_at',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null || row['latitude'] == null || row['longitude'] == null) {
      return null;
    }
    return RecommendationLocation.fromJson(row);
  }

  Future<void> save({
    required double latitude,
    required double longitude,
    required String source,
    required String label,
  }) async {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw const RecommendationLocationServiceException(
        'ค่าละติจูดไม่ถูกต้อง',
      );
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw const RecommendationLocationServiceException(
        'ค่าลองจิจูดไม่ถูกต้อง',
      );
    }
    if (source != 'gps' && source != 'manual') {
      throw const RecommendationLocationServiceException(
        'แหล่งที่มาของตำแหน่งไม่ถูกต้อง',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final cleanedLabel = label.trim();
    await SupabaseConfig.client.from('user_recommendation_locations').upsert({
      'user_id': _userId,
      'latitude': latitude,
      'longitude': longitude,
      'source': source,
      'location_label': cleanedLabel.isEmpty
          ? 'ตำแหน่งที่เลือก'
          : cleanedLabel.length > 500
          ? cleanedLabel.substring(0, 500)
          : cleanedLabel,
      'recommendation_enabled': true,
      'consented_at': now,
      'updated_at': now,
    }, onConflict: 'user_id');
    changes.value++;
  }

  /// Turning this off removes the stored coordinates as well as disabling use.
  Future<void> clear() async {
    await SupabaseConfig.client
        .from('user_recommendation_locations')
        .delete()
        .eq('user_id', _userId);
    changes.value++;
  }
}

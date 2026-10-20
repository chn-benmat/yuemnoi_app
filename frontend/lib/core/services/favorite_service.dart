import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/supabase_client.dart';

class FavoriteServiceException implements Exception {
  const FavoriteServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteService {
  FavoriteService._();
  static final FavoriteService instance = FavoriteService._();

  final ValueNotifier<Set<int>> favoritesNotifier = ValueNotifier<Set<int>>({});

  String? _loadedOwner;
  Future<void>? _loading;
  String? _loadingOwner;

  String? get _authenticatedUserId {
    if (!SupabaseConfig.isInitialized) return null;
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null || session.isExpired) return null;
    final user = session.user;
    if (user.id.isEmpty ||
        user.appMetadata['provider'] == 'anonymous' ||
        user.appMetadata['is_anonymous'] == true ||
        user.appMetadata['dashboard_only'] == true) {
      return null;
    }
    return user.id;
  }

  bool get _hasUnusableSupabaseSession =>
      SupabaseConfig.isInitialized &&
      SupabaseConfig.client.auth.currentUser != null &&
      _authenticatedUserId == null;

  String get _ownerKey => _authenticatedUserId ?? 'guest';

  String _guestStorageKey() => 'favorite_item_ids_guest';

  String _accountCacheKey(String userId) => 'favorite_item_ids_cache_$userId';

  String _legacyAccountKey(String userId) => 'favorite_item_ids_$userId';

  Set<int> _parseIds(List<String>? values) =>
      (values ?? []).map(int.tryParse).whereType<int>().toSet();

  Future<Set<int>> _readLocalIds(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return _parseIds(prefs.getStringList(key));
  }

  Future<void> _saveLocalIds(String key, Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, ids.map((id) => '$id').toList());
  }

  void _publish(Set<int> ids, String owner) {
    if (_ownerKey != owner) return;
    favoritesNotifier.value = Set<int>.unmodifiable(ids);
    _loadedOwner = owner;
  }

  /// โหลด favorite ของบัญชีจาก Supabase หรือของ guest จากเครื่อง
  Future<void> init({bool forceRefresh = false}) async {
    final owner = _ownerKey;
    if (!forceRefresh && _loadedOwner == owner) return;
    if (_loadingOwner == owner && _loading != null) {
      await _loading;
      return;
    }

    final load = _loadOwner(owner);
    _loading = load;
    _loadingOwner = owner;
    try {
      await load;
    } finally {
      if (identical(_loading, load)) {
        _loading = null;
        _loadingOwner = null;
      }
    }
  }

  Future<void> _loadOwner(String owner) async {
    if (owner == 'guest') {
      try {
        _publish(await _readLocalIds(_guestStorageKey()), owner);
      } catch (_) {
        _publish({}, owner);
      }
      return;
    }

    final userId = owner;
    final cacheKey = _accountCacheKey(userId);
    final legacyKey = _legacyAccountKey(userId);
    Set<int> cached = {};
    Set<int> legacy = {};
    try {
      cached = await _readLocalIds(cacheKey);
      legacy = await _readLocalIds(legacyKey);
    } catch (_) {}
    if (_ownerKey == owner) {
      favoritesNotifier.value = Set<int>.unmodifiable(cached.union(legacy));
    }

    try {
      final rows = await SupabaseConfig.client
          .from('user_favorites')
          .select('item_id')
          .eq('user_id', userId);
      final remoteIds = rows
          .map((row) => int.tryParse(row['item_id'].toString()))
          .whereType<int>()
          .toSet();
      final idsToMigrate = legacy.difference(remoteIds);

      if (idsToMigrate.isNotEmpty) {
        await SupabaseConfig.client
            .from('user_favorites')
            .upsert(
              idsToMigrate
                  .map((itemId) => {'user_id': userId, 'item_id': itemId})
                  .toList(),
              onConflict: 'user_id,item_id',
              ignoreDuplicates: true,
            );
      }

      final merged = remoteIds.union(legacy);
      try {
        await _saveLocalIds(cacheKey, merged);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(legacyKey);
      } catch (_) {
        // การเขียน cache ไม่ควรทำให้ข้อมูลที่อ่านได้จาก server หายไป
      }
      _publish(merged, owner);
    } catch (error) {
      // ใช้ cache ในเครื่องเมื่อเครือข่ายขัดข้อง แล้ว sync ใหม่ครั้งถัดไป
      _publish(cached.union(legacy), owner);
      debugPrint('Favorite sync failed: $error');
    }
  }

  bool isItemFavorite(int itemId) => favoritesNotifier.value.contains(itemId);

  /// สลับ favorite โดยให้ server เป็นแหล่งข้อมูลหลักสำหรับบัญชีผู้ใช้
  Future<bool> toggleFavorite(int itemId) async {
    if (itemId <= 0) {
      throw ArgumentError.value(itemId, 'itemId', 'ต้องมากกว่า 0');
    }

    if (_hasUnusableSupabaseSession) {
      final dashboardOnly =
          SupabaseConfig
              .client
              .auth
              .currentUser
              ?.appMetadata['dashboard_only'] ==
          true;
      throw FavoriteServiceException(
        dashboardOnly
            ? 'บัญชีนี้ใช้ได้เฉพาะ Dashboard สำหรับเจ้าหน้าที่'
            : 'บันทึกรายการโปรดไม่ได้: เซสชันบัญชีไม่พร้อมใช้งาน กรุณาเข้าสู่ระบบใหม่',
      );
    }

    await init();
    final owner = _ownerKey;
    final userId = _authenticatedUserId;
    final current = Set<int>.from(favoritesNotifier.value);
    final isFavoriteNow = !current.contains(itemId);

    if (userId != null) {
      try {
        final table = SupabaseConfig.client.from('user_favorites');
        if (isFavoriteNow) {
          await table.upsert(
            {'user_id': userId, 'item_id': itemId},
            onConflict: 'user_id,item_id',
            ignoreDuplicates: true,
          );
        } else {
          await table.delete().eq('user_id', userId).eq('item_id', itemId);
        }
      } catch (error) {
        debugPrint('Favorite sync failed for $userId: $error');
        throw FavoriteServiceException('บันทึกรายการโปรดไม่สำเร็จ: $error');
      }

      if (isFavoriteNow) {
        await _recordEvent(
          userId: userId,
          itemId: itemId,
          eventType: 'favorite',
        );
      }
    }

    if (_ownerKey != owner) return isFavoriteNow;
    if (isFavoriteNow) {
      current.add(itemId);
    } else {
      current.remove(itemId);
    }
    favoritesNotifier.value = Set<int>.unmodifiable(current);

    try {
      final key = userId == null
          ? _guestStorageKey()
          : _accountCacheKey(userId);
      await _saveLocalIds(key, current);
    } catch (_) {
      // Favorite ที่บัญชีล็อกอินสำเร็จแล้วบน server ยังใช้ได้ แม้ cache เขียนไม่ได้
    }
    _loadedOwner = owner;
    return isFavoriteNow;
  }

  Future<List<int>> getFavoriteIds() async {
    await init();
    return favoritesNotifier.value.toList(growable: false);
  }

  /// บันทึกการเปิดหน้ารายละเอียดให้บัญชีที่ล็อกอินเพื่อใช้ประกอบคำแนะนำ
  Future<void> recordItemView(int itemId) async {
    if (itemId <= 0) return;
    final userId = _authenticatedUserId;
    if (userId == null) {
      if (_hasUnusableSupabaseSession) {
        debugPrint(
          'Skipped item view event: Supabase session is not valid for app usage',
        );
      }
      return;
    }
    await _recordEvent(userId: userId, itemId: itemId, eventType: 'view');
  }

  Future<void> _recordEvent({
    required String userId,
    required int itemId,
    required String eventType,
  }) async {
    try {
      await SupabaseConfig.client.from('user_item_events').insert({
        'user_id': userId,
        'item_id': itemId,
        'event_type': eventType,
      });
    } catch (error) {
      // Event ใช้ประกอบคำแนะนำ; ไม่ให้การบันทึก event ที่ล้มเหลวขัดขวาง UI
      debugPrint('Failed to record $eventType event for item $itemId: $error');
    }
  }
}

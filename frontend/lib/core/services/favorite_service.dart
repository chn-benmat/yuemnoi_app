import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/supabase_client.dart';

class FavoriteService {
  FavoriteService._();
  static final FavoriteService instance = FavoriteService._();

  final ValueNotifier<Set<int>> favoritesNotifier = ValueNotifier<Set<int>>({});

  bool _initialized = false;

  String _getKey() {
    final uid = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    return uid != null && uid.isNotEmpty
        ? 'favorite_item_ids_$uid'
        : 'favorite_item_ids_guest';
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_getKey()) ?? [];
      favoritesNotifier.value = list
          .map((e) => int.tryParse(e))
          .whereType<int>()
          .toSet();
      _initialized = true;
    } catch (_) {}
  }

  bool isItemFavorite(int itemId) {
    return favoritesNotifier.value.contains(itemId);
  }

  Future<bool> toggleFavorite(int itemId) async {
    if (!_initialized) await init();
    final current = Set<int>.from(favoritesNotifier.value);
    final isFavNow = !current.contains(itemId);
    if (isFavNow) {
      current.add(itemId);
    } else {
      current.remove(itemId);
    }
    favoritesNotifier.value = current;

    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = current.map((e) => e.toString()).toList();
      await prefs.setStringList(_getKey(), stringList);
    } catch (_) {}

    return isFavNow;
  }

  Future<List<int>> getFavoriteIds() async {
    if (!_initialized) await init();
    return favoritesNotifier.value.toList();
  }
}

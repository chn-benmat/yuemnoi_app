import 'package:flutter/foundation.dart';

import 'cache_database.dart';

abstract final class AppCache {
  static CacheDatabase _database = CacheDatabase();
  static CacheDatabase get database => _database;
  static final _memory =
      <(String, String, String), List<Map<String, dynamic>>>{};
  static final _scopeRevisions = <String, int>{};

  static int scopeRevision(String ownerId) => _scopeRevisions[ownerId] ?? 0;

  static List<Map<String, dynamic>>? readMemorySnapshot(
    String namespace,
    String key,
    String ownerId,
  ) => _memory[(namespace, key, ownerId)];

  static void rememberSnapshot(
    String namespace,
    String key,
    String ownerId,
    List<Map<String, dynamic>> rows,
  ) {
    _memory[(namespace, key, ownerId)] = List.unmodifiable(rows);
    if (_memory.length > 100) _memory.remove(_memory.keys.first);
  }

  @visibleForTesting
  static void useDatabase(CacheDatabase database) {
    _memory.clear();
    _database = database;
  }

  static Future<void> forgetUser(String userId) async {
    _scopeRevisions[userId] = scopeRevision(userId) + 1;
    _memory.removeWhere((key, _) => key.$3 == userId);
    try {
      await _database.deleteScope(userId);
    } catch (_) {
      // Cache ไม่ควรขัดขวางการออกจากระบบเมื่อพื้นที่เก็บข้อมูลใช้ไม่ได้
    }
  }
}

import 'package:flutter/foundation.dart';

import 'cache_database.dart';

abstract final class AppCache {
  static CacheDatabase _database = CacheDatabase();
  static CacheDatabase get database => _database;

  @visibleForTesting
  static void useDatabase(CacheDatabase database) => _database = database;

  static Future<void> forgetUser(String userId) async {
    try {
      await _database.deleteScope(userId);
    } catch (_) {
      // Cache ไม่ควรขัดขวางการออกจากระบบเมื่อพื้นที่เก็บข้อมูลใช้ไม่ได้
    }
  }
}

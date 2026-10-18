import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'cache_database.g.dart';

class CacheSnapshots extends Table {
  TextColumn get namespace => text()();
  TextColumn get cacheKey => text()();
  TextColumn get ownerId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {namespace, cacheKey, ownerId};
}

/// เก็บเฉพาะ snapshot จาก server แยกบัญชี จึงไม่เป็นคิวส่งธุรกรรมตอน offline
@DriftDatabase(tables: [CacheSnapshots])
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'yuemnoi_cache',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 1;

  Future<List<Map<String, dynamic>>?> readSnapshot(
    String namespace,
    String key,
    String ownerId,
  ) async {
    final entry =
        await (select(cacheSnapshots)..where(
              (row) =>
                  row.namespace.equals(namespace) &
                  row.cacheKey.equals(key) &
                  row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (entry == null) return null;
    final values = jsonDecode(entry.payload) as List;
    return values
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
  }

  Future<void> writeSnapshot(
    String namespace,
    String key,
    String ownerId,
    List<Map<String, dynamic>> values,
  ) => into(cacheSnapshots)
      .insertOnConflictUpdate(
        CacheSnapshotsCompanion.insert(
          namespace: namespace,
          cacheKey: key,
          ownerId: ownerId,
          payload: jsonEncode(values),
          updatedAt: DateTime.now().toUtc(),
        ),
      )
      .then((_) {});

  Future<void> deleteScope(String ownerId, {String? namespace}) async {
    await (delete(cacheSnapshots)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              (namespace == null
                  ? const Constant(true)
                  : row.namespace.equals(namespace)),
        ))
        .go();
  }
}

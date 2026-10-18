// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $CacheSnapshotsTable extends CacheSnapshots
    with TableInfo<$CacheSnapshotsTable, CacheSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _namespaceMeta = const VerificationMeta(
    'namespace',
  );
  @override
  late final GeneratedColumn<String> namespace = GeneratedColumn<String>(
    'namespace',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    namespace,
    cacheKey,
    ownerId,
    payload,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('namespace')) {
      context.handle(
        _namespaceMeta,
        namespace.isAcceptableOrUnknown(data['namespace']!, _namespaceMeta),
      );
    } else if (isInserting) {
      context.missing(_namespaceMeta);
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {namespace, cacheKey, ownerId};
  @override
  CacheSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheSnapshot(
      namespace: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}namespace'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CacheSnapshotsTable createAlias(String alias) {
    return $CacheSnapshotsTable(attachedDatabase, alias);
  }
}

class CacheSnapshot extends DataClass implements Insertable<CacheSnapshot> {
  final String namespace;
  final String cacheKey;
  final String ownerId;
  final String payload;
  final DateTime updatedAt;
  const CacheSnapshot({
    required this.namespace,
    required this.cacheKey,
    required this.ownerId,
    required this.payload,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['namespace'] = Variable<String>(namespace);
    map['cache_key'] = Variable<String>(cacheKey);
    map['owner_id'] = Variable<String>(ownerId);
    map['payload'] = Variable<String>(payload);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CacheSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return CacheSnapshotsCompanion(
      namespace: Value(namespace),
      cacheKey: Value(cacheKey),
      ownerId: Value(ownerId),
      payload: Value(payload),
      updatedAt: Value(updatedAt),
    );
  }

  factory CacheSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheSnapshot(
      namespace: serializer.fromJson<String>(json['namespace']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      payload: serializer.fromJson<String>(json['payload']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'namespace': serializer.toJson<String>(namespace),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'ownerId': serializer.toJson<String>(ownerId),
      'payload': serializer.toJson<String>(payload),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CacheSnapshot copyWith({
    String? namespace,
    String? cacheKey,
    String? ownerId,
    String? payload,
    DateTime? updatedAt,
  }) => CacheSnapshot(
    namespace: namespace ?? this.namespace,
    cacheKey: cacheKey ?? this.cacheKey,
    ownerId: ownerId ?? this.ownerId,
    payload: payload ?? this.payload,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CacheSnapshot copyWithCompanion(CacheSnapshotsCompanion data) {
    return CacheSnapshot(
      namespace: data.namespace.present ? data.namespace.value : this.namespace,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      payload: data.payload.present ? data.payload.value : this.payload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheSnapshot(')
          ..write('namespace: $namespace, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('ownerId: $ownerId, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(namespace, cacheKey, ownerId, payload, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheSnapshot &&
          other.namespace == this.namespace &&
          other.cacheKey == this.cacheKey &&
          other.ownerId == this.ownerId &&
          other.payload == this.payload &&
          other.updatedAt == this.updatedAt);
}

class CacheSnapshotsCompanion extends UpdateCompanion<CacheSnapshot> {
  final Value<String> namespace;
  final Value<String> cacheKey;
  final Value<String> ownerId;
  final Value<String> payload;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CacheSnapshotsCompanion({
    this.namespace = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.payload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheSnapshotsCompanion.insert({
    required String namespace,
    required String cacheKey,
    required String ownerId,
    required String payload,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : namespace = Value(namespace),
       cacheKey = Value(cacheKey),
       ownerId = Value(ownerId),
       payload = Value(payload),
       updatedAt = Value(updatedAt);
  static Insertable<CacheSnapshot> custom({
    Expression<String>? namespace,
    Expression<String>? cacheKey,
    Expression<String>? ownerId,
    Expression<String>? payload,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (namespace != null) 'namespace': namespace,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (ownerId != null) 'owner_id': ownerId,
      if (payload != null) 'payload': payload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheSnapshotsCompanion copyWith({
    Value<String>? namespace,
    Value<String>? cacheKey,
    Value<String>? ownerId,
    Value<String>? payload,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CacheSnapshotsCompanion(
      namespace: namespace ?? this.namespace,
      cacheKey: cacheKey ?? this.cacheKey,
      ownerId: ownerId ?? this.ownerId,
      payload: payload ?? this.payload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (namespace.present) {
      map['namespace'] = Variable<String>(namespace.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheSnapshotsCompanion(')
          ..write('namespace: $namespace, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('ownerId: $ownerId, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $CacheSnapshotsTable cacheSnapshots = $CacheSnapshotsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cacheSnapshots];
}

typedef $$CacheSnapshotsTableCreateCompanionBuilder =
    CacheSnapshotsCompanion Function({
      required String namespace,
      required String cacheKey,
      required String ownerId,
      required String payload,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CacheSnapshotsTableUpdateCompanionBuilder =
    CacheSnapshotsCompanion Function({
      Value<String> namespace,
      Value<String> cacheKey,
      Value<String> ownerId,
      Value<String> payload,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CacheSnapshotsTableFilterComposer
    extends Composer<_$CacheDatabase, $CacheSnapshotsTable> {
  $$CacheSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheSnapshotsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CacheSnapshotsTable> {
  $$CacheSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheSnapshotsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CacheSnapshotsTable> {
  $$CacheSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get namespace =>
      $composableBuilder(column: $table.namespace, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CacheSnapshotsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CacheSnapshotsTable,
          CacheSnapshot,
          $$CacheSnapshotsTableFilterComposer,
          $$CacheSnapshotsTableOrderingComposer,
          $$CacheSnapshotsTableAnnotationComposer,
          $$CacheSnapshotsTableCreateCompanionBuilder,
          $$CacheSnapshotsTableUpdateCompanionBuilder,
          (
            CacheSnapshot,
            BaseReferences<
              _$CacheDatabase,
              $CacheSnapshotsTable,
              CacheSnapshot
            >,
          ),
          CacheSnapshot,
          PrefetchHooks Function()
        > {
  $$CacheSnapshotsTableTableManager(
    _$CacheDatabase db,
    $CacheSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> namespace = const Value.absent(),
                Value<String> cacheKey = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheSnapshotsCompanion(
                namespace: namespace,
                cacheKey: cacheKey,
                ownerId: ownerId,
                payload: payload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String namespace,
                required String cacheKey,
                required String ownerId,
                required String payload,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheSnapshotsCompanion.insert(
                namespace: namespace,
                cacheKey: cacheKey,
                ownerId: ownerId,
                payload: payload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheSnapshotsTable, CacheSnapshot>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $CacheSnapshotsTable,
                    CacheSnapshot
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CacheSnapshotsTable,
      CacheSnapshot,
      $$CacheSnapshotsTableFilterComposer,
      $$CacheSnapshotsTableOrderingComposer,
      $$CacheSnapshotsTableAnnotationComposer,
      $$CacheSnapshotsTableCreateCompanionBuilder,
      $$CacheSnapshotsTableUpdateCompanionBuilder,
      (
        CacheSnapshot,
        BaseReferences<_$CacheDatabase, $CacheSnapshotsTable, CacheSnapshot>,
      ),
      CacheSnapshot,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$CacheSnapshotsTableTableManager get cacheSnapshots =>
      $$CacheSnapshotsTableTableManager(_db, _db.cacheSnapshots);
}

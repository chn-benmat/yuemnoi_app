import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/cache/cache_database.dart';
import 'package:frontend/core/cache/app_cache.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _DelayedCacheDatabase extends Mock implements CacheDatabase {}

void main() {
  late CacheDatabase database;
  setUp(() => database = CacheDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('confirmed messages survive reopening the SQLite database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yuemnoi-cache-test-',
    );
    final file = File('${directory.path}/cache.sqlite');
    final first = CacheDatabase(NativeDatabase(file));
    await first.writeSnapshot('chat', 'room', 'alice', [
      {'id': 'saved'},
    ]);
    await first.close();
    final reopened = CacheDatabase(NativeDatabase(file));
    expect(await reopened.readSnapshot('chat', 'room', 'alice'), [
      {'id': 'saved'},
    ]);
    await reopened.close();
    await directory.delete(recursive: true);
  });

  test(
    'restores chat history for the owning account with correct isMine',
    () async {
      AppCache.useDatabase(database);
      await database.writeSnapshot('chat', 'room', 'alice', [
        {
          'id': 'message-1',
          'sender_id': 'alice',
          'conversation_id': 'room',
          'message': 'saved text',
          'created_at': '2026-10-18T00:00:00Z',
        },
      ]);
      final restored = await ChatMessagesCache.loadFromDisk(
        'room',
        currentUserId: 'alice',
      );
      expect(restored!.single.message, 'saved text');
      expect(restored.single.isMine, isTrue);
      expect(
        ChatMessagesCache.peek('room', currentUserId: 'alice')!.single.message,
        'saved text',
      );
      expect(ChatMessagesCache.peek('room', currentUserId: 'bob'), isNull);
      await AppCache.forgetUser('alice');
      expect(ChatMessagesCache.peek('room', currentUserId: 'alice'), isNull);
      expect(
        await ChatMessagesCache.loadFromDisk('room', currentUserId: 'bob'),
        isNull,
      );
      expect(
        await ChatMessagesCache.loadFromDisk('room', currentUserId: ''),
        isNull,
      );
    },
  );

  test('separates accounts, conversations and cache namespaces', () async {
    await database.writeSnapshot('chat', 'room', 'alice', [
      {'id': 'private'},
    ]);
    expect(await database.readSnapshot('chat', 'room', 'alice'), [
      {'id': 'private'},
    ]);
    expect(await database.readSnapshot('chat', 'room', 'bob'), isNull);
    expect(await database.readSnapshot('chat', 'another', 'alice'), isNull);
    expect(await database.readSnapshot('home', 'room', 'alice'), isNull);
  });

  test(
    'a disk read finishing after logout cannot restore cleared memory',
    () async {
      final delayed = _DelayedCacheDatabase();
      final read = Completer<List<Map<String, dynamic>>?>();
      when(
        () => delayed.readSnapshot('chat', 'room', 'alice'),
      ).thenAnswer((_) => read.future);
      when(() => delayed.deleteScope('alice')).thenAnswer((_) async {});
      AppCache.useDatabase(delayed);
      addTearDown(() => AppCache.useDatabase(database));
      final loading = ChatMessagesCache.loadFromDisk(
        'room',
        currentUserId: 'alice',
      );
      await AppCache.forgetUser('alice');
      read.complete([
        {
          'id': 'old',
          'sender_id': 'alice',
          'conversation_id': 'room',
          'message': 'old text',
          'created_at': '2026-10-18T00:00:00Z',
        },
      ]);
      expect(await loading, isNull);
      expect(ChatMessagesCache.peek('room', currentUserId: 'alice'), isNull);
    },
  );

  test('a successful empty server snapshot replaces stale data', () async {
    await database.writeSnapshot('home', 'feed', 'guest', [
      {'id': 'old'},
    ]);
    await database.writeSnapshot('home', 'feed', 'guest', []);
    expect(await database.readSnapshot('home', 'feed', 'guest'), isEmpty);
  });

  test('logout deletion only removes the selected account', () async {
    await database.writeSnapshot('chat', 'room', 'alice', [
      {'id': 'a'},
    ]);
    await database.writeSnapshot('chat', 'room', 'bob', [
      {'id': 'b'},
    ]);
    await database.deleteScope('alice');
    expect(await database.readSnapshot('chat', 'room', 'alice'), isNull);
    expect(await database.readSnapshot('chat', 'room', 'bob'), [
      {'id': 'b'},
    ]);
  });
}

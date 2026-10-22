import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:frontend/features/chat/domain/usecases/get_owned_chat_item_ids_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_event.dart';
import 'package:mocktail/mocktail.dart';

class _StreamMessages extends Mock implements StreamMessagesUseCase {}

class _SendMessage extends Mock implements SendChatMessageUseCase {}

class _GetOwnedItems extends Mock implements GetOwnedChatItemIdsUseCase {}

ChatMessage inquiry(int? itemId) => ChatMessage(
  id: 'inquiry-$itemId',
  conversationId: 'room',
  senderId: 'customer',
  message: ItemInquiryData(
    itemId: itemId,
    itemName: 'อุปกรณ์ $itemId',
  ).toChatMessagePayload(),
  createdAt: DateTime(2026, 10, 20),
  isMine: false,
);

void main() {
  late _GetOwnedItems getOwnedItems;
  late ChatDetailBloc bloc;

  setUp(() async {
    final streamMessages = _StreamMessages();
    getOwnedItems = _GetOwnedItems();
    when(() => streamMessages('room')).thenAnswer((_) => const Stream.empty());
    bloc = ChatDetailBloc(
      streamMessages: streamMessages,
      sendMessage: _SendMessage(),
      getOwnedItemIds: getOwnedItems,
    );
    bloc.add(const ChatMessagesSubscriptionRequested('room', itemId: 1));
    await pumpEventQueue();
  });

  tearDown(() => bloc.close());

  test(
    'checks each item in a mixed-owner conversation and reuses results',
    () async {
      when(() => getOwnedItems({1, 2})).thenAnswer((_) async => {1});
      bloc.add(ChatMessagesUpdated([inquiry(1), inquiry(2)]));
      await pumpEventQueue();
      expect(bloc.state.ownedItemIds, {1});
      bloc.add(ChatMessagesUpdated([inquiry(1), inquiry(2)]));
      await pumpEventQueue();
      verify(() => getOwnedItems({1, 2})).called(1);
    },
  );

  test('checks new inquiries delivered through direct realtime', () async {
    when(() => getOwnedItems({2})).thenAnswer((_) async => {2});
    bloc.add(ChatDirectMessageReceived(inquiry(2)));
    await pumpEventQueue();
    expect(bloc.state.ownedItemIds, {2});
  });

  test(
    'uses the conversation item for legacy inquiries without an ID',
    () async {
      when(() => getOwnedItems({1})).thenAnswer((_) async => {1});
      bloc.add(ChatMessagesUpdated([inquiry(null)]));
      await pumpEventQueue();
      expect(bloc.state.ownedItemIds, {1});
    },
  );

  test('keeps creation disabled while ownership is loading or fails', () async {
    final pending = Completer<Set<int>>();
    when(() => getOwnedItems({1})).thenAnswer((_) => pending.future);
    bloc.add(ChatMessagesUpdated([inquiry(1)]));
    await pumpEventQueue();
    expect(bloc.state.ownedItemIds, isEmpty);
    pending.completeError(Exception('offline'));
    await pumpEventQueue();
    expect(bloc.state.ownedItemIds, isEmpty);
    when(() => getOwnedItems({1})).thenAnswer((_) async => {1});
    bloc.add(ChatMessagesUpdated([inquiry(1), inquiry(null)]));
    await pumpEventQueue();
    expect(bloc.state.ownedItemIds, {1});
  });

  test('ignores ownership from an earlier subscription', () async {
    final pending = Completer<Set<int>>();
    when(() => getOwnedItems({1})).thenAnswer((_) => pending.future);
    bloc.add(ChatMessagesUpdated([inquiry(1)]));
    await pumpEventQueue();
    when(() => getOwnedItems({1})).thenAnswer((_) async => {});
    bloc.add(const ChatMessagesSubscriptionRequested('room', itemId: 1));
    await pumpEventQueue();
    pending.complete({1});
    await pumpEventQueue();
    expect(bloc.state.ownedItemIds, isEmpty);
  });
}

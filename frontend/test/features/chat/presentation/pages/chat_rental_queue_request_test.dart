import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/chat/data/datasources/rental_queue_remote_data_source.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/pages/chat_detail.dart';
import 'package:mocktail/mocktail.dart';

class _MockStreamMessages extends Mock implements StreamMessagesUseCase {}

class _MockSendMessage extends Mock implements SendChatMessageUseCase {}

class _MockRentalQueue extends Mock implements RentalQueueRemoteDataSource {}

void main() {
  testWidgets('queue prompts follow the eligibility of each item in chat', (
    tester,
  ) async {
    AuthSession.saveAccessToken('test-token');
    addTearDown(AuthSession.clear);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    const conversation = ChatConversation(
      id: 'queue-room',
      otherUserId: 'item-owner',
      name: 'ผู้ปล่อยเช่า',
      // ห้องเดิมอาจบันทึกบทบาทไว้คนละฝั่งกับเจ้าของประกาศปัจจุบัน
      role: ChatParticipantRole.renter,
      avatarAsset: '',
      preview: '',
      timeLabel: '',
    );
    final stream = StreamController<List<ChatMessage>>();
    addTearDown(stream.close);
    final messages = _MockStreamMessages();
    when(() => messages(conversation.id)).thenAnswer((_) => stream.stream);
    final bloc = ChatDetailBloc(
      streamMessages: messages,
      sendMessage: _MockSendMessage(),
    );
    addTearDown(bloc.close);
    final queue = _MockRentalQueue();
    var items = <({int id, String name})>[];
    when(() => queue.listItems(conversation.id)).thenAnswer((_) async => items);
    when(
      () => queue.runAction(conversation.id, 'request', itemId: 8),
    ).thenAnswer((_) async {
      items = [];
      return {'message_id': 35};
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ChatDetailScreen(
          conversation: conversation,
          chatDetailBloc: bloc,
          rentalQueueSource: queue,
        ),
      ),
    );
    stream.add([
      ChatMessage(
        id: '34',
        conversationId: conversation.id,
        senderId: conversation.otherUserId,
        message:
            '{"rentalQueue":{"itemId":9,"name":"เลนส์","status":"invited"}}',
        createdAt: DateTime.utc(2026, 11, 27),
        isMine: false,
      ),
    ]);
    await tester.pumpAndSettle();
    final requestQueue = find.text('ขอคิวเช่าต่อ');
    final invitation = find.text('เจ้าของชวนคุณเข้าคิว');
    expect(requestQueue, findsNothing);
    expect(invitation, findsNothing);

    items = [(id: 8, name: 'กล้องที่กำลังถูกเช่า')];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(invitation, findsNothing);

    items = [...items, (id: 9, name: 'เลนส์')];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(invitation, findsOneWidget);

    items = [(id: 8, name: 'กล้องที่กำลังถูกเช่า')];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(invitation, findsNothing);
    final field = find.byKey(const ValueKey('chat-message-field'));
    expect(requestQueue.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(requestQueue).bottom,
      lessThanOrEqualTo(tester.getRect(field).top),
    );
    await tester.tap(requestQueue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('กล้องที่กำลังถูกเช่า'));
    await tester.pumpAndSettle();

    verify(
      () => queue.runAction(conversation.id, 'request', itemId: 8),
    ).called(1);
    expect(requestQueue, findsNothing);

    stream.add([
      ChatMessage(
        id: '35',
        conversationId: conversation.id,
        senderId: 'customer',
        message:
            '{"rentalQueue":{"itemId":8,"name":"กล้อง",'
            '"status":"accepted","requestedByRenter":true,'
            '"acceptedAt":"2026-11-27T03:00:00Z"}}',
        createdAt: DateTime.utc(2026, 11, 27, 1),
        isMine: true,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('ส่งคำขอเช่า'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

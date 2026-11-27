import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/data/datasources/rental_queue_remote_data_source.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/pages/chat_detail.dart';
import 'package:frontend/features/chat/presentation/widgets/item_inquiry_bubble_card.dart';
import 'package:frontend/features/chat/presentation/widgets/rental_queue_card.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockStreamMessages extends Mock implements StreamMessagesUseCase {}

class _MockSendMessage extends Mock implements SendChatMessageUseCase {}

class _MockRentalQueue extends Mock implements RentalQueueRemoteDataSource {}

void main() {
  for (final (hasInquiry, hasConfirmedRental) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    testWidgets(
      hasConfirmedRental
          ? 'the confirmed renter keeps their booking without a queue prompt'
          : 'another renter has the item (existing inquiry: $hasInquiry)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        AuthSession.saveAccessToken('test-token');
        addTearDown(AuthSession.clear);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.view.physicalSize = Size(400, hasConfirmedRental ? 1500 : 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final conversation = ChatConversation(
          id: hasConfirmedRental ? 'customer-a-room' : 'customer-b-room',
          otherUserId: 'item-owner',
          name: 'ผู้ปล่อยเช่า',
          role: ChatParticipantRole.owner,
          avatarAsset: '',
          preview: '',
          timeLabel: '',
          itemId: 1,
          itemName: 'โต๊ะ',
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
        var occupied = hasConfirmedRental || !hasInquiry;
        var joined = false;
        when(() => queue.listItems(conversation.id)).thenAnswer(
          (_) async => occupied && !joined && !hasConfirmedRental
              ? [(id: 1, name: 'โต๊ะ')]
              : [],
        );
        when(
          () => queue.runAction(conversation.id, 'request', itemId: 1),
        ).thenAnswer((_) async {
          joined = true;
          return {'message_id': 20};
        });

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: conversation,
              chatDetailBloc: bloc,
              rentalQueueSource: queue,
              getUnavailableRentalItemIds: (ids) async => {
                if (occupied && ids.contains(1)) 1,
              },
            ),
          ),
        );
        final start = DateTime.now().add(const Duration(days: 1));
        stream.add([
          if (hasInquiry)
            for (final (id, name) in [(1, 'โต๊ะ'), (2, 'เลนส์')])
              ChatMessage(
                id: '$id',
                conversationId: conversation.id,
                senderId: hasConfirmedRental ? 'customer-a' : 'customer-b',
                message: ItemInquiryData(
                  itemId: id,
                  itemName: name,
                ).toChatMessagePayload(),
                createdAt: DateTime.utc(2026, 11, 27, 10, id),
                isMine: true,
              ),
          if (hasConfirmedRental)
            ChatMessage(
              id: '3',
              conversationId: conversation.id,
              senderId: conversation.otherUserId,
              message: BookingRequestData(
                item: BookingItemInfo.defaultMockItem.copyWith(
                  id: 1,
                  title: 'โต๊ะ',
                  imageUrl: '',
                ),
                startDate: start,
                endDate: start.add(const Duration(days: 1)),
                startTime: const TimeOfDay(hour: 9, minute: 0),
                endTime: const TimeOfDay(hour: 9, minute: 0),
                location: 'จุดนัดรับ',
                bookingId: 25,
                status: 'confirmed',
              ).toChatMessagePayload(),
              createdAt: DateTime.utc(2026, 11, 27, 10, 3),
              isMine: false,
            ),
        ]);
        await tester.pumpAndSettle();
        final tableInquiry = find.byWidgetPredicate(
          (widget) =>
              widget is ItemInquiryBubbleCard && widget.inquiryData.itemId == 1,
        );
        if (hasConfirmedRental) {
          expect(tableInquiry, findsOneWidget);
          expect(find.text('ยืนยันคำขอเช่าเรียบร้อยแล้ว'), findsOneWidget);
          expect(find.text('ขอคิวเช่าต่อ'), findsNothing);
          expect(find.textContaining('กรุณาต่อคิวเพื่อเช่าต่อ'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          return;
        }
        if (hasInquiry) {
          expect(tableInquiry, findsOneWidget);
          occupied = true;
          await tester.pump(const Duration(seconds: 30));
          await tester.pumpAndSettle();
          expect(find.byType(ItemInquiryBubbleCard), findsOneWidget);
          expect(find.text('เลนส์'), findsOneWidget);
        }

        expect(tableInquiry, findsNothing);
        expect(find.textContaining('กรุณาต่อคิวเพื่อเช่าต่อ'), findsOneWidget);
        await tester.tap(find.text('ขอคิวเช่าต่อ'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'โต๊ะ'));
        await tester.pumpAndSettle();
        verify(
          () => queue.runAction(conversation.id, 'request', itemId: 1),
        ).called(1);
        expect(tableInquiry, findsNothing);
        expect(find.text('ขอคิวเช่าต่อ'), findsNothing);

        if (hasInquiry) {
          occupied = false;
          await tester.pump(const Duration(seconds: 30));
          await tester.pumpAndSettle();
          expect(tableInquiry, findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('the promoted queue card moves below its ready notice', (
    tester,
  ) async {
    await initializeDateFormatting('th');
    SharedPreferences.setMockInitialValues({});
    AuthSession.saveAccessToken('test-token');
    addTearDown(AuthSession.clear);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const conversation = ChatConversation(
      id: 'queue-ready-room',
      otherUserId: 'item-owner',
      name: 'ผู้ปล่อยเช่า',
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
    when(() => queue.listItems(conversation.id)).thenAnswer((_) async => []);
    when(
      () => queue.runAction(conversation.id, 'accept', messageId: 10),
    ).thenAnswer((_) async => {'message_id': 10});
    ChatMessage message(int id, String content, {bool isMine = true}) =>
        ChatMessage(
          id: '$id',
          conversationId: conversation.id,
          senderId: isMine ? 'customer' : conversation.otherUserId,
          message: content,
          createdAt: DateTime.utc(2026, 11, 27, 9, id),
          isMine: isMine,
        );
    final waiting = message(
      10,
      '{"rentalQueue":{"itemId":8,"name":"กล้อง","status":"waiting",'
      '"position":1,"requestedByRenter":true}}',
    );
    final otherQueue = message(
      11,
      '{"rentalQueue":{"itemId":9,"name":"เลนส์","status":"waiting",'
      '"position":1,"requestedByRenter":true}}',
    );
    const noticeText =
        'อุปกรณ์พร้อมให้เช่าต่อแล้ว กรุณายืนยันสิทธิ์ในการ์ดคิวภายใน 24 ชั่วโมง';
    final notice = message(12, noticeText, isMine: false);
    final ready = message(
      10,
      '{"rentalQueue":{"itemId":8,"name":"กล้อง","status":"ready",'
      '"requestedByRenter":true,"readyMessageId":"12"}}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatDetailScreen(
          conversation: conversation,
          chatDetailBloc: bloc,
          rentalQueueSource: queue,
        ),
      ),
    );
    stream.add([waiting, otherQueue]);
    await tester.pumpAndSettle();
    final camera = find.text('กล้อง');
    final lens = find.text('เลนส์');
    expect(tester.getTopLeft(camera).dy, lessThan(tester.getTopLeft(lens).dy));

    stream.add([ready, otherQueue]);
    await tester.pumpAndSettle();
    expect(camera, findsOneWidget);

    stream.add([ready, otherQueue, notice]);
    await tester.pumpAndSettle();
    final noticeTextFinder = find.text(noticeText);
    expect(find.byType(RentalQueueCard), findsNWidgets(2));
    expect(camera, findsOneWidget);
    expect(find.text('รออุปกรณ์คืน · คิวที่ 1'), findsOneWidget);
    expect(
      tester.getBottomLeft(lens).dy,
      lessThan(tester.getTopLeft(noticeTextFinder).dy),
    );
    expect(
      tester.getBottomLeft(noticeTextFinder).dy,
      lessThan(tester.getTopLeft(camera).dy),
    );
    await tester.tap(find.text('ยืนยันสิทธิ์และนัดรับ'));
    await tester.pumpAndSettle();
    verify(
      () => queue.runAction(conversation.id, 'accept', messageId: 10),
    ).called(1);

    stream.add([
      message(
        10,
        '{"rentalQueue":{"itemId":8,"name":"กล้อง","status":"accepted",'
        '"requestedByRenter":true,"readyMessageId":"12",'
        '"acceptedAt":"2026-11-27T09:13:00Z"}}',
      ),
      otherQueue,
      notice,
    ]);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(camera).dy,
      greaterThan(tester.getBottomLeft(noticeTextFinder).dy),
    );
    expect(find.text('ส่งคำขอเช่า'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final isOwner in [true, false]) {
    testWidgets('pending request follows occupancy (owner: $isOwner)', (
      tester,
    ) async {
      await initializeDateFormatting('th');
      SharedPreferences.setMockInitialValues({});
      AuthSession.saveAccessToken('test-token');
      addTearDown(AuthSession.clear);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(800, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final conversation = ChatConversation(
        id: 'occupied-room-$isOwner',
        otherUserId: isOwner ? 'customer-b' : 'item-owner',
        name: isOwner ? 'ลูกค้า B' : 'ผู้ปล่อยเช่า',
        role: isOwner ? ChatParticipantRole.owner : ChatParticipantRole.renter,
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
      var occupied = false;
      var queueHeld = false;
      var joined = false;
      when(() => queue.listItems(conversation.id)).thenAnswer(
        (_) async =>
            !isOwner && occupied && !joined ? [(id: 1, name: 'กล้อง A')] : [],
      );
      when(
        () => queue.runAction(conversation.id, 'request', itemId: 1),
      ).thenAnswer((_) async {
        joined = true;
        return {'message_id': 40};
      });

      final now = DateTime.now();
      ChatMessage request(int id, String title) => ChatMessage(
        id: '${30 + id}',
        conversationId: conversation.id,
        senderId: 'customer-b',
        message: BookingRequestData(
          item: BookingItemInfo.defaultMockItem.copyWith(
            id: id,
            title: title,
            imageUrl: '',
          ),
          startDate: now.add(const Duration(days: 1)),
          endDate: now.add(const Duration(days: 2)),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 0),
          location: 'จุดนัดรับ',
          bookingId: 20 + id,
          status: 'pending',
          isCustomerRequest: true,
        ).toChatMessagePayload(),
        createdAt: now.add(Duration(seconds: id)),
        isMine: !isOwner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: conversation,
            chatDetailBloc: bloc,
            rentalQueueSource: queue,
            getUnavailableRentalItemIds: (ids) async =>
                occupied || queueHeld ? {1} : {},
          ),
        ),
      );
      stream.add([request(1, 'กล้อง A'), request(2, 'เลนส์ B')]);
      await tester.pumpAndSettle();
      final requestAction = find.text(
        isOwner ? 'ตรวจสอบและยืนยันคำขอเช่า' : 'แก้ไขรายละเอียด',
      );
      final queuePrompt = find.text('ชวนเข้าคิวเช่าต่อ');
      expect(requestAction, findsNWidgets(2));
      expect(queuePrompt, findsNothing);

      occupied = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(requestAction, findsOneWidget);
      expect(queuePrompt, isOwner ? findsNothing : findsOneWidget);

      if (!isOwner) {
        await tester.tap(queuePrompt);
        await tester.pumpAndSettle();
        verify(
          () => queue.runAction(conversation.id, 'request', itemId: 1),
        ).called(1);
        expect(queuePrompt, findsNothing);
        expect(requestAction, findsOneWidget);
      }

      occupied = false;
      queueHeld = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(requestAction, findsOneWidget);
      expect(queuePrompt, findsNothing);

      queueHeld = false;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(requestAction, findsNWidgets(2));
      expect(queuePrompt, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a saved customer request replaces the preceding inquiry only', (
    tester,
  ) async {
    await initializeDateFormatting('th');
    SharedPreferences.setMockInitialValues({});
    AuthSession.saveAccessToken('test-token');
    addTearDown(AuthSession.clear);
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const conversation = ChatConversation(
      id: 'request-room',
      otherUserId: 'item-owner',
      name: 'ผู้ปล่อยเช่า',
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
    when(() => queue.listItems(conversation.id)).thenAnswer((_) async => []);
    final now = DateTime.now();
    ChatMessage message(String id, String text, int minute) => ChatMessage(
      id: id,
      conversationId: conversation.id,
      senderId: 'customer',
      message: text,
      createdAt: now.add(Duration(minutes: minute)),
      isMine: true,
    );
    final inquiry = message(
      '10',
      const ItemInquiryData(itemId: 1, itemName: 'โต๊ะ').toChatMessagePayload(),
      0,
    );
    final otherInquiry = message(
      '11',
      const ItemInquiryData(
        itemId: 2,
        itemName: 'กล้อง',
      ).toChatMessagePayload(),
      1,
    );
    final request = BookingRequestData(
      item: BookingItemInfo.defaultMockItem.copyWith(
        title: 'โต๊ะ',
        imageUrl: '',
      ),
      startDate: now.add(const Duration(days: 1)),
      endDate: now.add(const Duration(days: 2)),
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 9, minute: 0),
      location: 'จุดนัดรับ',
      bookingId: 25,
      status: 'pending',
      isCustomerRequest: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatDetailScreen(
          conversation: conversation,
          chatDetailBloc: bloc,
          rentalQueueSource: queue,
        ),
      ),
    );
    stream.add([inquiry, otherInquiry]);
    await tester.pumpAndSettle();
    expect(find.byType(ItemInquiryBubbleCard), findsNWidgets(2));
    stream.add([
      inquiry,
      otherInquiry,
      message('12', request.toChatMessagePayload(), 2),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(ItemInquiryBubbleCard), findsOneWidget);
    expect(find.text('กล้อง'), findsOneWidget);
    expect(find.text('แก้ไขรายละเอียด'), findsOneWidget);
    stream.add([
      inquiry,
      otherInquiry,
      message(
        '12',
        request.copyWith(status: 'cancelled').toChatMessagePayload(),
        2,
      ),
      message('13', inquiry.message, 3),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(ItemInquiryBubbleCard), findsNWidgets(2));
    expect(find.text('แก้ไขรายละเอียด'), findsNothing);
    expect(find.text('ส่งคำขอเช่าใหม่'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/skeleton_layout_cache.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/data/datasources/rental_queue_remote_data_source.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:frontend/features/chat/domain/repositories/chat_repository.dart';
import 'package:frontend/features/chat/domain/usecases/get_owned_chat_item_ids_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/pages/chat_detail.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_empty_view.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_skeleton_loading_view.dart';
import 'package:frontend/features/chat/presentation/widgets/item_inquiry_bubble_card.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

class _Messages extends Mock implements StreamMessagesUseCase {}

class _SendMessage extends Mock implements SendChatMessageUseCase {}

class _Queue extends Mock implements RentalQueueRemoteDataSource {}

class _Repository extends Mock implements ChatRepository {}

void main() {
  Future<StreamController<List<ChatMessage>>> openChat(
    WidgetTester tester, {
    String preview = 'ข้อความก่อนหน้า',
    Future<Set<int>> Function(Set<int>)? availability,
    Future<Set<int>>? ownership,
    Future<List<({int id, String name})>> Function()? listQueue,
  }) async {
    SharedPreferences.setMockInitialValues({});
    AuthSession.saveAccessToken('test-token');
    addTearDown(AuthSession.clear);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final stream = StreamController<List<ChatMessage>>();
    final messages = _Messages();
    when(() => messages('room')).thenAnswer((_) => stream.stream);
    final repository = _Repository();
    when(
      () => repository.getOwnedItemIds({1}),
    ).thenAnswer((_) => ownership ?? Future.value({}));
    final bloc = ChatDetailBloc(
      streamMessages: messages,
      sendMessage: _SendMessage(),
      getOwnedItemIds: GetOwnedChatItemIdsUseCase(repository),
    );
    addTearDown(() async {
      await bloc.close();
      await stream.close();
    });
    final queue = _Queue();
    when(
      () => queue.listItems('room'),
    ).thenAnswer((_) => listQueue?.call() ?? Future.value([]));
    final conversation = ChatConversation(
      id: 'room',
      otherUserId: 'peer',
      name: 'ผู้สนทนา',
      role: ChatParticipantRole.owner,
      avatarAsset: '',
      preview: preview,
      timeLabel: '',
      itemId: 1,
      itemName: 'โต๊ะ',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatDetailScreen(
          conversation: conversation,
          chatDetailBloc: bloc,
          rentalQueueSource: queue,
          getUnavailableRentalItemIds: availability ?? (_) async => {},
        ),
      ),
    );
    await tester.pump();
    return stream;
  }

  ChatMessage message(String body, {String id = 'message-id'}) => ChatMessage(
    id: id,
    conversationId: 'room',
    senderId: 'viewer',
    message: body,
    createdAt: DateTime(2026, 11, 27, 10),
    isMine: true,
  );

  const inquiry = ItemInquiryData(itemId: 1, itemName: 'โต๊ะ');
  final sendRequest = find.text('ส่งคำขอเช่าอุปกรณ์นี้');

  for (final occupied in [true, false]) {
    testWidgets('inquiry waits for item availability (occupied: $occupied)', (
      tester,
    ) async {
      final availability = Completer<Set<int>>();
      final stream = await openChat(
        tester,
        availability: (_) => availability.future,
      );
      stream.add([message(inquiry.toChatMessagePayload())]);
      await tester.pumpAndSettle();
      expect(find.byType(ItemInquiryBubbleCard), findsOneWidget);
      expect(sendRequest, findsNothing);

      availability.complete(occupied ? {1} : {});
      await tester.pumpAndSettle();
      expect(sendRequest, occupied ? findsNothing : findsOneWidget);
      expect(
        find.text('อุปกรณ์นี้ยังไม่พร้อมให้เช่า'),
        occupied ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'inquiry waits for queue eligibility after availability arrives',
    (tester) async {
      final queue = Completer<List<({int id, String name})>>();
      final stream = await openChat(tester, listQueue: () => queue.future);
      stream.add([message(inquiry.toChatMessagePayload())]);
      await tester.pumpAndSettle();
      expect(sendRequest, findsNothing);

      queue.complete([(id: 1, name: 'โต๊ะ')]);
      await tester.pumpAndSettle();
      expect(sendRequest, findsNothing);
      expect(
        find.text('อุปกรณ์นี้กำลังถูกเช่า กรุณาต่อคิวเพื่อเช่าต่อ'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a self-owned item never shows the rental request action', (
    tester,
  ) async {
    final ownership = Completer<Set<int>>();
    final stream = await openChat(tester, ownership: ownership.future);
    stream.add([message(inquiry.toChatMessagePayload())]);
    await tester.pumpAndSettle();
    expect(sendRequest, findsNothing);

    ownership.complete({1});
    await tester.pumpAndSettle();
    expect(find.byType(ItemInquiryBubbleCard), findsOneWidget);
    expect(sendRequest, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an occupied pending request never shows its edit action', (
    tester,
  ) async {
    final availability = Completer<Set<int>>();
    final stream = await openChat(
      tester,
      availability: (_) => availability.future,
    );
    final request = BookingRequestData(
      item: BookingItemInfo.defaultMockItem.copyWith(
        id: 1,
        title: 'โต๊ะ',
        imageUrl: '',
      ),
      startDate: DateTime(2099, 11, 27),
      endDate: DateTime(2099, 11, 28),
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 9, minute: 0),
      location: 'จุดนัดรับ',
      bookingId: 36,
      status: 'pending',
      isCustomerRequest: true,
    );
    stream.add([message(request.toChatMessagePayload())]);
    final edit = find.text('แก้ไขรายละเอียด');
    await tester.pumpAndSettle();
    expect(edit, findsNothing);

    availability.complete({1});
    await tester.pumpAndSettle();
    expect(edit, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final occupied in [false, true]) {
    testWidgets(
      'cancelled request keeps its retry row while checking eligibility (occupied: $occupied)',
      (tester) async {
        final availability = Completer<Set<int>>();
        final queue = Completer<List<({int id, String name})>>();
        final stream = await openChat(
          tester,
          availability: (_) => availability.future,
          listQueue: () => queue.future,
        );
        final request = BookingRequestData(
          item: BookingItemInfo.defaultMockItem.copyWith(
            id: 1,
            title: 'โต๊ะ',
            imageUrl: '',
          ),
          startDate: DateTime(2099, 11, 27),
          endDate: DateTime(2099, 11, 28),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 0),
          location: 'จุดนัดรับ',
          bookingId: 36,
          status: 'cancelled',
          isCustomerRequest: true,
        );
        stream.add([
          message(inquiry.toChatMessagePayload(), id: 'inquiry'),
          message(request.toChatMessagePayload()),
        ]);
        await tester.pumpAndSettle();
        final retry = find.widgetWithText(TextButton, 'ส่งคำขอเช่าใหม่');
        expect(tester.widget<TextButton>(retry).enabled, isFalse);
        final retrySize = tester.getSize(retry);

        availability.complete(occupied ? {1} : {});
        await tester.pumpAndSettle();
        expect(tester.widget<TextButton>(retry).enabled, isFalse);
        expect(tester.getSize(retry), retrySize);

        queue.complete(occupied ? [(id: 1, name: 'โต๊ะ')] : []);
        await tester.pumpAndSettle();
        if (occupied) {
          expect(retry, findsNothing);
          expect(find.text('ชวนเข้าคิวเช่าต่อ'), findsOneWidget);
        } else {
          expect(tester.widget<TextButton>(retry).enabled, isTrue);
          expect(tester.getSize(retry), retrySize);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'queue stays visible after a refresh failure until eligibility changes',
    (tester) async {
      var attempts = 0;
      final stream = await openChat(
        tester,
        listQueue: () async {
          attempts++;
          if (attempts == 2) {
            throw const RentalQueueRemoteException('temporary network failure');
          }
          return attempts == 3 ? [] : [(id: 1, name: 'โต๊ะ')];
        },
      );
      stream.add([message('มีข้อความก่อนหน้า')]);
      final queue = find.text('ขอคิวเช่าต่อ');
      await tester.pumpAndSettle();
      expect(queue, findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(queue, findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(queue, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final hasMessages in [true, false]) {
    testWidgets('empty preview waits for history (messages: $hasMessages)', (
      tester,
    ) async {
      final stream = await openChat(tester, preview: 'ยังไม่มีข้อความ');
      final skeleton = find.byType(ChatSkeletonLoadingView);
      expect(find.byType(ChatEmptyView), findsNothing);
      expect(skeleton, findsOneWidget);
      expect(
        find.descendant(of: skeleton, matching: find.byType(Shimmer)),
        findsWidgets,
      );

      stream.add([if (hasMessages) message('ข้อความเดิมในห้องแชท')]);
      await tester.pumpAndSettle();
      expect(skeleton, findsNothing);
      expect(
        find.byType(ChatEmptyView),
        hasMessages ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('ข้อความเดิมในห้องแชท'),
        hasMessages ? findsOneWidget : findsNothing,
      );
      if (hasMessages) {
        // ขนาดข้อความจริงถูกจำไว้ ให้ skeleton ครั้งหน้าวาดรายการเดียวตามนี้
        final layout = SkeletonLayoutCache.instance.read('chat.room');
        expect(layout, hasLength(1));
        expect(layout!.single, startsWith('o|t|'));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

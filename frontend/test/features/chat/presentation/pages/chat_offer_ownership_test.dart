import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/data/models/chat_conversation_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:frontend/features/chat/domain/repositories/chat_repository.dart';
import 'package:frontend/features/chat/domain/usecases/get_owned_chat_item_ids_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/pages/chat_detail.dart';
import 'package:frontend/features/chat/presentation/widgets/item_inquiry_bubble_card.dart';
import 'package:mocktail/mocktail.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockStreamMessages extends Mock implements StreamMessagesUseCase {}

class _MockSendMessage extends Mock implements SendChatMessageUseCase {}

class _MockRepository extends Mock implements ChatRepository {}

void main() {
  testWidgets(
    'owner can offer the same item again after the previous rental completed',
    (tester) async {
      await initializeDateFormatting('th');
      SharedPreferences.setMockInitialValues({});
      BookingConfirmationTracker.clearMemoryCache();
      final conversation = ChatConversationModel.fromRecords(
        conversation: const {
          'id': 'renewal-room',
          'renter_id': 'owner',
          'owner_id': 'customer',
          'item_id': 1,
        },
        otherProfile: const {'display_name': 'ลูกค้า'},
        item: const {'id': 1, 'user_id': 'owner', 'item_name': 'Canon EOS R50'},
        currentUserId: 'owner',
      );
      final previous = BookingRequestData(
        item: const BookingItemInfo(
          id: 1,
          title: 'Canon EOS R50',
          imageUrl: '',
          rating: 5,
          reviewCount: 1,
          hourlyRate: 700,
          dailyRate: 5799,
          defaultLocation: 'กรุงเทพ',
        ),
        startDate: DateTime(2026, 10, 18),
        endDate: DateTime(2026, 10, 19),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 9, minute: 0),
        location: 'กรุงเทพ',
        bookingId: 10,
        status: 'completed',
      );
      const renewed = ItemInquiryData(
        itemId: 1,
        itemName: 'Canon EOS R50',
        previousBookingId: 10,
      );
      final stream = StreamController<List<ChatMessage>>();
      final streamMessages = _MockStreamMessages();
      when(
        () => streamMessages(conversation.id),
      ).thenAnswer((_) => stream.stream);
      final repository = _MockRepository();
      when(() => repository.getOwnedItemIds({1})).thenAnswer((_) async => {1});
      final bloc = ChatDetailBloc(
        streamMessages: streamMessages,
        sendMessage: _MockSendMessage(),
        getOwnedItemIds: GetOwnedChatItemIdsUseCase(repository),
      );
      addTearDown(() async {
        await bloc.close();
        await stream.close();
        BookingConfirmationTracker.clearMemoryCache();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: conversation,
            chatDetailBloc: bloc,
          ),
        ),
      );
      await tester.pump();
      stream.add([
        ChatMessage(
          id: 'previous-offer',
          conversationId: conversation.id,
          senderId: 'owner',
          message: previous.toChatMessagePayload(),
          createdAt: DateTime(2026, 10, 18),
          isMine: true,
        ),
        ChatMessage(
          id: 'renewed-inquiry',
          conversationId: conversation.id,
          senderId: 'customer',
          message: renewed.toChatMessagePayload(),
          createdAt: DateTime(2026, 10, 20),
          isMine: false,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inquiry-send-request-1')),
        findsOneWidget,
      );
      expect(find.text('สร้างข้อเสนอการเช่า / นัดรับ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final isOwner in [false, null]) {
    testWidgets('inquiry card rejects creation callback when owner=$isOwner', (
      tester,
    ) async {
      const inquiry = ItemInquiryData(itemId: 1, itemName: 'Canon EOS R50');
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ItemInquiryBubbleCard(
              message: ChatMessage(
                id: 'inquiry',
                conversationId: 'room',
                senderId: 'customer',
                message: inquiry.toChatMessagePayload(),
                createdAt: DateTime(2026, 10, 20),
                isMine: true,
              ),
              inquiryData: inquiry,
              isOwner: isOwner,
              onSendBookingRequest: (_) => called = true,
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('inquiry-send-request-1')),
        findsNothing,
      );
      expect(find.text('ดูรายละเอียดอุปกรณ์'), findsOneWidget);
      expect(called, isFalse);
    });
  }

  for (final reversedParticipants in [false, true]) {
    for (final viewerIsOwner in [true, false]) {
      for (final senderIsOwner in [true, false]) {
        testWidgets(
          'Only item owner can create offer: reversed=$reversedParticipants, '
          'viewerOwner=$viewerIsOwner, senderOwner=$senderIsOwner',
          (tester) async {
            const ownerId = 'item-owner';
            const customerId = 'item-customer';
            final currentUserId = viewerIsOwner ? ownerId : customerId;
            final conversation = ChatConversationModel.fromRecords(
              conversation: {
                'id': 'conv-ownership',
                'renter_id': reversedParticipants ? ownerId : customerId,
                'owner_id': reversedParticipants ? customerId : ownerId,
                'item_id': 1,
              },
              otherProfile: const {'display_name': 'คู่สนทนา'},
              item: const {
                'id': 1,
                'user_id': ownerId,
                'item_name': 'Canon EOS R50',
                'price': 5799,
                'type': 'รายวัน',
              },
              currentUserId: currentUserId,
            );
            const inquiry = ItemInquiryData(
              itemId: 1,
              itemName: 'Canon EOS R50',
              price: 5799,
              unitLabel: 'วัน',
            );
            final senderId = senderIsOwner ? ownerId : customerId;
            final message = ChatMessage(
              id: 'inquiry-ownership',
              conversationId: conversation.id,
              senderId: senderId,
              message: inquiry.toChatMessagePayload(),
              createdAt: DateTime(2026, 10, 20, 20, 7),
              isMine: senderId == currentUserId,
            );
            final messages = StreamController<List<ChatMessage>>();
            final streamMessages = _MockStreamMessages();
            when(
              () => streamMessages(conversation.id),
            ).thenAnswer((_) => messages.stream);
            final repository = _MockRepository();
            when(
              () => repository.getOwnedItemIds({1}),
            ).thenAnswer((_) async => viewerIsOwner ? {1} : {});
            final bloc = ChatDetailBloc(
              streamMessages: streamMessages,
              sendMessage: _MockSendMessage(),
              getOwnedItemIds: GetOwnedChatItemIdsUseCase(repository),
            );
            ChatMessagesCache.clear();
            addTearDown(() async {
              await bloc.close();
              await messages.close();
              ChatMessagesCache.clear();
            });

            await tester.pumpWidget(
              MaterialApp(
                home: ChatDetailScreen(
                  conversation: conversation,
                  chatDetailBloc: bloc,
                ),
              ),
            );
            await tester.pump();
            messages.add([message]);
            await tester.pumpAndSettle();

            expect(
              find.text('สร้างข้อเสนอการเช่า / นัดรับ'),
              viewerIsOwner ? findsOneWidget : findsNothing,
              reason:
                  'Offer creation follows item ownership, regardless of '
                  'conversation participant slots or inquiry sender.',
            );
          },
        );
      }
    }
  }
}

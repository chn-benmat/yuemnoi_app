import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/services/phone_call_service.dart';
import 'package:frontend/core/widgets/custom_bottom_navbar.dart';
import 'package:frontend/features/chat/data/models/chat_conversation_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/chat_reply_content.dart';
import 'package:frontend/features/chat/domain/repositories/chat_repository.dart';
import 'package:frontend/features/chat/domain/usecases/get_conversation_contact_phone_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/get_owned_chat_item_ids_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/get_conversations_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_event.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_state.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_list_bloc.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_list_event.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_list_state.dart';
import 'package:frontend/features/chat/presentation/pages/chat.dart';
import 'package:frontend/features/chat/presentation/pages/chat_detail.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_avatar.dart';
import 'package:frontend/core/services/active_conversation_tracker.dart';
import 'package:frontend/core/services/chat_notification_service.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:frontend/features/chat/presentation/widgets/global_chat_notification_listener.dart';
import 'package:frontend/features/chat/domain/usecases/upload_chat_image_usecase.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_image_preview_modal.dart';
import 'package:frontend/features/chat/presentation/widgets/in_app_notification_banner.dart';
import 'package:frontend/core/services/chat_pin_service.dart';
import 'package:frontend/features/chat/presentation/widgets/conversation_action_sheet.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_message_action_sheet.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:frontend/features/chat/presentation/widgets/stacked_images_grid_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/features/profile/presentation/pages/profile/user_profile_view_screen.dart';
import 'package:go_router/go_router.dart';

import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockGetConversationsUseCase extends Mock
    implements GetConversationsUseCase {}

class _MockStreamMessagesUseCase extends Mock
    implements StreamMessagesUseCase {}

class _MockSendChatMessageUseCase extends Mock
    implements SendChatMessageUseCase {}

class _MockGetOwnedChatItemIdsUseCase extends Mock
    implements GetOwnedChatItemIdsUseCase {}

class _MockUploadChatImageUseCase extends Mock
    implements UploadChatImageUseCase {}

class _MockChatRemoteDataSource extends Mock implements ChatRemoteDataSource {}

class _MockChatRepository extends Mock implements ChatRepository {}

class _FakePhoneCallService implements PhoneCallService {
  String? calledPhone;

  @override
  Future<bool> call(String phoneNumber) async {
    calledPhone = phoneNumber;
    return true;
  }
}

class _MockChatNotificationService extends Mock
    implements ChatNotificationService {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  test('converts Thailand country code to a local dialer number', () {
    expect(normalizePhoneNumberForDialer('+66 81-234-5678'), '0812345678');
    expect(normalizePhoneNumberForDialer('+660812345678'), '0812345678');
  });

  test('conversation model preserves message time and creation fallback', () {
    ChatConversation fromRecord(Map<String, dynamic> record) =>
        ChatConversationModel.fromRecords(
          conversation: {
            'id': 'conv-time',
            'renter_id': 'me',
            'owner_id': 'other',
            ...record,
          },
          otherProfile: null,
          item: null,
          currentUserId: 'me',
        );
    final latest = DateTime.utc(2026, 10, 21, 10);
    final created = DateTime.utc(2026, 10, 20, 8);
    final conversation = fromRecord({
      'last_message_at': latest.toIso8601String(),
      'created_at': created.toIso8601String(),
    });
    expect(conversation.lastMessageAt!.isAtSameMomentAs(latest), isTrue);
    expect(
      conversation.copyWith(hasUnreadMessage: true).lastMessageAt,
      conversation.lastMessageAt,
    );
    expect(
      fromRecord({
        'created_at': created.toIso8601String(),
      }).lastMessageAt!.isAtSameMomentAs(created),
      isTrue,
    );
  });

  const sampleConversation1 = ChatConversation(
    id: 'conv-1',
    otherUserId: 'user-owner-1',
    name: 'สมชาย เจ้าของกล้อง',
    role: ChatParticipantRole.owner,
    avatarAsset: 'assets/images/user.png',
    preview: 'สนใจเช่า Sony A7IV ไหมครับ',
    timeLabel: '10 นาที',
    itemId: 1,
    itemName: 'Sony Alpha A7 IV',
    itemPrice: 1200,
    itemRentalType: 'รายวัน',
    hasUnreadMessage: true,
  );

  const sampleConversation2 = ChatConversation(
    id: 'conv-2',
    otherUserId: 'user-renter-1',
    name: 'วิภาวี ผู้เช่าเต็นท์',
    role: ChatParticipantRole.renter,
    avatarAsset: 'assets/images/user.png',
    preview: 'ขอสอบถามขนาดเต็นท์หน่อยค่ะ',
    timeLabel: 'เมื่อวาน',
    itemId: 2,
    itemName: 'เต็นท์ Coleman 4 คน',
    itemPrice: 500,
    itemRentalType: 'รายวัน',
  );

  group('ChatScreen', () {
    late _MockGetConversationsUseCase mockGetConversations;
    late ChatListBloc chatListBloc;

    setUp(() {
      AuthSession.saveAccessToken('mock_token_123');
      mockGetConversations = _MockGetConversationsUseCase();
      when(
        () => mockGetConversations(),
      ).thenAnswer((_) async => [sampleConversation1, sampleConversation2]);
      chatListBloc = ChatListBloc(getConversations: mockGetConversations)
        ..add(const LoadChatListStarted());
    });

    tearDown(() {
      AuthSession.clear();
      chatListBloc.close();
    });

    testWidgets('renders all conversations without role filters', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatScreen(chatListBloc: chatListBloc)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('สมชาย เจ้าของกล้อง'), findsOneWidget);
      expect(find.text('วิภาวี ผู้เช่าเต็นท์'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('unread-conversation-dot')),
        findsOneWidget,
      );

      final firstTime = tester.getRect(
        find.text(sampleConversation1.timeLabel),
      );
      final secondTime = tester.getRect(
        find.text(sampleConversation2.timeLabel),
      );
      final card = tester.getRect(
        find.byKey(const ValueKey('conversation-conv-1')),
      );
      expect(firstTime.right, closeTo(card.right - 16, 0.1));
      expect(secondTime.right, closeTo(firstTime.right, 0.1));
      expect(find.text('ทั้งหมด'), findsNothing);
      expect(find.text('ผู้ปล่อยเช่า'), findsNothing);
      expect(find.text('ผู้เช่า'), findsNothing);
    });

    testWidgets('chat list supports narrow screens with large text', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(body: ChatScreen(chatListBloc: chatListBloc)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-search-field')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-filter-button')));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่ได้อ่าน'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('เสร็จสิ้น'));
      await tester.tap(find.text('เสร็จสิ้น'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('มีข้อความที่ยังไม่ได้อ่าน')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('filters conversation list by search query', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatScreen(chatListBloc: chatListBloc)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'เต็นท์',
      );
      await tester.pumpAndSettle();

      expect(find.text('วิภาวี ผู้เช่าเต็นท์'), findsOneWidget);
      expect(find.text('สมชาย เจ้าของกล้อง'), findsNothing);
    });

    testWidgets('sorts chats by message time and combines unread with search', (
      tester,
    ) async {
      chatListBloc.add(
        ChatConversationsUpdated([
          sampleConversation1.copyWith(lastMessageAt: DateTime(2026, 10, 20)),
          sampleConversation2.copyWith(lastMessageAt: DateTime(2026, 10, 21)),
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatScreen(chatListBloc: chatListBloc)),
        ),
      );
      await tester.pumpAndSettle();
      double top(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('conversation-$id'))).dy;
      expect(top('conv-2'), lessThan(top('conv-1')));
      await tester.tap(find.byKey(const ValueKey('chat-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เก่าสุด'));
      await tester.tap(find.text('เสร็จสิ้น'));
      await tester.pumpAndSettle();
      expect(top('conv-1'), lessThan(top('conv-2')));
      await tester.tap(find.byKey(const ValueKey('chat-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ใหม่ล่าสุด'));
      await tester.tap(find.byType(SwitchListTile));
      await tester.tap(find.text('เสร็จสิ้น'));
      await tester.pumpAndSettle();
      expect(find.text(sampleConversation1.name), findsOneWidget);
      expect(find.text(sampleConversation2.name), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'เต็นท์',
      );
      await tester.pumpAndSettle();
      expect(find.text(sampleConversation1.name), findsNothing);
      expect(find.text(sampleConversation2.name), findsNothing);
      await tester.tap(find.byTooltip('ล้างการค้นหา'));
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-search-field')))
            .controller!
            .text,
        isEmpty,
      );
      chatListBloc.add(const ChatConversationMarkedAsRead('conv-1'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(
        chatListBloc.state.conversations.every((c) => !c.hasUnreadMessage),
        isTrue,
      );
      expect(find.text('ไม่มีแชทที่ยังไม่ได้อ่าน'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.tap(find.text('เสร็จสิ้น'));
      await tester.pumpAndSettle();
      expect(top('conv-2'), lessThan(top('conv-1')));
    });

    test(
      'ChatListBloc marks conversation as read when ChatConversationMarkedAsRead is added',
      () async {
        final bloc = ChatListBloc(getConversations: mockGetConversations);
        bloc.emit(
          const ChatListState(
            status: ChatListStatus.success,
            conversations: [sampleConversation1, sampleConversation2],
          ),
        );

        expect(bloc.state.conversations.first.hasUnreadMessage, isTrue);

        bloc.add(const ChatConversationMarkedAsRead('conv-1'));
        await pumpEventQueue();

        expect(bloc.state.conversations.first.hasUnreadMessage, isFalse);
        await bloc.close();
      },
    );
  });

  group('ChatDetailScreen', () {
    late _MockStreamMessagesUseCase mockStreamMessages;
    late _MockSendChatMessageUseCase mockSendMessage;
    late StreamController<List<ChatMessage>> streamController;

    setUp(() {
      ChatMessagesCache.clear();
      mockStreamMessages = _MockStreamMessagesUseCase();
      mockSendMessage = _MockSendChatMessageUseCase();
      streamController = StreamController<List<ChatMessage>>.broadcast();

      when(
        () => mockStreamMessages('conv-1'),
      ).thenAnswer((_) => streamController.stream);

      when(
        () => mockSendMessage(
          conversationId: any(named: 'conversationId'),
          message: any(named: 'message'),
          imageUrl: any(named: 'imageUrl'),
        ),
      ).thenAnswer((_) async {});
    });

    tearDown(() {
      streamController.close();
      ChatMessagesCache.clear();
    });

    testWidgets('puts the queue invitation above the owner’s message field', (
      tester,
    ) async {
      final bloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation2.copyWith(id: 'conv-1'),
            chatDetailBloc: bloc,
          ),
        ),
      );
      await tester.pump();

      final invite = find.ancestor(
        of: find.text('ชวนเข้าคิวเช่าต่อ'),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      final field = find.byKey(const ValueKey('chat-message-field'));
      expect(invite.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(invite).bottom,
        lessThanOrEqualTo(tester.getRect(field).top),
      );
      expect(find.byTooltip('ส่งคำขอเช่าต่อ'), findsNothing);
    });

    testWidgets(
      'shows the queue shortcut when the chat contains an owned item',
      (tester) async {
        final ownership = _MockGetOwnedChatItemIdsUseCase();
        when(() => ownership({76})).thenAnswer((_) async => {76});
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          getOwnedItemIds: ownership,
        );
        addTearDown(bloc.close);

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: bloc,
            ),
          ),
        );
        await tester.pump();

        final invite = find.text('ชวนเข้าคิวเช่าต่อ');
        expect(invite, findsNothing);
        expect(find.byIcon(Icons.playlist_add_rounded), findsNothing);
        streamController.add([
          ChatMessage(
            id: 'owned-inquiry',
            conversationId: 'conv-1',
            senderId: 'user-owner-1',
            message: const ItemInquiryData(
              itemId: 76,
              itemName: 'Canon EOS R50',
            ).toChatMessagePayload(),
            createdAt: DateTime(2026, 11, 26),
            isMine: false,
            isRead: true,
          ),
        ]);
        await tester.pumpAndSettle();

        expect(invite.hitTestable(), findsOneWidget);
      },
    );

    for (final conversation in [
      sampleConversation2.copyWith(id: 'conv-1'),
      sampleConversation1,
    ]) {
      testWidgets('limits the queue shortcut to owners without an open rental '
          '(${conversation.role.name})', (tester) async {
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
        );
        addTearDown(bloc.close);

        final booking = BookingRequestData(
          item: BookingItemInfo.defaultMockItem.copyWith(imageUrl: ''),
          startDate: DateTime(2026, 11, 27),
          endDate: DateTime(2026, 11, 28),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          location: 'Pickup',
        );
        ChatMessage offer(String status, {bool isMine = true}) => ChatMessage(
          id: isMine ? 'outgoing-offer' : 'incoming-offer',
          conversationId: conversation.id,
          senderId: isMine ? 'me' : conversation.otherUserId,
          message: booking
              .copyWith(
                item: isMine ? booking.item : booking.item.copyWith(id: 76),
                bookingId: isMine ? 2087 : 2086,
                status: status,
              )
              .toChatMessagePayload(),
          createdAt: DateTime(2026, 11, 26, 10, isMine ? 1 : 0),
          isMine: isMine,
          isRead: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: conversation,
              chatDetailBloc: bloc,
            ),
          ),
        );
        await tester.pump();

        final shortcut = find.byIcon(Icons.playlist_add_rounded);
        final availableWithoutOpenRental =
            conversation.role == ChatParticipantRole.renter
            ? findsOneWidget
            : findsNothing;
        final incomingOffer = offer('active', isMine: false);
        streamController.add([incomingOffer, offer('pending')]);
        await tester.pumpAndSettle();
        expect(shortcut, availableWithoutOpenRental);

        for (final status in [
          'confirmed',
          'active',
          'awaiting_return',
          'return_ready',
        ]) {
          streamController.add([incomingOffer, offer(status)]);
          await tester.pumpAndSettle();
          expect(find.text('ชวนเข้าคิวเช่าต่อ'), findsNothing, reason: status);
          expect(
            find.byTooltip('ส่งคำขอเช่าต่อ'),
            findsNothing,
            reason: status,
          );
        }

        streamController.add([incomingOffer, offer('completed')]);
        await tester.pumpAndSettle();
        expect(shortcut, availableWithoutOpenRental);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('opens the existing inquiry for the selected item', (
      tester,
    ) async {
      final bloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
      );
      addTearDown(bloc.close);

      ChatMessage message(String id, String text, int minute) => ChatMessage(
        id: id,
        conversationId: 'conv-1',
        senderId: 'me',
        message: text,
        createdAt: DateTime(2026, 11, 24, 10, minute),
        isMine: true,
        isRead: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: bloc,
            initialMessageId: 'canon-inquiry',
          ),
        ),
      );
      await tester.pump();

      final messages = [
        message(
          'canon-inquiry',
          const ItemInquiryData(
            itemId: 76,
            itemName: 'Canon EOS R50',
          ).toChatMessagePayload(),
          0,
        ),
        for (var minute = 1; minute <= 16; minute++)
          message('message-$minute', 'ข้อความเดิม $minute', minute),
        message(
          'samsung-inquiry',
          const ItemInquiryData(
            itemId: 102,
            itemName: 'Samsung Galaxy S26',
          ).toChatMessagePayload(),
          17,
        ),
      ];
      streamController.add(messages.sublist(8));
      await tester.pumpAndSettle();
      expect(find.text('Samsung Galaxy S26').hitTestable(), findsOneWidget);

      streamController.add(messages);
      await tester.pumpAndSettle();

      expect(find.text('Canon EOS R50').hitTestable(), findsOneWidget);
      expect(
        find.text(ItemInquiryData.inquiryPrefix).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('opens phone dialer from the right-side call button', (
      tester,
    ) async {
      final chatDetailBloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
      );
      final repository = _MockChatRepository();
      final phoneCallService = _FakePhoneCallService();
      addTearDown(chatDetailBloc.close);

      when(
        () => repository.getConversationContactPhone('conv-1'),
      ).thenAnswer((_) async => '0812345678');

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: chatDetailBloc,
            getContactPhone: GetConversationContactPhoneUseCase(repository),
            phoneCallService: phoneCallService,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chat-phone-call-button')));
      await tester.pump();

      expect(phoneCallService.calledPhone, '0812345678');
    });

    testWidgets('hides legacy voice call log messages', (tester) async {
      final chatDetailBloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
      );
      addTearDown(chatDetailBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: chatDetailBloc,
          ),
        ),
      );
      await tester.pump();

      streamController.add([
        ChatMessage(
          id: 'legacy-call-log',
          conversationId: 'conv-1',
          senderId: 'user-owner-1',
          message: '📞 โทรด้วยเสียง • ไม่ได้รับสาย',
          createdAt: DateTime.now(),
          isMine: false,
          isRead: false,
        ),
      ]);
      await tester.pump();

      expect(find.text('โทรด้วยเสียง'), findsNothing);
      expect(find.text('ไม่ได้รับสาย'), findsNothing);
    });

    testWidgets('displays streamed messages and handles message sending', (
      tester,
    ) async {
      final chatDetailBloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
      );
      addTearDown(chatDetailBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: chatDetailBloc,
          ),
        ),
      );
      await tester.pump();

      final message = ChatMessage(
        id: '1',
        conversationId: 'conv-1',
        senderId: 'user-owner-1',
        message: 'สวัสดีครับ สนใจรับของวันไหนดีครับ',
        createdAt: DateTime.now(),
        isMine: false,
        isRead: false,
      );

      streamController.add([message]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('สวัสดีครับ สนใจรับของวันไหนดีครับ'), findsOneWidget);

      // Send a reply
      await tester.enterText(
        find.byKey(const ValueKey('chat-message-field')),
        'สะดวกวันเสาร์นี้ครับ',
      );
      await tester.tap(find.byKey(const ValueKey('send-message-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(
        () => mockSendMessage(
          conversationId: 'conv-1',
          message: 'สะดวกวันเสาร์นี้ครับ',
          imageUrl: null,
        ),
      ).called(1);
    });

    testWidgets(
      'shows floating scroll-to-bottom arrow button when scrolled up and scrolls down on tap',
      (tester) async {
        final chatDetailBloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
        );
        addTearDown(chatDetailBloc.close);

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: chatDetailBloc,
            ),
          ),
        );
        await tester.pump();

        // Create 20 messages to make the list scrollable
        final messages = List.generate(
          20,
          (i) => ChatMessage(
            id: 'msg-$i',
            conversationId: 'conv-1',
            senderId: 'user-owner-1',
            message: 'ข้อความที่ $i ในห้องแชท',
            createdAt: DateTime.now().subtract(Duration(minutes: 20 - i)),
            isMine: i.isEven,
            isRead: true,
          ),
        );

        streamController.add(messages);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final scrollButtonFinder = find.byKey(
          const ValueKey('chat-scroll-to-bottom-button'),
        );
        expect(scrollButtonFinder, findsOneWidget);

        // At bottom, AnimatedScale has scale 0.0
        final AnimatedScale scaleWidgetInitial = tester.widget(
          find.ancestor(
            of: scrollButtonFinder,
            matching: find.byType(AnimatedScale),
          ),
        );
        expect(scaleWidgetInitial.scale, 0.0);

        // Scroll up by dragging down (because reverse: true, drag downwards to scroll to older messages)
        await tester.drag(
          find.byKey(const ValueKey('chat-message-list')),
          const Offset(0, 400),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final AnimatedScale scaleWidgetScrolled = tester.widget(
          find.ancestor(
            of: scrollButtonFinder,
            matching: find.byType(AnimatedScale),
          ),
        );
        expect(scaleWidgetScrolled.scale, 1.0);

        // Tap the scroll-to-bottom button
        await tester.tap(scrollButtonFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      },
    );

    testWidgets(
      'scrolls and highlights the exact target message among duplicate identical messages',
      (tester) async {
        final chatDetailBloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
        );
        addTearDown(chatDetailBloc.close);

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: chatDetailBloc,
            ),
          ),
        );
        await tester.pump();

        final msg1 = ChatMessage(
          id: 'dup-1',
          conversationId: 'conv-1',
          senderId: 'user-owner-1',
          message: 'สวัสดีครับ',
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
          isMine: false,
          isRead: true,
        );

        final msg2 = ChatMessage(
          id: 'dup-2',
          conversationId: 'conv-1',
          senderId: 'user-owner-1',
          message: 'สวัสดีครับ',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          isMine: false,
          isRead: true,
        );

        final replyToMsg2 = ChatMessage(
          id: 'reply-to-2',
          conversationId: 'conv-1',
          senderId: 'me',
          message: '↩ ตอบกลับ:chn.benmat|สวัสดีครับ|dup-2|\nตอบกลับอันที่ 2',
          createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
          isMine: true,
          isRead: true,
        );

        streamController.add([msg1, msg2, replyToMsg2]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tap the quote in reply message
        await tester.tap(find.text('สวัสดีครับ').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      },
    );

    testWidgets('renders delivery status at bottom left of latest message only', (
      tester,
    ) async {
      final chatDetailBloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
      );
      addTearDown(chatDetailBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: chatDetailBloc,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final msg1 = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: 'me',
        message: 'สวัสดีครับอันแรก',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        isMine: true,
        isRead: false,
      );

      final msg2 = ChatMessage(
        id: 'msg-2',
        conversationId: 'conv-1',
        senderId: 'me',
        message: 'สวัสดีครับอันที่สอง',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        isMine: true,
        isRead: false,
      );

      // Emit 2 unread messages sent by me
      streamController.add([msg1, msg2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Only msg2 (the latest sent by me) should show "ส่งแล้ว"
      expect(find.text('ส่งแล้ว'), findsOneWidget);
      expect(find.text('กำลังส่ง'), findsNothing);

      // Now update msg2 to be read (isRead: true)
      final msg2Read = ChatMessage(
        id: 'msg-2',
        conversationId: 'conv-1',
        senderId: 'me',
        message: 'สวัสดีครับอันที่สอง',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        isMine: true,
        isRead: true,
      );

      streamController.add([msg1, msg2Read]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Only msg2Read should show avatar delivery status icon and no "ส่งแล้ว" text
      expect(
        find.byKey(const ValueKey('chat-message-delivery-status')),
        findsOneWidget,
      );
      expect(find.text('ส่งแล้ว'), findsNothing);

      final pending = Completer<void>();
      when(
        () => mockSendMessage(
          conversationId: any(named: 'conversationId'),
          message: any(named: 'message'),
          imageUrl: any(named: 'imageUrl'),
        ),
      ).thenAnswer((_) => pending.future);
      chatDetailBloc.add(
        const ChatMessageSent(
          conversationId: 'conv-1',
          message: 'กำลังพิมพ์ส่งข้อความที่สาม',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The new latest sending message should show "กำลังส่ง"
      expect(find.text('กำลังส่ง'), findsOneWidget);
      expect(find.text('ส่งแล้ว'), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('กำลังส่ง'), findsNothing);
      expect(find.text('ส่งแล้ว'), findsOneWidget);
    });
  });

  group('ChatAvatar presence status indicator', () {
    testWidgets('renders green dot when isOnline is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatAvatar(
              asset: 'assets/images/user.png',
              size: 50,
              isOnline: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('avatar-status-online')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('avatar-status-offline')), findsNothing);

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('avatar-status-online')),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF10B981));
    });

    testWidgets('renders grey dot when isOnline is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatAvatar(
              asset: 'assets/images/user.png',
              size: 50,
              isOnline: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('avatar-status-offline')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('avatar-status-online')), findsNothing);

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('avatar-status-offline')),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF9CA3AF));
    });
  });

  group('CustomBottomNavbar unread badge', () {
    testWidgets(
      'renders red dot badge on chat tab when hasUnreadChat is true',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: CustomBottomNavbar(
                selectedIndex: 0,
                hasUnreadChat: true,
                onTabChange: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('chat-unread-badge')), findsWidgets);
      },
    );

    testWidgets('does not render red dot badge when hasUnreadChat is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CustomBottomNavbar(
              selectedIndex: 0,
              hasUnreadChat: false,
              onTabChange: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('chat-unread-badge')), findsNothing);
    });
  });

  group('ChatConversationModel.formatTimeLabel', () {
    test('formats today messages with exact clock time HH:mm', () {
      final now = DateTime.now();
      final todayTime = DateTime(now.year, now.month, now.day, 14, 30);
      expect(ChatConversationModel.formatTimeLabel(todayTime), '14:30');
    });

    test('formats yesterday messages as เมื่อวาน', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(ChatConversationModel.formatTimeLabel(yesterday), 'เมื่อวาน');
    });
  });

  group('InAppNotificationBanner', () {
    testWidgets('renders sender name, message and triggers onTap when tapped', (
      tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppNotificationBanner(
              conversation: sampleConversation1,
              message: 'สะดวกวันเสาร์นี้ไหมครับ',
              onTap: () => tapped = true,
              onDismiss: () {},
              duration: const Duration(seconds: 3),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('สมชาย เจ้าของกล้อง'), findsOneWidget);
      expect(find.text('สะดวกวันเสาร์นี้ไหมครับ'), findsOneWidget);
      expect(find.text('ข้อความใหม่'), findsOneWidget);
      expect(find.text('Sony Alpha A7 IV'), findsOneWidget);

      // Tap banner
      await tester.tap(find.text('สะดวกวันเสาร์นี้ไหมครับ'));
      expect(tapped, isTrue);
    });

    testWidgets(
      'renders only the actual reply text without reply prefix in banner',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InAppNotificationBanner(
                conversation: sampleConversation1,
                message:
                    '↩ ตอบกลับ:chn.benmat|สวัสดีครับ|102|\nตกลงตามนี้ครับผม',
                onTap: () {},
                onDismiss: () {},
                duration: const Duration(seconds: 3),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ตกลงตามนี้ครับผม'), findsOneWidget);
        expect(find.textContaining('↩ ตอบกลับ:'), findsNothing);
      },
    );

    testWidgets('automatically dismisses after duration expires', (
      tester,
    ) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppNotificationBanner(
              conversation: sampleConversation1,
              message: 'ข้อความแจ้งเตือน',
              onTap: () {},
              onDismiss: () => dismissed = true,
              duration: const Duration(seconds: 3),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto dismiss after 3 seconds
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('dismisses when close icon is tapped', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppNotificationBanner(
              conversation: sampleConversation1,
              message: 'สวัสดีครับ',
              onTap: () {},
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });

  group('ActiveConversationTracker', () {
    test('tracks and clears active conversation ID', () {
      final tracker = ActiveConversationTracker.instance;
      expect(tracker.isConversationActive('conv-test'), isFalse);

      tracker.setActive('conv-test');
      expect(tracker.isConversationActive('conv-test'), isTrue);
      expect(tracker.activeConversationId, 'conv-test');

      tracker.clearActive('conv-test');
      expect(tracker.isConversationActive('conv-test'), isFalse);
      expect(tracker.activeConversationId, isNull);
    });
  });

  group('GlobalChatNotificationListener', () {
    late _MockChatRemoteDataSource mockChatDataSource;
    late _MockChatNotificationService mockNotificationService;
    late StreamController<List<IncomingChatMessageData>> msgStreamController;

    setUp(() {
      mockChatDataSource = _MockChatRemoteDataSource();
      mockNotificationService = _MockChatNotificationService();
      msgStreamController =
          StreamController<List<IncomingChatMessageData>>.broadcast();

      when(
        () => mockChatDataSource.streamIncomingMessages(),
      ).thenAnswer((_) => msgStreamController.stream);
      when(() => mockNotificationService.initialize()).thenAnswer((_) async {});
      when(
        () => mockNotificationService.playMessageSound(),
      ).thenAnswer((_) async {});
      when(
        () => mockNotificationService.showSystemNotification(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});
    });

    tearDown(() {
      msgStreamController.close();
      ActiveConversationTracker.instance.clearActive();
    });

    testWidgets('plays sound and renders in-app banner when message arrives', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlobalChatNotificationListener(
              dataSource: mockChatDataSource,
              notificationService: mockNotificationService,
              child: const Text('Home Content'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Home Content'), findsOneWidget);
      expect(find.text('ข้อความใหม่'), findsNothing);

      // Incoming message arrives
      final incoming = IncomingChatMessageData(
        id: 'msg-new-1',
        conversationId: 'conv-1',
        senderId: 'user-owner-1',
        message: 'มีกล้องว่างพร้อมให้เช่าครับ',
        imageUrl: null,
        createdAt: DateTime.now(),
        conversation: sampleConversation1,
      );

      msgStreamController.add([incoming]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      verify(() => mockNotificationService.playMessageSound()).called(1);
      expect(find.text('สมชาย เจ้าของกล้อง'), findsOneWidget);
      expect(find.text('มีกล้องว่างพร้อมให้เช่าครับ'), findsOneWidget);
    });

    testWidgets(
      'does not show in-app banner if conversation is already active',
      (tester) async {
        ActiveConversationTracker.instance.setActive('conv-1');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GlobalChatNotificationListener(
                dataSource: mockChatDataSource,
                notificationService: mockNotificationService,
                child: const Text('Home Content'),
              ),
            ),
          ),
        );
        await tester.pump();

        final incoming = IncomingChatMessageData(
          id: 'msg-new-2',
          conversationId: 'conv-1',
          senderId: 'user-owner-1',
          message: 'ข้อความในห้องที่เปิดอยู่',
          imageUrl: null,
          createdAt: DateTime.now(),
          conversation: sampleConversation1,
        );

        msgStreamController.add([incoming]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        verifyNever(() => mockNotificationService.playMessageSound());
        expect(find.text('ข้อความใหม่'), findsNothing);
      },
    );
  });

  group('ChatImagePreviewModal', () {
    testWidgets('renders images count, caption field, and send button', (
      tester,
    ) async {
      final mockFile1 = XFile('test1.jpg');
      final mockFile2 = XFile('test2.jpg');

      List<XFile>? sentImages;
      String? sentCaption;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatImagePreviewModal(
              images: [mockFile1, mockFile2],
              onSend: (images, caption) {
                sentImages = images;
                sentCaption = caption;
              },
              onAddMore: () async => [],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ส่งรูปภาพ (2 รูป)'), findsOneWidget);
      expect(find.text('ส่ง (2)'), findsOneWidget);
      expect(find.text('เพิ่มรูป'), findsOneWidget);

      // Enter caption
      await tester.enterText(
        find.byType(TextField),
        'รูปสภาพสินค้าก่อนส่งมอบครับ',
      );
      await tester.pump();

      // Tap send
      await tester.tap(find.text('ส่ง (2)'));
      await tester.pump();

      expect(sentImages?.length, 2);
      expect(sentCaption, 'รูปสภาพสินค้าก่อนส่งมอบครับ');
    });

    testWidgets(
      'removes image and updates count when remove button is tapped',
      (tester) async {
        final mockFile1 = XFile('test1.jpg');
        final mockFile2 = XFile('test2.jpg');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatImagePreviewModal(
                images: [mockFile1, mockFile2],
                onSend: (_, _) {},
                onAddMore: () async => [],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('ส่งรูปภาพ (2 รูป)'), findsOneWidget);

        // Remove the first image
        final closeButtons = find.byIcon(Icons.close_rounded);
        await tester.tap(closeButtons.at(1)); // first thumbnail close button
        await tester.pump();

        expect(find.text('ส่งรูปภาพ (1 รูป)'), findsOneWidget);
        expect(find.text('ส่ง (1)'), findsOneWidget);
      },
    );
  });

  group('ChatDetailBloc Multi-Image Upload', () {
    late _MockStreamMessagesUseCase mockStreamMessages;
    late _MockSendChatMessageUseCase mockSendMessage;
    late _MockUploadChatImageUseCase mockUploadChatImage;

    setUp(() {
      mockStreamMessages = _MockStreamMessagesUseCase();
      mockSendMessage = _MockSendChatMessageUseCase();
      mockUploadChatImage = _MockUploadChatImageUseCase();
    });

    test(
      'ChatMultipleImagesUploadedAndSent uploads all images and sends messages',
      () async {
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          uploadChatImage: mockUploadChatImage,
        );

        when(
          () => mockUploadChatImage.call(
            conversationId: 'conv-1',
            imageBytes: any(named: 'imageBytes'),
            fileName: any(named: 'fileName'),
          ),
        ).thenAnswer(
          (invocation) async =>
              'https://storage.example.com/${invocation.namedArguments[#fileName]}',
        );

        when(
          () => mockSendMessage.call(
            conversationId: 'conv-1',
            message: any(named: 'message'),
            imageUrl: any(named: 'imageUrl'),
          ),
        ).thenAnswer((_) async {});

        final image1 = ChatImageData(
          imageBytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'photo1.jpg',
        );
        final image2 = ChatImageData(
          imageBytes: Uint8List.fromList([4, 5, 6]),
          fileName: 'photo2.jpg',
        );

        bloc.add(
          ChatMultipleImagesUploadedAndSent(
            conversationId: 'conv-1',
            images: [image1, image2],
            caption: 'คำอธิบายรูป',
          ),
        );

        await expectLater(
          bloc.stream,
          emitsInOrder([
            ChatDetailState(isUploadingImage: true),
            ChatDetailState(isUploadingImage: false),
          ]),
        );

        verify(
          () => mockUploadChatImage.call(
            conversationId: 'conv-1',
            imageBytes: image1.imageBytes,
            fileName: 'photo1.jpg',
          ),
        ).called(1);

        verify(
          () => mockUploadChatImage.call(
            conversationId: 'conv-1',
            imageBytes: image2.imageBytes,
            fileName: 'photo2.jpg',
          ),
        ).called(1);

        verify(
          () => mockSendMessage.call(
            conversationId: 'conv-1',
            message: '📷 ส่งรูปภาพ',
            imageUrl: 'https://storage.example.com/photo1.jpg',
          ),
        ).called(1);

        verify(
          () => mockSendMessage.call(
            conversationId: 'conv-1',
            message: 'คำอธิบายรูป',
            imageUrl: 'https://storage.example.com/photo2.jpg',
          ),
        ).called(1);

        await bloc.close();
      },
    );
  });

  group('ChatPinService & ConversationActionSheet', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'ChatPinService only allows 1 pinned conversation at a time',
      () async {
        final pinService = ChatPinService.instance;
        await pinService.init();

        expect(pinService.pinnedConversationId, isNull);
        expect(pinService.isPinned('conv-1'), isFalse);

        await pinService.togglePin('conv-1');
        expect(pinService.pinnedConversationId, 'conv-1');
        expect(pinService.isPinned('conv-1'), isTrue);

        // Pin another conversation -> should replace previous (max 1 chat rule)
        await pinService.togglePin('conv-2');
        expect(pinService.pinnedConversationId, 'conv-2');
        expect(pinService.isPinned('conv-1'), isFalse);
        expect(pinService.isPinned('conv-2'), isTrue);

        // Toggle same conversation -> unpins
        await pinService.togglePin('conv-2');
        expect(pinService.pinnedConversationId, isNull);
        expect(pinService.isPinned('conv-2'), isFalse);
      },
    );

    testWidgets(
      'ConversationActionSheet renders all options and triggers callbacks',
      (tester) async {
        bool pinToggled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    ConversationActionSheet.show(
                      ctx,
                      conversation: sampleConversation1,
                      onTogglePin: () {
                        pinToggled = true;
                      },
                      onDelete: () {},
                    );
                  },
                  child: const Text('Open Actions'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Actions'));
        await tester.pumpAndSettle();

        expect(find.text('ปักหมุด'), findsOneWidget);
        expect(find.text('ลบ'), findsOneWidget);
        expect(find.text('เก็บถาวร'), findsNothing);
        expect(find.text('เปิดฟองสบู่แชท'), findsNothing);
        expect(find.text('ทำเครื่องหมายว่ายังไม่ได้อ่าน'), findsNothing);

        await tester.tap(find.text('ปักหมุด'));
        await tester.pumpAndSettle();
        expect(pinToggled, isTrue);
      },
    );
  });

  group('ChatMessageActionSheet & StackedImagesGridScreen', () {
    testWidgets(
      'ChatMessageActionSheet displays message actions without emojis and supports image saving',
      (tester) async {
        bool replied = false;

        final myMessage = ChatMessage(
          id: 'msg-1',
          conversationId: 'conv-1',
          senderId: 'my-user-id',
          message: 'สวัสดีครับ ยืมของหน่อย',
          createdAt: DateTime(2026, 8, 16, 10, 0),
          isMine: true,
          isRead: true,
          imageUrl: 'https://example.com/photo.jpg',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    ChatMessageActionSheet.show(
                      ctx,
                      message: myMessage,
                      imageUrls: ['https://example.com/photo.jpg'],
                      onReply: () => replied = true,
                      onEdit: () {},
                      onDelete: () {},
                      onSaveImage: () {},
                    );
                  },
                  child: const Text('Show Message Sheet'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Message Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('❤️'), findsNothing);
        expect(find.text('👍'), findsNothing);
        expect(find.text('ตอบกลับ'), findsOneWidget);
        expect(find.text('บันทึกภาพ'), findsOneWidget);
        expect(find.text('คัดลอก'), findsOneWidget);
        expect(find.text('แก้ไข'), findsOneWidget);
        expect(find.text('ลบ'), findsOneWidget);

        // Tap Reply
        await tester.tap(find.text('ตอบกลับ'));
        await tester.pumpAndSettle();
        expect(replied, isTrue);
      },
    );

    testWidgets(
      'StackedImagesGridScreen renders 2-column image count header without 3 dots',
      (tester) async {
        final images = [
          'https://example.com/img1.jpg',
          'https://example.com/img2.jpg',
          'https://example.com/img3.jpg',
        ];

        await tester.pumpWidget(
          MaterialApp(home: StackedImagesGridScreen(imageUrls: images)),
        );

        expect(find.text('3 รูป'), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsOneWidget);
        expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      },
    );
  });

  group('Real-Time Chat & Global Presence Architecture (LINE & Messenger)', () {
    late _MockStreamMessagesUseCase mockStreamMessages;
    late _MockSendChatMessageUseCase mockSendMessage;
    late StreamController<List<ChatMessage>> streamController;

    setUp(() {
      ChatMessagesCache.clear();
      mockStreamMessages = _MockStreamMessagesUseCase();
      mockSendMessage = _MockSendChatMessageUseCase();
      streamController = StreamController<List<ChatMessage>>.broadcast();
      when(
        () => mockStreamMessages(any()),
      ).thenAnswer((_) => streamController.stream);
    });

    tearDown(() {
      streamController.close();
      ChatMessagesCache.clear();
    });

    testWidgets('Typing indicator updates header and shows typing bubble', (
      tester,
    ) async {
      final bloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
        conversationId: sampleConversation1.id,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: bloc,
          ),
        ),
      );
      await tester.pump();

      // Initially not typing
      expect(
        find.byKey(const ValueKey('chat-header-typing-status')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chat-typing-indicator-bubble')),
        findsNothing,
      );

      // Other user starts typing
      bloc.add(const ChatTypingStatusUpdated(true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('chat-header-typing-status')),
        findsOneWidget,
      );
      expect(find.text('กำลังพิมพ์...'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-typing-indicator-bubble')),
        findsOneWidget,
      );

      // Other user stops typing
      bloc.add(const ChatTypingStatusUpdated(false));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('chat-header-typing-status')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chat-typing-indicator-bubble')),
        findsNothing,
      );
    });

    testWidgets('ChatReadReceiptsUpdated marks sent messages as read', (
      tester,
    ) async {
      final bloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
        conversationId: sampleConversation1.id,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: bloc,
          ),
        ),
      );

      // Deliver an unread sent message
      final msg = ChatMessage(
        id: 'msg-1',
        conversationId: sampleConversation1.id,
        senderId: 'my-user-id',
        message: 'สวัสดีครับ',
        createdAt: DateTime.now(),
        isMine: true,
        isRead: false,
      );

      bloc.add(ChatMessagesUpdated([msg]));
      await tester.pumpAndSettle();

      expect(find.text('ส่งแล้ว'), findsOneWidget);

      // Receive read receipt from other user -> displays avatar icon
      bloc.add(ChatReadReceiptsUpdated(sampleConversation1.id));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat-message-delivery-status')),
        findsOneWidget,
      );
      expect(find.text('ส่งแล้ว'), findsNothing);
    });

    testWidgets(
      'Renders reply UI for text and image quotes and handles scroll on tap',
      (tester) async {
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation1.id,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: bloc,
            ),
          ),
        );

        final originalMsg = ChatMessage(
          id: 'msg-origin-1',
          conversationId: sampleConversation1.id,
          senderId: sampleConversation1.otherUserId,
          message: 'กล้องตัวนี้พร้อมให้เช่าครับ',
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
          isMine: false,
        );

        final replyMsg = ChatMessage(
          id: 'msg-reply-1',
          conversationId: sampleConversation1.id,
          senderId: 'my-user-id',
          message:
              '↩ ตอบกลับ:สมชาย เจ้าของกล้อง|กล้องตัวนี้พร้อมให้เช่าครับ|msg-origin-1|\nรับทราบครับ เดี๋ยวเข้าไปรับ',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          isMine: true,
        );

        bloc.add(ChatMessagesUpdated([originalMsg, replyMsg]));
        await tester.pumpAndSettle();

        expect(find.text('คุณตอบกลับสมชาย เจ้าของกล้อง'), findsOneWidget);
        expect(
          find.text('กล้องตัวนี้พร้อมให้เช่าครับ'),
          findsNWidgets(2),
        ); // Original + Quoted
        expect(find.text('รับทราบครับ เดี๋ยวเข้าไปรับ'), findsOneWidget);

        // Tap on quoted text to scroll to original
        await tester.tap(find.text('กล้องตัวนี้พร้อมให้เช่าครับ').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'sending a reply to multiline text preserves the answer and quote ID',
      (tester) async {
        when(
          () => mockSendMessage(
            conversationId: any(named: 'conversationId'),
            message: any(named: 'message'),
            imageUrl: any(named: 'imageUrl'),
          ),
        ).thenAnswer((_) async {});
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation1.id,
        );
        addTearDown(bloc.close);
        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: bloc,
            ),
          ),
        );
        await tester.pump();
        final original = ChatMessage(
          id: 'multiline-origin',
          conversationId: sampleConversation1.id,
          senderId: sampleConversation1.otherUserId,
          message: 'รายละเอียด\nหลายบรรทัด | พร้อมให้เช่า',
          createdAt: DateTime(2026, 10, 20),
          isMine: false,
        );
        bloc.add(ChatMessagesUpdated([original]));
        await tester.pumpAndSettle();
        await tester.longPress(find.text(original.message));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ตอบกลับ'));
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียด หลายบรรทัด พร้อมให้เช่า'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('chat-message-field')),
          'ตกลงครับ\nขอรับช่วงเช้า',
        );
        await tester.tap(find.byKey(const ValueKey('send-message-button')));
        await tester.pumpAndSettle();
        final payload =
            verify(
                  () => mockSendMessage(
                    conversationId: sampleConversation1.id,
                    message: captureAny(named: 'message'),
                    imageUrl: any(named: 'imageUrl'),
                  ),
                ).captured.single
                as String;
        final reply = ChatReplyContent.tryParse(payload)!;
        expect(reply.text, 'ตกลงครับ\nขอรับช่วงเช้า');
        expect(reply.quotedMessageId, original.id);
        expect(reply.quotedText, 'รายละเอียด หลายบรรทัด พร้อมให้เช่า');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Failed message shows error status and allows retry', (
      tester,
    ) async {
      when(
        () => mockSendMessage(
          conversationId: any(named: 'conversationId'),
          message: any(named: 'message'),
          imageUrl: any(named: 'imageUrl'),
        ),
      ).thenThrow(Exception('Network error'));

      final bloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
        conversationId: sampleConversation1.id,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatDetailScreen(
            conversation: sampleConversation1,
            chatDetailBloc: bloc,
          ),
        ),
      );

      final textField = find.byKey(const ValueKey('chat-message-field'));
      final sendButton = find.byKey(const ValueKey('send-message-button'));

      await tester.enterText(textField, 'ทดสอบส่งข้อความล้มเหลว');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(find.text('ส่งไม่สำเร็จ'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-message-failed-status')),
        findsOneWidget,
      );

      // Now mock successful retry
      when(
        () => mockSendMessage(
          conversationId: any(named: 'conversationId'),
          message: any(named: 'message'),
          imageUrl: any(named: 'imageUrl'),
        ),
      ).thenAnswer((_) async {});

      await tester.tap(
        find.byKey(const ValueKey('chat-message-failed-status')),
      );
      await tester.pumpAndSettle();

      verify(
        () => mockSendMessage(
          conversationId: sampleConversation1.id,
          message: 'ทดสอบส่งข้อความล้มเหลว',
          imageUrl: null,
        ),
      ).called(2);
    });

    testWidgets(
      'ChatDetailScreen displays rental request button on item inquiry card for owner',
      (tester) async {
        final getOwnedItemIds = _MockGetOwnedChatItemIdsUseCase();
        when(() => getOwnedItemIds({2})).thenAnswer((_) async => {2});
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation2.id,
          getOwnedItemIds: getOwnedItemIds,
        );

        const inquiry = ItemInquiryData(
          itemId: 2,
          itemName: 'เต็นท์ Coleman 4 คน',
          price: 500,
          unitLabel: 'วัน',
        );
        final inquiryMsg = ChatMessage(
          id: 'msg-inq-1',
          conversationId: sampleConversation2.id,
          senderId: 'user-renter-1',
          message: inquiry.toChatMessagePayload(),
          createdAt: DateTime.now(),
          isMine: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation2,
              chatDetailBloc: bloc,
            ),
          ),
        );

        bloc.add(ChatMessagesUpdated([inquiryMsg]));
        await tester.pumpAndSettle();

        // Owner should see the rental offer button on the inquiry card
        expect(
          find.byKey(const ValueKey('inquiry-send-request-2')),
          findsOneWidget,
        );
        expect(find.text('สร้างข้อเสนอการเช่า / นัดรับ'), findsOneWidget);
      },
    );

    testWidgets(
      'Sender of Item Inquiry message can long-press and delete the message',
      (tester) async {
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation1.id,
        );

        final inquiryData = const ItemInquiryData(
          itemId: 1,
          itemName: 'Sony Alpha A7 IV',
          price: 500,
          unitLabel: 'ชั่วโมง',
        );

        final inquiryMsg = ChatMessage(
          id: 'msg-inquiry-1',
          conversationId: sampleConversation1.id,
          senderId: 'my-user-id',
          message: inquiryData.toChatMessagePayload(),
          createdAt: DateTime.now(),
          isMine: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: bloc,
            ),
          ),
        );

        bloc.add(ChatMessagesUpdated([inquiryMsg]));
        await tester.pumpAndSettle();

        expect(
          find.text('ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:'),
          findsOneWidget,
        );

        // Long press on the item inquiry card
        await tester.longPress(
          find.text('ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:'),
        );
        await tester.pumpAndSettle();

        // Action sheet should appear with Delete button
        expect(find.text('ลบ'), findsOneWidget);

        // Tap Delete button
        await tester.tap(find.text('ลบ'));
        await tester.pumpAndSettle();

        // Confirm dialog should appear
        expect(find.text('ยกเลิกการส่งข้อความนี้หรือไม่?'), findsOneWidget);
        expect(find.text('ลบสำหรับทุกคน'), findsOneWidget);

        // Tap confirm delete
        await tester.tap(find.text('ลบสำหรับทุกคน'));
        await tester.pumpAndSettle();

        // Message should be removed from view
        expect(
          find.text('ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Rental request button re-appears when renter sends a new item inquiry after previous booking request',
      (tester) async {
        final getOwnedItemIds = _MockGetOwnedChatItemIdsUseCase();
        when(() => getOwnedItemIds({10})).thenAnswer((_) async => {10});
        when(() => getOwnedItemIds({25})).thenAnswer((_) async => {25});
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation2.id,
          getOwnedItemIds: getOwnedItemIds,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation2,
              chatDetailBloc: bloc,
            ),
          ),
        );

        // Step 1: Initial item inquiry
        final inquiry1 = const ItemInquiryData(
          itemId: 10,
          itemName: 'กล้อง Canon EOS R5',
          price: 1000,
          unitLabel: 'วัน',
        );
        final inquiryMsg1 = ChatMessage(
          id: 'msg-inq-1',
          conversationId: sampleConversation2.id,
          senderId: 'user-renter-1',
          message: inquiry1.toChatMessagePayload(),
          createdAt: DateTime(2026, 9, 1, 10, 0),
          isMine: false,
        );

        // Step 2: Owner sent booking request for inquiry 1
        final bookingData1 = BookingRequestData(
          item: const BookingItemInfo(
            id: 10,
            title: 'กล้อง Canon EOS R5',
            imageUrl: '',
            rating: 5.0,
            reviewCount: 2,
            hourlyRate: 150,
            dailyRate: 1000,
            defaultLocation: 'กรุงเทพ',
            ownerName: 'วิภาวี',
          ),
          startDate: DateTime(2026, 9, 2),
          endDate: DateTime(2026, 9, 3),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          location: 'กรุงเทพ',
          conversationId: sampleConversation2.id,
        );
        final bookingMsg1 = ChatMessage(
          id: 'msg-book-1',
          conversationId: sampleConversation2.id,
          senderId: 'my-owner-id',
          message: bookingData1.toChatMessagePayload(),
          createdAt: DateTime(2026, 9, 1, 10, 5),
          isMine: true,
        );

        // Deliver inquiry 1 + booking 1 -> button should be hidden
        bloc.add(ChatMessagesUpdated([inquiryMsg1, bookingMsg1]));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat-floating-rental-request-button')),
          findsNothing,
        );

        // Step 3: Renter comes back and inquires about a NEW item (or same item again)
        final inquiry2 = const ItemInquiryData(
          itemId: 25,
          itemName: 'เลนส์ Canon RF 24-70mm',
          price: 600,
          unitLabel: 'วัน',
        );
        final inquiryMsg2 = ChatMessage(
          id: 'msg-inq-2',
          conversationId: sampleConversation2.id,
          senderId: 'user-renter-1',
          message: inquiry2.toChatMessagePayload(),
          createdAt: DateTime(2026, 9, 4, 12, 0),
          isMine: false,
        );

        // Deliver new inquiry after booking request
        bloc.add(ChatMessagesUpdated([inquiryMsg1, bookingMsg1, inquiryMsg2]));
        await tester.pumpAndSettle();

        // Button should appear on the new inquiry card!
        expect(
          find.byKey(const ValueKey('inquiry-send-request-25')),
          findsOneWidget,
        );
        expect(find.text('สร้างข้อเสนอการเช่า / นัดรับ'), findsWidgets);
      },
    );

    testWidgets(
      'Renter cannot create rental offers from the item inquiry card',
      (tester) async {
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation1.id,
        );

        const inquiry = ItemInquiryData(
          itemId: 1,
          itemName: 'Sony Alpha A7 IV',
          price: 1200,
          unitLabel: 'วัน',
        );
        final inquiryMsg = ChatMessage(
          id: 'msg-inq-renter-1',
          conversationId: sampleConversation1.id,
          senderId: 'my-renter-id',
          message: inquiry.toChatMessagePayload(),
          createdAt: DateTime.now(),
          isMine: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: bloc,
            ),
          ),
        );

        bloc.add(ChatMessagesUpdated([inquiryMsg]));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('inquiry-send-request-1')),
          findsNothing,
        );
        expect(find.text('ส่งคำขอเช่าอุปกรณ์นี้'), findsNothing);
      },
    );

    testWidgets('Chat avatar opens the counterpart profile with its user ID', (
      tester,
    ) async {
      final bloc = ChatDetailBloc(
        streamMessages: mockStreamMessages,
        sendMessage: mockSendMessage,
        conversationId: sampleConversation1.id,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: bloc,
            ),
          ),
          GoRoute(
            path: AppRoutes.userProfileView,
            builder: (_, state) {
              final args = state.extra! as UserProfileViewArgs;
              return Scaffold(
                body: Text('profile:${args.userId}:${args.displayName}'),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      streamController.add(const []);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-profile-avatar')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'profile:${sampleConversation1.otherUserId}:${sampleConversation1.name}',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'Owner receives confirmation for the exact offer through the shared message stream',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation2.id,
        );
        final data = BookingRequestData(
          item: const BookingItemInfo(
            id: 2,
            title: 'Test tent',
            imageUrl: '',
            rating: 5,
            reviewCount: 1,
            hourlyRate: 100,
            dailyRate: 500,
            defaultLocation: 'Pickup',
          ),
          startDate: DateTime(2026, 10, 18),
          endDate: DateTime(2026, 10, 19),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          location: 'Pickup',
        );
        ChatMessage offer(String id, BookingRequestData data) => ChatMessage(
          id: id,
          conversationId: sampleConversation2.id,
          senderId: 'owner',
          message: data.toChatMessagePayload(),
          createdAt: DateTime(2026, 10, 17),
          isMine: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation2,
              chatDetailBloc: bloc,
            ),
          ),
        );
        streamController.add([offer('offer-1', data), offer('offer-2', data)]);
        await tester.pumpAndSettle();
        expect(find.text('แก้ไขรายละเอียด'), findsNWidgets(2));
        streamController.add([
          offer('offer-1', data.copyWith(bookingId: 25, status: 'confirmed')),
          offer('offer-2', data),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียดนัดรับ'), findsOneWidget);
        expect(find.text('แก้ไขรายละเอียด'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'Offer receiver can confirm and sender can edit regardless of conversation roles',
      (tester) async {
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation2.id,
        );

        final bookingData = BookingRequestData(
          item: const BookingItemInfo(
            id: 2,
            title: 'เต็นท์ Coleman 4 คน',
            imageUrl: '',
            rating: 5.0,
            reviewCount: 2,
            hourlyRate: 100,
            dailyRate: 500,
            defaultLocation: 'กรุงเทพ',
            ownerName: 'ฉัน',
          ),
          startDate: DateTime(2026, 9, 2),
          endDate: DateTime(2026, 9, 3),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          location: 'กรุงเทพ',
          conversationId: sampleConversation2.id,
        );

        // ผู้รับข้อเสนอเป็นลูกค้าของสินค้านี้ แม้บทบาทเดิมของห้องแชตจะสลับกัน
        final receivedBookingMsg = ChatMessage(
          id: 'msg-book-received',
          conversationId: sampleConversation2.id,
          senderId: 'user-renter-1',
          message: bookingData.toChatMessagePayload(),
          createdAt: DateTime.now(),
          isMine: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation2,
              chatDetailBloc: bloc,
            ),
          ),
        );

        bloc.add(ChatMessagesUpdated([receivedBookingMsg]));
        await tester.pumpAndSettle();

        expect(find.text('ตรวจสอบคำขอเช่า'), findsOneWidget);
        expect(find.text('ตรวจสอบและยอมรับคำขอเช่า'), findsNothing);

        // ทดสอบเมื่อ Owner เป็นคนส่งข้อเสนอเอง (isMine: true) -> ต้องเห็นปุ่มแก้ไขรายละเอียด
        final sentBookingMsg = ChatMessage(
          id: 'msg-book-sent',
          conversationId: sampleConversation2.id,
          senderId: 'my-owner-id',
          message: bookingData.toChatMessagePayload(),
          createdAt: DateTime.now(),
          isMine: true,
        );

        bloc.add(ChatMessagesUpdated([sentBookingMsg]));
        await tester.pumpAndSettle();

        expect(find.text('แก้ไขรายละเอียด'), findsOneWidget);
      },
    );

    testWidgets(
      'Displays active and completed rental status in the chat card without a banner',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final bloc = ChatDetailBloc(
          streamMessages: mockStreamMessages,
          sendMessage: mockSendMessage,
          conversationId: sampleConversation1.id,
        );

        final now = DateTime.now();
        final bookingData = BookingRequestData(
          item: const BookingItemInfo(
            id: 99,
            title: 'ฟิกเกอร์ โกะโจ x เกะโท',
            imageUrl: '',
            rating: 5.0,
            reviewCount: 1,
            hourlyRate: 100,
            dailyRate: 200,
            defaultLocation: 'นัดรับตามตกลง',
            ownerName: 'eiei',
          ),
          rentalType: BookingRentalType.daily,
          startDate: DateTime(now.year, now.month, now.day),
          endDate: DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 1)),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          location: 'นัดรับตามตกลง',
          locationNote: '',
          paymentMethod: 'cash',
          bookingId: 2065,
        );

        final bookingMsg = ChatMessage(
          id: 'msg-book-1',
          conversationId: sampleConversation1.id,
          senderId: sampleConversation1.otherUserId,
          message: bookingData.toChatMessagePayload(),
          createdAt: now.subtract(const Duration(minutes: 5)),
          isMine: false,
        );

        final handoverMsg = ChatMessage(
          id: 'msg-handover-1',
          conversationId: sampleConversation1.id,
          senderId: 'my-user-id',
          message: '✅ ยืนยันการส่งมอบอุปกรณ์เรียบร้อยแล้ว เริ่มต้นช่วงเวลาเช่า',
          createdAt: now,
          isMine: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ChatDetailScreen(
              conversation: sampleConversation1,
              chatDetailBloc: bloc,
            ),
          ),
        );

        bloc.add(ChatMessagesUpdated([bookingMsg, handoverMsg]));
        await tester.pumpAndSettle();

        expect(find.textContaining('กำลังเช่า:'), findsNothing);
        expect(
          find.byKey(const ValueKey('chat-booking-return-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat-booking-rental-status-button')),
          findsNothing,
        );
        expect(find.text('ดูจุดนัดส่งคืนบนแผนที่'), findsNothing);

        final completedMessage = ChatMessage(
          id: bookingMsg.id,
          conversationId: bookingMsg.conversationId,
          senderId: bookingMsg.senderId,
          message: bookingData
              .copyWith(status: 'completed')
              .toChatMessagePayload(),
          createdAt: bookingMsg.createdAt,
          isMine: bookingMsg.isMine,
        );
        bloc.add(ChatMessagesUpdated([completedMessage, handoverMsg]));
        await tester.pumpAndSettle();
        expect(find.text('การเช่าเสร็จสิ้น'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-booking-return-button')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(bloc.close);
      },
    );
  });
}

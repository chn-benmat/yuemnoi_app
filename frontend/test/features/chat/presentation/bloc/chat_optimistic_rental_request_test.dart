import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_event.dart';
import 'package:mocktail/mocktail.dart';

class _Send extends Mock implements SendChatMessageUseCase {}

class _Stream extends Mock implements StreamMessagesUseCase {}

void main() {
  test(
    'chat connection failure explains what to do without technical error',
    () async {
      final stream = _Stream();
      final controller = StreamController<List<ChatMessage>>();
      when(() => stream('room')).thenAnswer((_) => controller.stream);
      final bloc = ChatDetailBloc(streamMessages: stream, sendMessage: _Send());
      addTearDown(() async {
        await bloc.close();
        await controller.close();
      });

      bloc.add(const ChatMessagesSubscriptionRequested('room'));
      await pumpEventQueue();
      controller.addError(Exception('RealtimeSubscribeException code 1006'));
      await pumpEventQueue();

      expect(bloc.state.errorMessage, contains('ตรวจสอบอินเทอร์เน็ต'));
      expect(bloc.state.errorMessage, contains('ตรวจสอบสถานะการเช่า'));
      expect(
        bloc.state.errorMessage,
        isNot(contains('RealtimeSubscribeException')),
      );
    },
  );

  test('server-normalized booking replaces optimistic card', () async {
    final send = _Send();
    when(
      () => send(
        conversationId: 'room',
        message: any(named: 'message'),
        imageUrl: null,
      ),
    ).thenAnswer((_) async {});
    final bloc = ChatDetailBloc(streamMessages: _Stream(), sendMessage: send);
    const payload = 'offer [BOOKING_DATA:{"itemId":1,"location":"Bangkok"}]';
    bloc.add(const ChatMessageSent(conversationId: 'room', message: payload));
    await pumpEventQueue();
    bloc.add(
      ChatMessagesUpdated([
        ChatMessage(
          id: 'saved',
          conversationId: 'room',
          senderId: 'me',
          message:
              'offer [BOOKING_DATA:${jsonEncode({"location": "Bangkok", "status": "pending", "itemId": 1, "originalMessageId": "saved", "latitude": 13.7, "longitude": 100.4, "locationNote": "snapshot"})}]',
          createdAt: DateTime(2026),
          isMine: true,
        ),
      ]),
    );
    await pumpEventQueue();
    final ids = bloc.state.messages.map((m) => m.id).toList();
    await bloc.close();
    expect(ids, ['saved']);
  });

  test(
    'rental card appears before saving, keeps its image, and retries without duplication',
    () async {
      final send = _Send();
      final gate = Completer<void>();
      when(
        () => send(
          conversationId: any(named: 'conversationId'),
          message: any(named: 'message'),
          imageUrl: any(named: 'imageUrl'),
        ),
      ).thenAnswer((_) => gate.future);
      final bloc = ChatDetailBloc(streamMessages: _Stream(), sendMessage: send);
      addTearDown(bloc.close);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      const payload =
          '📋 คำขอเช่าอุปกรณ์\nอุปกรณ์: Canon EOS R50\n[BOOKING_DATA:{"itemId":1}]';
      const image = 'https://example.test/camera.jpg';
      bloc.add(
        const ChatMessageSent(
          conversationId: 'room',
          message: payload,
          imageUrl: image,
        ),
      );
      bloc.add(
        const ChatMessageSent(
          conversationId: 'room',
          message: payload,
          imageUrl: image,
        ),
      );
      await pumpEventQueue();
      final pending = bloc.state.messages.single;
      expect(pending.message, payload);
      expect(pending.imageUrl, image);
      expect(bloc.state.sendingMessageIds, contains(pending.id));
      gate.completeError(Exception('offline'));
      await pumpEventQueue();
      expect(bloc.state.failedMessageIds, contains(pending.id));
      expect(bloc.state.sendingMessageIds, isEmpty);
      when(
        () => send(conversationId: 'room', message: payload, imageUrl: image),
      ).thenAnswer((_) async {});
      bloc.add(
        ChatRetryMessageSent(conversationId: 'room', tempMessageId: pending.id),
      );
      await pumpEventQueue();
      expect(bloc.state.messages, hasLength(1));
      expect(bloc.state.failedMessageIds, isEmpty);
      expect(bloc.state.sendingMessageIds, isEmpty);
      bloc.add(
        ChatMessagesUpdated([
          ChatMessage(
            id: 'saved',
            conversationId: 'room',
            senderId: 'me',
            message: payload,
            imageUrl: image,
            createdAt: DateTime(2026, 10, 21),
            isMine: true,
          ),
        ]),
      );
      await pumpEventQueue();
      expect(bloc.state.messages.map((message) => message.id), ['saved']);
    },
  );
}

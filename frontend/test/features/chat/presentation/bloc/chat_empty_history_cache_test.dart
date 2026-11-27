import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/cache/app_cache.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/data/models/chat_message_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chat/domain/usecases/stream_messages_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_bloc.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_event.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_detail_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Messages extends Mock implements StreamMessagesUseCase {}

class _SendMessage extends Mock implements SendChatMessageUseCase {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString:
          'SUPABASE_URL=https://example.supabase.co\n'
          'SUPABASE_PUBLISHABLE_KEY=test-key',
    );
    for (final name in [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    await http.runWithClient(
      SupabaseConfig.initialize,
      () => MockClient((_) async => throw StateError('Unexpected request')),
    );
    await SupabaseConfig.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'viewer',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  test('empty memory snapshot waits for current history', () async {
    AppCache.rememberSnapshot('chat', 'room', 'viewer', []);
    final bloc = ChatDetailBloc(
      conversationId: 'room',
      streamMessages: _Messages(),
      sendMessage: _SendMessage(),
    );
    addTearDown(bloc.close);
    expect(bloc.state.status, ChatDetailStatus.initial);
  });

  test('cached cancellation survives the first chat message snapshot', () async {
    const room = 'room-with-cancelled-order';
    ChatMessage message(
      int bookingId,
      String status, {
      bool isRead = false,
    }) => ChatMessage(
      id: 'booking-card',
      conversationId: room,
      senderId: 'renter',
      message:
          '📋 คำขอเช่าอุปกรณ์\n[RENTAL_REQUEST_DATA:{"itemId":1,"bookingId":$bookingId,"status":"$status"}]',
      createdAt: DateTime(2026, 11, 27),
      isMine: false,
      isRead: isRead,
    );

    AppCache.rememberSnapshot('chat', room, 'viewer', [
      ChatMessageModel.toJson(message(2129, 'cancelled')),
    ]);
    final bloc = ChatDetailBloc(
      conversationId: room,
      streamMessages: _Messages(),
      sendMessage: _SendMessage(),
    );
    addTearDown(bloc.close);

    String? statusOf(ChatMessage message) =>
        BookingRequestData.fromChatMessage(message.message)?.status;

    expect(statusOf(bloc.state.messages.single), 'cancelled');
    bloc.add(ChatMessagesUpdated([message(2129, 'pending', isRead: true)]));
    await pumpEventQueue();
    expect(statusOf(bloc.state.messages.single), 'cancelled');
    expect(bloc.state.messages.single.isRead, isTrue);
    expect(statusOf(ChatMessagesCache.peek(room)!.single), 'cancelled');

    bloc.add(ChatMessagesUpdated([message(2130, 'pending')]));
    await pumpEventQueue();
    expect(statusOf(bloc.state.messages.single), 'pending');
  });
}

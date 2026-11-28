import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:frontend/features/chat/data/models/chat_conversation_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_detail_header.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_message_bubble.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AuthenticatedClient extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

void main() {
  testWidgets('shows an anonymous header and reply label for a deleted user', (
    tester,
  ) async {
    final room = ChatConversationModel.fromRecords(
      conversation: const {'id': 'deleted', 'renter_id': 'viewer'},
      otherProfile: null,
      item: null,
      currentUserId: 'viewer',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: ChatDetailHeader(
              conversation: room,
              onPhoneCallPressed: () {},
            ),
          ),
          body: ChatMessageBubble(
            message: ChatMessage(
              id: 'reply',
              conversationId: room.id,
              senderId: 'viewer',
              message: '↩ ตอบกลับ:ชื่อเดิม|คุยไว้ก่อนหน้านี้||\nข้อความตอบกลับ',
              createdAt: DateTime(2026, 11, 26),
              isMine: true,
            ),
            isReadOnly: room.isOtherUserUnavailable,
            otherUserName: room.name,
          ),
        ),
      ),
    );
    expect(find.text('ไม่พบผู้ใช้'), findsOneWidget);
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-phone-call-button')), findsNothing);
    expect(find.text('คุณตอบกลับไม่พบผู้ใช้'), findsOneWidget);
    expect(find.text('ข้อความตอบกลับ'), findsOneWidget);
  });

  for (final viewerRole in ['renter_id', 'owner_id']) {
    test('keeps chats with deleted accounts for $viewerRole', () async {
      final otherRole = viewerRole == 'renter_id' ? 'owner_id' : 'renter_id';
      final rooms =
          [
                ('deleted-1', null, 'ข้อความเดิมของห้องแรก'),
                ('deleted-2', null, 'ข้อความเดิมของห้องที่สอง'),
                ('pending', 'pending-user', 'ข้อความก่อนขอลบบัญชี'),
                ('active', 'active-user', 'ข้อความของบัญชีปัจจุบัน'),
              ]
              .map(
                (room) => {
                  'id': room.$1,
                  viewerRole: 'viewer',
                  otherRole: room.$2,
                  'last_message': room.$3,
                },
              )
              .toList();

      final client = SupabaseClient(
        'https://chat.test',
        'test-key',
        httpClient: MockClient((request) async {
          final idFilter = request.url.queryParameters['id'];
          final Object response = switch (request.url.path) {
            '/rest/v1/conversation_tb' when idFilter != null =>
              rooms.where((room) => idFilter == 'eq.${room['id']}').toList(),
            '/rest/v1/conversation_tb' => rooms,
            '/rest/v1/public_profile_v' => [
              if (request.url.queryParameters['user_id'] != 'eq.pending-user')
                {'user_id': 'active-user', 'display_name': 'สมชาย'},
            ],
            '/rest/v1/rpc/chat_unread_conversation_ids' => [
              {'conversation_id': 'deleted-1'},
            ],
            '/rest/v1/chat_message_tb' => [
              {
                'id': 12,
                'conversation_id': 'deleted-1',
                'sender_id': null,
                'message': 'ข้อความเดิมของห้องแรก',
                'created_at': '2026-11-26T00:00:00Z',
              },
            ],
            _ => throw StateError('Unexpected request: ${request.url}'),
          };
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final authenticated = _AuthenticatedClient();
      final auth = _Auth();
      when(() => authenticated.auth).thenReturn(auth);
      when(() => authenticated.schema(any())).thenAnswer(
        (call) => client.schema(call.positionalArguments.single as String),
      );
      when(() => auth.currentUser).thenReturn(
        const User(
          id: 'viewer',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '',
        ),
      );
      final source = ChatRemoteDataSource(client: authenticated);

      final conversations = await source.getConversations();
      expect(conversations.map((room) => room.id), [
        'deleted-1',
        'deleted-2',
        'pending',
        'active',
      ]);
      expect(conversations.map((room) => room.name), [
        'ไม่พบผู้ใช้',
        'ไม่พบผู้ใช้',
        'ไม่พบผู้ใช้',
        'สมชาย',
      ]);
      expect(conversations.map((room) => room.hasUnreadMessage), [
        true,
        false,
        false,
        false,
      ]);
      final detail = await source.getConversationById('deleted-1');
      expect(detail?.name, 'ไม่พบผู้ใช้');
      expect(detail?.preview, 'ข้อความเดิมของห้องแรก');
      final messages = await source.fetchMessages(conversationId: 'deleted-1');
      expect(messages.single.message, 'ข้อความเดิมของห้องแรก');
      expect(messages.single.isMine, isFalse);
    });
  }
}

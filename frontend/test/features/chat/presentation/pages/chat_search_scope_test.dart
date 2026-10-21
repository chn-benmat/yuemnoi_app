import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/chat/domain/usecases/get_conversations_usecase.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_list_bloc.dart';
import 'package:frontend/features/chat/presentation/bloc/chat_list_event.dart';
import 'package:frontend/features/chat/presentation/pages/chat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _GetConversations extends Mock implements GetConversationsUseCase {}

void main() {
  tearDownAll(() => Supabase.instance.dispose());
  var profileRequests = 0;
  setUpAll(() async {
    for (final name in [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString:
          'SUPABASE_URL=https://example.supabase.co\nSUPABASE_PUBLISHABLE_KEY=test-key',
    );
    await SupabaseConfig.initialize();
    await Supabase.instance.dispose();
    profileRequests = 0;
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        profileRequests++;
        return http.Response(
          '[{"user_id":"account-only","display_name":"td account","email":"td@example.com","is_online":true}]',
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await SupabaseConfig.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'current-user',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  testWidgets('chat search never displays system accounts', (tester) async {
    profileRequests = 0;
    AuthSession.saveAccessToken('test-token');
    final getConversations = _GetConversations();
    when(
      () => getConversations(),
    ).thenAnswer((_) async => <ChatConversation>[]);
    final bloc = ChatListBloc(getConversations: getConversations)
      ..add(const ChatListRefreshed());
    addTearDown(() async {
      await bloc.close();
      AuthSession.clear();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatScreen(chatListBloc: bloc)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.enterText(
        find.byKey(const ValueKey('chat-search-field')),
        'td',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('บัญชีผู้ใช้ในระบบ'), findsNothing);
    expect(find.text('td account'), findsNothing);
    expect(profileRequests, 0);
  });
}

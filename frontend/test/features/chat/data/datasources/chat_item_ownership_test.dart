import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:frontend/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:frontend/features/chat/domain/usecases/get_owned_chat_item_ids_usecase.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AuthenticatedClient extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

void main() {
  for (final userId in ['item-owner', 'item-customer']) {
    test('loads only items owned by authenticated $userId', () async {
      var requests = 0;
      final client = SupabaseClient(
        'https://ownership.test',
        'test-key',
        httpClient: MockClient((request) async {
          requests++;
          expect(request.url.path, '/rest/v1/item_tb');
          expect(request.url.queryParameters['select'], 'id');
          expect(request.url.queryParameters['id'], 'in.(1,2)');
          expect(request.url.queryParameters['user_id'], 'eq.$userId');
          return http.Response(
            jsonEncode(
              userId == 'item-owner'
                  ? [
                      {'id': 1},
                    ]
                  : [],
            ),
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
      when(() => auth.currentUser).thenReturn(
        User(
          id: userId,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '',
        ),
      );
      when(() => authenticated.from(any())).thenAnswer(
        (call) => client.from(call.positionalArguments.single as String),
      );
      final useCase = GetOwnedChatItemIdsUseCase(
        ChatRepositoryImpl(
          remoteDataSource: ChatRemoteDataSource(client: authenticated),
        ),
      );

      expect(await useCase({1, 2}), userId == 'item-owner' ? {1} : <int>{});
      expect(requests, 1);
      expect(await useCase({}), isEmpty);
      expect(requests, 1);
    });
  }
}

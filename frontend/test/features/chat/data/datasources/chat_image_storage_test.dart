import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:frontend/features/chat/domain/entities/chat_reply_content.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

class _MockStorage extends Mock implements SupabaseStorageClient {}

class _MockBucket extends Mock implements StorageFileApi {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const FileOptions());
  });

  test(
    'chat image upload and signed URL use the conversation folder',
    () async {
      final client = _MockClient();
      final auth = _MockAuth();
      final storage = _MockStorage();
      final bucket = _MockBucket();
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => client.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(
        User(
          id: 'sender-user',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '',
        ),
      );
      when(() => client.storage).thenReturn(storage);
      when(() => storage.from('chat_bk')).thenReturn(bucket);
      when(
        () => bucket.uploadBinary(
          any(),
          any(),
          fileOptions: any(named: 'fileOptions'),
        ),
      ).thenAnswer((_) async => 'uploaded');
      when(
        () => bucket.createSignedUrl(any(), 3600),
      ).thenAnswer((_) async => 'https://example.test/signed-image');

      final result = await ChatRemoteDataSource(client: client).uploadChatImage(
        conversationId: 'conversation-id',
        imageBytes: bytes,
        fileName: 'photo.PNG',
      );

      final upload = verify(
        () => bucket.uploadBinary(
          captureAny(),
          bytes,
          fileOptions: captureAny(named: 'fileOptions'),
        ),
      ).captured;
      final path = upload.first as String;
      expect(path.split('/'), hasLength(2));
      expect(path.split('/').first, 'conversation-id');
      expect(path, endsWith('.png'));
      expect((upload.last as FileOptions).contentType, 'image/png');
      verify(() => bucket.createSignedUrl(path, 3600)).called(1);
      expect(result, 'https://example.test/signed-image');
    },
  );

  for (final (failSigning, storagePath) in [
    (false, 'room/sender-photo.jpg'),
    (true, 'room/sender-photo.jpg'),
    (false, 'legacy-user/room/sender-photo.jpg'),
  ]) {
    test(
      'history refreshes $storagePath image and quote; signing failure=$failSigning',
      () async {
        final expired =
            'https://project.test/storage/v1/object/sign/chat_bk/$storagePath?token=expired';
        final fresh =
            'https://project.test/storage/v1/object/sign/chat_bk/$storagePath?token=fresh';
        var signRequests = 0;
        final client = SupabaseClient(
          'https://project.test',
          'test-key',
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/chat_message_tb') {
              return http.Response(
                jsonEncode([
                  {
                    'id': 'reply',
                    'conversation_id': 'room',
                    'sender_id': 'other',
                    'message':
                        '↩ ตอบกลับ:ตัวเอง|📷 รูปภาพ|photo|$expired\nรับทราบครับ',
                    'created_at': '2026-10-20T10:01:00Z',
                  },
                  {
                    'id': 'photo',
                    'conversation_id': 'room',
                    'sender_id': 'other',
                    'message': '📷 ส่งรูปภาพ',
                    'image_url': expired,
                    'created_at': '2026-10-20T10:00:00Z',
                  },
                ]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            expect(
              request.url.path,
              '/storage/v1/object/sign/chat_bk/$storagePath',
            );
            expect(request.method, 'POST');
            expect(jsonDecode(request.body)['expiresIn'], 3600);
            signRequests++;
            return failSigning
                ? http.Response(
                    '{"statusCode":"403","error":"AccessDenied","message":"denied"}',
                    403,
                  )
                : http.Response(
                    '{"signedURL":"/object/sign/chat_bk/$storagePath?token=fresh"}',
                    200,
                    headers: {'content-type': 'application/json'},
                    request: request,
                  );
          }),
        );
        addTearDown(client.dispose);
        final authenticated = _MockClient();
        final auth = _MockAuth();
        when(() => authenticated.auth).thenReturn(auth);
        when(() => authenticated.storage).thenReturn(client.storage);
        when(() => authenticated.schema(any())).thenAnswer(
          (call) => client.schema(call.positionalArguments.single as String),
        );
        when(() => auth.currentUser).thenReturn(
          User(
            id: 'viewer',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '',
          ),
        );
        final source = ChatRemoteDataSource(client: authenticated);
        await source.fetchMessages(conversationId: 'room');
        await source.refreshChatImageUrl(expired);
        final messages = await source.fetchMessages(conversationId: 'room');
        expect(messages, hasLength(2));
        expect(messages.first.imageUrl, failSigning ? expired : fresh);
        final reply = ChatReplyContent.tryParse(messages.last.message)!;
        expect(reply.quotedImageUrl, failSigning ? expired : fresh);
        expect(reply.text, 'รับทราบครับ');
        expect(signRequests, greaterThanOrEqualTo(1));
        if (!failSigning) expect(signRequests, 1);
      },
    );
  }
}

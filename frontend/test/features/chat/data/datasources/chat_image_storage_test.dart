import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
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
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/profile/data/datasources/profile_remote_data_source.dart';

void main() {
  test(
    'a partial save returns the username and cooldown from the profile',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.method, 'PUT');
            expect(request.data, {'bio': 'New bio'});
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'profile': {
                    'user_id': 'u1',
                    'username': 'elle.com_',
                    'username_changed_at': '2026-11-27T05:00:00Z',
                    'bio': 'New bio',
                  },
                },
              ),
            );
          },
        ),
      );
      final client = DioApiClient(dio: dio, appSecret: '');
      addTearDown(client.close);

      final profile = await ProfileRemoteDataSource(
        client: client,
      ).updateProfile(accessToken: 'token', bio: 'New bio');

      expect(profile.username, 'elle.com_');
      expect(profile.usernameChangedAt, DateTime.utc(2026, 11, 27, 5));
      expect(profile.bio, 'New bio');
    },
  );
}

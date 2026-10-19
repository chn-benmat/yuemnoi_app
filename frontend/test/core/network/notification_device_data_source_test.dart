import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/notification_device_data_source.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements ApiClient {}

void main() {
  late _Api api;
  late NotificationDeviceDataSource source;
  setUp(() {
    api = _Api();
    source = NotificationDeviceDataSource(client: api);
    when(() => api.close()).thenReturn(null);
  });
  tearDown(() => source.close());
  Future<void> register() => source.register(
    accessToken: 'verified-session',
    installationId: 'persistent-installation',
    token: 'device-specific-token',
    platform: 'android',
  );
  test('HTTP failure cannot be mistaken for saved device token', () async {
    when(
      () => api.put(
        any(),
        headers: any(named: 'headers'),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async =>
          const ApiResponse(statusCode: 503, data: {'error': 'unavailable'}),
    );
    await expectLater(
      register(),
      throwsA(
        isA<NotificationDeviceException>().having(
          (e) => e.statusCode,
          'status',
          503,
        ),
      ),
    );
  });
  test(
    'registration sends stable installation and verified bearer instead of user id',
    () async {
      when(
        () => api.put(
          any(),
          headers: any(named: 'headers'),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(statusCode: 200, data: {'status': 'ok'}),
      );
      await register();
      verify(
        () => api.put(
          '/api/notifications/devices',
          headers: {'Authorization': 'Bearer verified-session'},
          data: {
            'installation_id': 'persistent-installation',
            'token': 'device-specific-token',
            'platform': 'android',
          },
        ),
      ).called(1);
    },
  );
  test(
    'logout only unregisters this installation and checks response',
    () async {
      when(
        () => api.delete(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => const ApiResponse(statusCode: 401, data: {}));
      await expectLater(
        source.unregister(
          accessToken: 'expired',
          installationId: 'persistent-installation',
        ),
        throwsA(isA<NotificationDeviceException>()),
      );
      verify(
        () => api.delete(
          '/api/notifications/devices/persistent-installation',
          headers: {'Authorization': 'Bearer expired'},
        ),
      ).called(1);
    },
  );
}

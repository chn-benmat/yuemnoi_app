import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_session_validator.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/notification/data/notification_remote_data_source.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NotificationApi extends Mock implements ApiClient {}

void main() {
  testWidgets('asks guests to sign in before loading notifications', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationPage()));

    expect(find.text('การแจ้งเตือน'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบเพื่อดูการแจ้งเตือน'), findsOneWidget);
  });

  testWidgets('notification header has a purple background and white title', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationPage()));

    final title = find.text('การแจ้งเตือน');
    expect(
      find.ancestor(
        of: title,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == AppColors.primaryColor,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(title).style?.color, Colors.white);
  });

  testWidgets('notification skeletons appear while loading each page', (
    tester,
  ) async {
    final api = _NotificationApi();
    final session = Session(
      accessToken: 'test-token',
      tokenType: 'bearer',
      user: const User(
        id: 'notification-user',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-10-17T00:00:00Z',
      ),
    );
    const headers = {'Authorization': 'Bearer test-token'};
    when(() => api.get('/api/auth/session', headers: headers)).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {'user_id': 'notification-user'},
      ),
    );
    final firstPage = Completer<ApiResponse>();
    final nextPage = Completer<ApiResponse>();
    when(
      () => api.get(
        '/api/notifications',
        headers: headers,
        queryParameters: {'limit': 40, 'offset': 0},
      ),
    ).thenAnswer((_) => firstPage.future);
    when(
      () => api.get(
        '/api/notifications',
        headers: headers,
        queryParameters: {'limit': 40, 'offset': 40},
      ),
    ).thenAnswer((_) => nextPage.future);
    await AuthSession.accept(
      session,
      validator: AppSessionValidator(client: api),
    );
    addTearDown(AuthSession.clear);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationPage(
          dataSource: NotificationRemoteDataSource(client: api),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('notification-loading-skeleton')),
      findsOneWidget,
    );
    expect(find.byType(Shimmer), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    firstPage.complete(
      ApiResponse(
        statusCode: 200,
        data: {'items': List.generate(40, _notification)},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Shimmer), findsNothing);
    expect(find.text('การแจ้งเตือน 0'), findsOneWidget);

    final loadMore = find.text('ดูเพิ่มเติม');
    await tester.scrollUntilVisible(loadMore, 480);
    await tester.tap(loadMore);
    await tester.pump();
    expect(find.text('การแจ้งเตือน 39'), findsOneWidget);
    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    nextPage.complete(
      ApiResponse(
        statusCode: 200,
        data: {
          'items': [_notification(40)],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Shimmer), findsNothing);
    expect(find.text('การแจ้งเตือน 40'), findsOneWidget);
  });
}

Map<String, Object> _notification(int id) => {
  'id': '$id',
  'type': 'chat_message',
  'title': 'การแจ้งเตือน $id',
  'body': 'ข้อความใหม่',
};

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/booking_request_bubble_card.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final localDeadline = DateTime(2099, 11, 27, 17);

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
    await http.runWithClient(SupabaseConfig.initialize, () {
      return MockClient((request) async {
        if (request.url.path != '/rest/v1/booking_tb' ||
            request.url.queryParameters['id'] != 'eq.36') {
          throw StateError('Unexpected booking request: ${request.url}');
        }
        return http.Response(
          jsonEncode([
            {
              'id': 36,
              'status': 'active',
              'end_at': localDeadline.toUtc().toIso8601String(),
            },
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
    });
    await SupabaseConfig.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'renter',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('the active chat card shows the return deadline in local time', (
    tester,
  ) async {
    final bookingData = BookingRequestData(
      item: const BookingItemInfo(
        id: 1,
        title: 'Camera',
        imageUrl: '',
        rating: 4.8,
        reviewCount: 1,
        hourlyRate: 150,
        dailyRate: 700,
        defaultLocation: 'Pickup point',
      ),
      startDate: DateTime(2099, 11, 26),
      endDate: DateTime(2099, 11, 27),
      startTime: const TimeOfDay(hour: 15, minute: 0),
      endTime: const TimeOfDay(hour: 15, minute: 0),
      location: 'Pickup point',
      bookingId: 36,
    );
    final message = ChatMessage(
      id: 'booking-deadline-message',
      conversationId: 'booking-deadline-conversation',
      senderId: 'renter',
      message: bookingData.toChatMessagePayload(),
      createdAt: DateTime(2099, 11, 26),
      isMine: false,
      isRead: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BookingRequestBubbleCard(
              message: message,
              bookingData: bookingData,
              isOwner: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deadline = tester.widget<Text>(find.textContaining('ครบกำหนดส่งคืน'));
    expect(deadline.data, 'ครบกำหนดส่งคืน: 27/11/2099 เวลา 17:00 น.');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

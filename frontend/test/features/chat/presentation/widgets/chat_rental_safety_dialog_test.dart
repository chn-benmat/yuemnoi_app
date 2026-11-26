import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/chat_rental_safety_preferences.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_rental_safety_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const renterTitle = 'คำเตือนก่อนเช่าอุปกรณ์';
  const ownerTitle = 'คำเตือนก่อนปล่อยเช่าอุปกรณ์';

  late DateTime now;
  late ChatRentalSafetyPreferences preferences;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 26, 23, 59);
    preferences = ChatRentalSafetyPreferences(now: () => now);
  });

  Future<void> openChat(
    WidgetTester tester, {
    required ChatParticipantRole role,
    String accountId = 'first-account',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showChatRentalSafetyReminder(
                context,
                accountId: accountId,
                role: role,
                preferences: preferences,
              ),
              child: const Text('เปิดแชท'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดแชท'));
    await tester.pumpAndSettle();
  }

  Future<void> acknowledge(
    WidgetTester tester, {
    bool hideToday = false,
  }) async {
    if (hideToday) {
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('รับทราบ'));
    await tester.pumpAndSettle();
  }

  testWidgets('the reminder returns on the next local calendar day', (
    tester,
  ) async {
    await openChat(tester, role: ChatParticipantRole.renter);
    expect(find.text(renterTitle), findsOneWidget);
    await acknowledge(tester, hideToday: true);

    SharedPreferences.resetStatic();
    await openChat(tester, role: ChatParticipantRole.renter);
    expect(find.byType(AlertDialog), findsNothing);

    now = DateTime(2026, 11, 27);
    await openChat(tester, role: ChatParticipantRole.renter);
    expect(find.text(renterTitle), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });

  testWidgets('acknowledgment sits directly below the checkbox on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openChat(tester, role: ChatParticipantRole.owner);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    final checkbox = tester.getRect(find.byType(CheckboxListTile));
    final button = tester.getRect(find.byType(FilledButton));
    expect(button.top - checkbox.bottom, inInclusiveRange(0, 8));
  });

  testWidgets('acknowledging without checking shows the next reminder', (
    tester,
  ) async {
    await openChat(tester, role: ChatParticipantRole.owner);
    expect(find.text(ownerTitle), findsOneWidget);
    await acknowledge(tester);

    await openChat(tester, role: ChatParticipantRole.owner);
    expect(find.text(ownerTitle), findsOneWidget);
  });

  testWidgets(
    'hiding an owner reminder leaves other roles and accounts visible',
    (tester) async {
      await openChat(tester, role: ChatParticipantRole.owner);
      await acknowledge(tester, hideToday: true);

      await openChat(tester, role: ChatParticipantRole.renter);
      expect(find.text(renterTitle), findsOneWidget);
      await acknowledge(tester);

      await openChat(
        tester,
        role: ChatParticipantRole.owner,
        accountId: 'second-account',
      );
      expect(find.text(ownerTitle), findsOneWidget);
    },
  );
}

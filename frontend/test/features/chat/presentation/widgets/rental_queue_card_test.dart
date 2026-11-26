import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/domain/entities/rental_queue_card_data.dart';
import 'package:frontend/features/chat/presentation/widgets/rental_queue_card.dart';

void main() {
  testWidgets('the waiting renter sees their place and can leave', (
    tester,
  ) async {
    final data = RentalQueueCardData.fromMessage(
      '{"rentalQueue":{"itemId":8,"name":"กล้อง","status":"waiting","position":2}}',
    );
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RentalQueueCard(
            data: data!,
            isOwner: false,
            onAction: (action) async {
              actions.add(action);
            },
          ),
        ),
      ),
    );
    expect(find.text('รออุปกรณ์คืน · คิวที่ 2'), findsOneWidget);
    expect(find.text('ยืนยันสิทธิ์และนัดรับ'), findsNothing);
    await tester.tap(find.text('ออกจากคิว'));
    expect(actions, ['leave']);
  });

  testWidgets(
    'the first renter can accept, and the owner can then offer pickup',
    (tester) async {
      final actions = <String>[];
      Future<void> showCard(String status, {bool owner = false}) async {
        final data = RentalQueueCardData.fromMessage(
          '{"rentalQueue":{"itemId":8,"name":"กล้อง","status":"$status","expiresAt":"2030-01-02T01:00:00Z"}}',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RentalQueueCard(
                data: data!,
                isOwner: owner,
                onAction: (action) async {
                  actions.add(action);
                },
                onSendOffer: owner ? () => actions.add('offer') : null,
              ),
            ),
          ),
        );
      }

      await showCard('ready');
      expect(find.text('อุปกรณ์พร้อมให้เช่าต่อ'), findsOneWidget);
      await tester.tap(find.text('ยืนยันสิทธิ์และนัดรับ'));
      await tester.pump();
      expect(actions, ['accept']);

      await showCard('accepted', owner: true);
      expect(find.text('ผู้เช่ายืนยันสิทธิ์แล้ว'), findsOneWidget);
      expect(find.text('ออกจากคิว'), findsNothing);
      await tester.tap(find.text('ส่งข้อเสนอและนัดรับ'));
      expect(actions, ['accept', 'offer']);
    },
  );
}

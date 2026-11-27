import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/domain/entities/rental_queue_card_data.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_message_bubble.dart';
import 'package:frontend/features/chat/presentation/widgets/rental_queue_card.dart';

void main() {
  testWidgets('a renter can act on the queue card they sent', (tester) async {
    final actions = <String>[];
    for (final isMine in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: ChatMessage(
                id: '35',
                conversationId: 'room',
                senderId: 'renter',
                message:
                    '{"rentalQueue":{"itemId":8,"name":"กล้อง",'
                    '"status":"ready","requestedByRenter":true}}',
                createdAt: DateTime(2026, 11, 27),
                isMine: isMine,
              ),
              onQueueAction: (action) async => actions.add(action),
            ),
          ),
        ),
      );
      final accept = find.text('ยืนยันสิทธิ์และนัดรับ');
      expect(accept, isMine ? findsOneWidget : findsNothing);
      if (isMine) await tester.tap(accept);
    }
    expect(actions, ['accept']);
  });

  for (final (description, prices, expected) in const [
    (
      'both rates',
      '"price":150,"rentalType":"รายชั่วโมง","dailyPrice":1200',
      ['150 บาท / ชั่วโมง', '1,200 บาท / วัน'],
    ),
    (
      'the hourly rate only',
      '"price":150,"rentalType":"รายชั่วโมง","dailyPrice":null',
      ['150 บาท / ชั่วโมง'],
    ),
    (
      'the daily rate only from an existing message',
      '"price":1200,"rentalType":"รายวัน"',
      ['1,200 บาท / วัน'],
    ),
  ]) {
    testWidgets('the rental queue card shows $description', (tester) async {
      final data = RentalQueueCardData.fromMessage(
        '{"rentalQueue":{"itemId":8,"name":"กล้อง","status":"invited",$prices}}',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RentalQueueCard(
              data: data!,
              isOwner: false,
              onAction: (_) async {},
            ),
          ),
        ),
      );

      final displayedPrices = tester
          .widgetList<Text>(find.textContaining('บาท'))
          .map((text) => text.data);
      expect(displayedPrices, orderedEquals(expected));
    });
  }

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

  testWidgets('the first renter can accept and send a request to the owner', (
    tester,
  ) async {
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
              onSendRequest: () => actions.add('request'),
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
    expect(find.text('ส่งคำขอเช่า'), findsNothing);
    await showCard('accepted');
    await tester.tap(find.text('ส่งคำขอเช่า'));
    expect(actions, ['accept', 'request']);
  });
}

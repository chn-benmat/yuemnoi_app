import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_skeleton_layout_estimate.dart';

ChatMessage _message(
  String text, {
  required bool mine,
  required DateTime at,
  String id = 'm',
}) => ChatMessage(
  id: id,
  conversationId: 'room',
  senderId: mine ? 'me' : 'other',
  message: text,
  createdAt: at,
  isMine: mine,
  isRead: true,
);

void main() {
  final start = DateTime(2026, 11, 29, 17, 49);

  test('a room with one booking card estimates exactly one card', () {
    final layout = estimateChatSkeletonLayout(
      [
        _message(
          '${BookingRequestData.bookingPayloadPrefix}\nโต๊ะคุณภาพดี',
          mine: true,
          at: start,
        ),
      ],
      screenWidth: 414,
      screenHeight: 896,
    );

    expect(layout, hasLength(1));
    final parts = layout.single.split('|');
    expect(parts[0], 'o'); // ฝั่งเรา
    expect(parts[1], 'c'); // การ์ด
    expect(parts[3], '1'); // มีตัวคั่นเวลาด้านบน
  });

  test('orders newest first with avatars and dividers like the chat page', () {
    final layout = estimateChatSkeletonLayout(
      [
        _message('สวัสดีครับ', mine: false, at: start, id: 'a'),
        _message(
          'ยังว่างไหม',
          mine: false,
          at: start.add(const Duration(minutes: 1)),
          id: 'b',
        ),
        _message(
          'ว่างครับ',
          mine: true,
          at: start.add(const Duration(minutes: 30)),
          id: 'c',
        ),
      ],
      screenWidth: 414,
      screenHeight: 896,
    );

    expect(layout.map((t) => t.split('|').take(2).join('|')), [
      'o|t',
      'i|t',
      'i|t',
    ]);
    // ข้อความของเราห่าง 29 นาทีจึงมีตัวคั่นเวลา ส่วนอวาตาร์อยู่ข้อความสุดท้ายของอีกฝ่าย
    expect(layout[0].split('|')[3], '1');
    expect(layout[1].split('|')[4], '1');
    expect(layout[2].split('|')[4], '0');
    expect(layout[2].split('|')[3], '1');
  });

  test('an empty room has no skeleton rows', () {
    expect(
      estimateChatSkeletonLayout(const [], screenWidth: 414, screenHeight: 896),
      isEmpty,
    );
  });
}

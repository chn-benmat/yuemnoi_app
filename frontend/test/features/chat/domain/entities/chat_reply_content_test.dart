import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/chat_reply_content.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';

ChatMessage original(String text, {String? imageUrl}) => ChatMessage(
  id: 'origin',
  conversationId: 'conversation',
  senderId: 'other',
  message: text,
  imageUrl: imageUrl,
  createdAt: DateTime(2026, 10, 20),
  isMine: false,
);

void main() {
  test(
    'multiline quotes and pipes preserve the answer and original message ID',
    () {
      final payload = ChatReplyContent.compose(
        original: original('รายละเอียด\nหลายบรรทัด | พร้อมให้เช่า 📷'),
        target: 'สมชาย',
        text: 'รับทราบครับ\nขอบคุณครับ | ตกลง',
      );
      final parsed = ChatReplyContent.tryParse(payload)!;
      expect(parsed.quotedText, 'รายละเอียด หลายบรรทัด พร้อมให้เช่า 📷');
      expect(parsed.quotedMessageId, 'origin');
      expect(parsed.quotedImageUrl, isNull);
      expect(parsed.text, 'รับทราบครับ\nขอบคุณครับ | ตกลง');
    },
  );

  test(
    'booking previews use the item title and image without serialized data',
    () {
      final booking = BookingRequestData(
        item: const BookingItemInfo(
          id: 42,
          title: 'iPhone 18 Pro Max 256GB',
          imageUrl: 'https://example.com/item.jpg',
          rating: 0,
          reviewCount: 0,
          hourlyRate: 100,
          dailyRate: 4999,
          defaultLocation: 'ซีคอน บางแค',
        ),
        startDate: DateTime(2026, 10, 19),
        endDate: DateTime(2026, 10, 20),
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 10, minute: 0),
        location: 'ซีคอน บางแค',
      );
      final preview = ChatReplyContent.preview(
        original(booking.toChatMessagePayload()),
      );
      expect(preview.text, '📋 คำขอเช่าอุปกรณ์: iPhone 18 Pro Max 256GB');
      expect(preview.imageUrl, 'https://example.com/item.jpg');
      expect(preview.text, isNot(contains('[BOOKING_DATA:')));
    },
  );

  test('inquiry preview uses its image from metadata', () {
    const inquiry = ItemInquiryData(
      itemId: 42,
      itemName: 'กล้อง Sony',
      imageUrl: 'https://example.com/camera.jpg',
    );
    final preview = ChatReplyContent.preview(
      original(inquiry.toChatMessagePayload()),
    );
    expect(preview.text, 'อุปกรณ์: กล้อง Sony');
    expect(preview.imageUrl, inquiry.imageUrl);
  });

  test('replying to a reply quotes only its answer', () {
    final payload = ChatReplyContent.compose(
      original: original('↩ ตอบกลับ:ตัวเอง|คำถามเดิม|old|\nคำตอบล่าสุด'),
      target: 'สมชาย',
      text: 'ตกลงครับ',
    );
    final parsed = ChatReplyContent.tryParse(payload)!;
    expect(parsed.quotedText, 'คำตอบล่าสุด');
    expect(parsed.quotedMessageId, 'origin');
    expect(parsed.text, 'ตกลงครับ');
  });

  test('legacy multiline quote with no image can still be edited safely', () {
    final parsed = ChatReplyContent.tryParse(
      '↩ ตอบกลับ:ตัวเอง|รายละเอียด\nหลายบรรทัด|420|\nคำตอบเดิม',
    )!;
    expect(parsed.quotedText, 'รายละเอียด หลายบรรทัด');
    expect(parsed.quotedMessageId, '420');
    final edited = ChatReplyContent.tryParse(
      parsed.toMessage(newText: 'คำตอบใหม่'),
    )!;
    expect(edited.quotedMessageId, '420');
    expect(edited.text, 'คำตอบใหม่');
  });

  test('ordinary links are not interpreted as image attachments', () {
    final parsed = ChatReplyContent.tryParse(
      '↩ ตอบกลับ:สมชาย|ดูรายละเอียด https://example.com/info|origin|\nตกลง',
    )!;
    expect(parsed.quotedImageUrl, isNull);
    expect(parsed.quotedText, contains('https://example.com/info'));
  });
}

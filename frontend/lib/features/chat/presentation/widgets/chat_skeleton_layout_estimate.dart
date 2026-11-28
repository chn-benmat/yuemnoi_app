import 'dart:math' as math;

import '../../../booking/domain/entities/booking_request_model.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/item_inquiry_data.dart';
import '../../domain/entities/rental_queue_card_data.dart';

/// key ที่ห้องแชทใช้เก็บรูปร่างข้อความล่าสุดให้ skeleton
String chatSkeletonLayoutKey(String conversationId) => 'chat.$conversationId';

/// ประมาณรูปร่างข้อความล่าสุดของห้องจากข้อมูลข้อความ สำหรับห้องที่ยังไม่เคยเปิด
/// ให้ skeleton ครั้งแรกมีจำนวน ฝั่ง และชนิดตรงกับที่จะแสดง เมื่อเปิดห้องจริงแล้ว
/// หน้าแชทจะวัดขนาดจริงมาเขียนทับค่าประมาณนี้
///
/// คืนค่ารูปแบบเดียวกับ ChatSkeletonLoadingView.layout โดยเรียงใหม่สุดก่อน
List<String> estimateChatSkeletonLayout(
  List<ChatMessage> messages, {
  required double screenWidth,
  required double screenHeight,
  int max = 12,
}) {
  if (messages.isEmpty) return const [];
  final ordered = [...messages]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  // พื้นที่ตัวอักษรในบับเบิล: กว้างสุด 72% ของจอ ลบ padding ซ้ายขวา 14
  final textWidth = math.max(80.0, screenWidth * 0.72 - 28);
  final lastMineIndex = ordered.lastIndexWhere((m) => m.isMine);

  bool showDivider(int i) {
    if (i == 0) return true;
    final prev = ordered[i - 1].createdAt;
    final curr = ordered[i].createdAt;
    final differentDay =
        prev.year != curr.year ||
        prev.month != curr.month ||
        prev.day != curr.day;
    return differentDay || curr.difference(prev).inMinutes.abs() >= 15;
  }

  bool showAvatar(int i) {
    if (ordered[i].isMine) return false;
    if (i == ordered.length - 1) return true;
    return ordered[i + 1].isMine || showDivider(i + 1);
  }

  final tokens = <String>[];
  var total = 0.0;
  for (var i = ordered.length - 1; i >= 0; i--) {
    if (tokens.length >= max || total >= screenHeight) break;
    final message = ordered[i];
    final text = message.message;
    final String kind;
    double height;
    if (BookingRequestData.isBookingRequest(text)) {
      // การ์ดคำขอเช่า: รูป 210 หัวข้อ ปุ่ม 36 กล่องรายละเอียด และปุ่มหลัก 42
      kind = 'c';
      height = 522;
    } else if (ItemInquiryData.isInquiry(text)) {
      kind = 'c';
      height = 420;
    } else if (RentalQueueCardData.fromMessage(text) != null) {
      kind = 'c';
      height = 170;
    } else if (message.imageUrl != null && message.imageUrl!.isNotEmpty) {
      kind = 'i';
      height = 184;
    } else {
      // ตัวอักษร 15px สูงบรรทัด 1.35 กว้างราว 7.5px ต่อตัว และ padding บนล่าง 10
      kind = 't';
      final lines = text
          .split('\n')
          .fold<int>(
            0,
            (sum, line) =>
                sum + math.max(1, (line.length * 7.5 / textWidth).ceil()),
          );
      height = lines * 20.25 + 24;
    }
    final divider = showDivider(i);
    if (divider) height += 40;
    // ข้อความล่าสุดของเรามีสถานะส่งแล้วหรืออวาตาร์อ่านแล้วอยู่ด้านล่าง
    if (i == lastMineIndex) height += 18;
    total += height;
    tokens.add(
      [
        message.isMine ? 'o' : 'i',
        kind,
        height.round(),
        divider ? 1 : 0,
        showAvatar(i) ? 1 : 0,
        text.length,
      ].join('|'),
    );
  }
  return tokens;
}

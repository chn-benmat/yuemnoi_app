import '../../../booking/domain/entities/booking_request_model.dart';
import 'chat_message.dart';
import 'item_inquiry_data.dart';

class ChatReplyContent {
  const ChatReplyContent({
    required this.target,
    required this.quotedText,
    required this.text,
    this.quotedMessageId,
    this.quotedImageUrl,
  });

  final String target;
  final String quotedText;
  final String text;
  final String? quotedMessageId;
  final String? quotedImageUrl;

  static const _prefix = '↩ ตอบกลับ:';

  static ChatReplyContent? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith(_prefix)) {
      final content = trimmed.substring(_prefix.length);
      // ข้อความเก่าอาจมีบรรทัดใหม่ในคำอ้างอิง จึงหาเส้นแบ่งหลังช่อง ID และรูป
      final fields = RegExp(
        r'^([^|\r\n]*)\|([\s\S]*?)\|([^|\r\n]*)\|(https?://[^\r\n]*)?\r?\n([\s\S]*)$',
      ).firstMatch(content);
      if (fields != null) {
        return ChatReplyContent(
          target: fields[1]!.trim(),
          quotedText: _previewText(
            fields[2]!.trim().isEmpty && fields[4] != null
                ? '[รูปภาพ]'
                : fields[2]!,
          ),
          quotedMessageId: _nonEmpty(fields[3]),
          quotedImageUrl: _nonEmpty(fields[4]),
          text: fields[5]!,
        );
      }

      final newline = content.indexOf('\n');
      if (newline != -1) {
        final header = content.substring(0, newline).trim();
        final fields = header.split('|');
        final colon = header.indexOf(':');
        return ChatReplyContent(
          target: fields.length > 1
              ? fields.first.trim()
              : (colon != -1 ? header.substring(0, colon).trim() : header),
          quotedText: _previewText(
            fields.length > 1
                ? fields[1]
                : (colon != -1
                      ? header.substring(colon + 1).replaceAll('"', '')
                      : ''),
          ),
          quotedMessageId: fields.length > 2 ? _nonEmpty(fields[2]) : null,
          text: content.substring(newline + 1),
        );
      }
    }

    for (final prefix in ['💬 ตอบกลับ', '↪ ตอบกลับ']) {
      if (trimmed.startsWith(prefix)) {
        final newline = trimmed.indexOf('\n');
        if (newline != -1) {
          return ChatReplyContent(
            target: trimmed
                .substring(prefix.length, newline)
                .replaceAll('"', '')
                .replaceFirst(':', '')
                .trim(),
            quotedText: '',
            text: trimmed.substring(newline + 1),
          );
        }
      }
    }
    return null;
  }

  static String messageText(String raw) => tryParse(raw)?.text ?? raw.trim();

  static ({String text, String? imageUrl}) preview(ChatMessage message) {
    final raw = messageText(message.message);
    final booking = BookingRequestData.isBookingRequest(raw)
        ? BookingRequestData.fromChatMessage(raw)
        : null;
    if (booking != null) {
      return (
        text: _previewText('📋 คำขอเช่าอุปกรณ์: ${booking.item.title}'),
        imageUrl:
            _nonEmpty(message.imageUrl) ?? _nonEmpty(booking.item.imageUrl),
      );
    }
    final inquiry = ItemInquiryData.fromChatMessage(raw);
    if (inquiry != null) {
      return (
        text: _previewText('อุปกรณ์: ${inquiry.itemName}'),
        imageUrl: _nonEmpty(message.imageUrl) ?? _nonEmpty(inquiry.imageUrl),
      );
    }
    return (
      text: _previewText(
        raw.isEmpty && _nonEmpty(message.imageUrl) != null ? '[รูปภาพ]' : raw,
      ),
      imageUrl: _nonEmpty(message.imageUrl),
    );
  }

  static String compose({
    required ChatMessage original,
    required String target,
    required String text,
  }) {
    final quote = preview(original);
    return ChatReplyContent(
      target: target,
      quotedText: quote.text,
      quotedMessageId: original.id,
      quotedImageUrl: quote.imageUrl,
      text: text,
    ).toMessage();
  }

  String toMessage({String? newText}) =>
      '$_prefix${_singleLine(target)}|${_singleLine(quotedText)}|${quotedMessageId ?? ''}|${quotedImageUrl ?? ''}\n${newText ?? text}';

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static String _singleLine(String text) => text
      .replaceAll(RegExp(r'[\r\n|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _previewText(String raw) {
    var text = messageText(raw);
    if (text.isEmpty) return 'ข้อความ';
    if (text == '📷 ส่งรูปภาพ' || text == '[รูปภาพ]') {
      return '📷 รูปภาพ';
    }
    for (final tag in [
      BookingRequestData.metaStartTag,
      BookingRequestData.customerRequestMetaTag,
      ItemInquiryData.metaStartTag,
    ]) {
      final index = text.indexOf(tag);
      if (index != -1) text = text.substring(0, index);
    }
    // คำอ้างอิงเก่าที่เคยถูกตัดบรรทัดอาจมี ID และ URL ปนท้ายชื่ออุปกรณ์
    if (text.startsWith('อุปกรณ์:') ||
        text.startsWith(BookingRequestData.bookingPayloadPrefix) ||
        text.startsWith(ItemInquiryData.inquiryPrefix) ||
        text.startsWith(ItemInquiryData.legacyPrefix)) {
      text = text.replaceFirst(
        RegExp(r'(?:[\s|]+\d+)?[\s|]+https?://[\s\S]*$'),
        '',
      );
    }
    text = _singleLine(text);
    return text.runes.length > 80
        ? '${String.fromCharCodes(text.runes.take(80))}…'
        : text;
  }
}

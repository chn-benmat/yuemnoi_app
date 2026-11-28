import 'package:flutter/material.dart';

import '../../../../core/widgets/skeleton_shimmer.dart';

/// โครงห้องแชทขณะโหลด ใช้ระยะเดียวกับ PackageChatList และ ChatMessageBubble
/// รายการชิดล่างเหมือนแชทจริงที่ reversed อวาตาร์ 28 และมุมบับเบิล 20/4
class ChatSkeletonLoadingView extends StatelessWidget {
  const ChatSkeletonLoadingView({super.key, this.layout});

  /// ขนาดข้อความที่วัดไว้ตอนเปิดห้องนี้ครั้งก่อน เรียงใหม่สุดก่อน
  /// แต่ละตัวเป็น 'ฝั่ง|ชนิด|ความสูง|มีตัวคั่นเวลา|มีอวาตาร์|ความยาวข้อความ'
  final List<String>? layout;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubble = screenWidth * 0.72;
    // ห่อ shimmer ทีละชิ้น เพราะ shimmer ทาสีทับทุกพิกเซลข้างใน
    // การ์ดจึงต้องวางพื้นขาวกับเส้นขอบไว้นอก shimmer จึงจะเห็นกรอบการ์ด
    Widget bone(Widget child) => SkeletonShimmer(child: child);
    final measured = [
      for (final token in layout ?? const <String>[])
        ?_MeasuredMessage.tryParse(token),
    ];
    return ListView(
      key: const ValueKey('chat-detail-loading-skeleton'),
      // เรียงจากล่างขึ้นบนเหมือนรายการข้อความจริง เพื่อไม่ให้เนื้อหากระโดดตอนโหลดเสร็จ
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      // ห้องที่เคยเปิดแล้ววาดตามขนาดจริงที่วัดไว้ ห้องใหม่ใช้โครงทั่วไป
      children: measured.isNotEmpty
          ? [
              for (final message in measured)
                _MeasuredMessageBone(
                  message: message,
                  screenWidth: screenWidth,
                ),
            ]
          : [
              bone(const _ReadReceiptBone()),
              _BookingCardBone(width: (screenWidth * 0.75).clamp(0.0, 320.0)),
              bone(const _TimeDividerBone()),
              bone(
                _IncomingBubbleBone(width: maxBubble * 0.62, showAvatar: true),
              ),
              bone(_IncomingBubbleBone(width: maxBubble * 0.84)),
              bone(_OutgoingBubbleBone(width: maxBubble * 0.48)),
              bone(_OutgoingBubbleBone(width: maxBubble * 0.76)),
              bone(
                _IncomingBubbleBone(width: maxBubble * 0.55, showAvatar: true),
              ),
              bone(const _TimeDividerBone()),
            ],
    );
  }
}

class _MeasuredMessage {
  const _MeasuredMessage({
    required this.isMine,
    required this.kind,
    required this.height,
    required this.hasDivider,
    required this.hasAvatar,
    required this.textLength,
  });

  final bool isMine;

  /// 't' ข้อความ, 'c' การ์ด (คำขอเช่า สอบถาม คิว), 'i' รูปภาพ
  final String kind;
  final double height;
  final bool hasDivider;
  final bool hasAvatar;
  final int textLength;

  static _MeasuredMessage? tryParse(String token) {
    final parts = token.split('|');
    if (parts.length != 6) return null;
    final height = double.tryParse(parts[2]);
    if (height == null || height <= 0) return null;
    return _MeasuredMessage(
      isMine: parts[0] == 'o',
      kind: parts[1],
      height: height,
      hasDivider: parts[3] == '1',
      hasAvatar: parts[4] == '1',
      textLength: int.tryParse(parts[5]) ?? 0,
    );
  }
}

/// ความสูงตัวคั่นเวลาในหน้าจริง: ข้อความ 12px กับ padding แนวตั้ง 12
const _dividerHeight = 40.0;

/// วาดข้อความหนึ่งรายการให้สูงเท่าที่วัดได้จริง แบ่งเป็นตัวคั่นเวลากับตัวข้อความ
class _MeasuredMessageBone extends StatelessWidget {
  const _MeasuredMessageBone({
    required this.message,
    required this.screenWidth,
  });

  final _MeasuredMessage message;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    // รายการเตี้ยกว่าบับเบิล เช่นข้อความแจ้งสถานะสั้น ๆ เว้นที่ไว้เท่าเดิมโดยไม่วาดอะไร
    if (message.height < 28) return SizedBox(height: message.height);
    final maxBubble = screenWidth * 0.72;
    final showDivider =
        message.hasDivider && message.height >= _dividerHeight + 28;
    final divider = showDivider ? _dividerHeight : 0.0;
    final bodyHeight = message.height - divider - 4;
    final Widget body = switch (message.kind) {
      'c' => _CardBone(
        width: (screenWidth * 0.75).clamp(0.0, 320.0),
        height: bodyHeight,
      ),
      'i' => SkeletonShimmer(
        child: SkeletonBox(
          width: maxBubble.clamp(0.0, 220.0),
          height: bodyHeight,
          borderRadius: 16,
        ),
      ),
      _ => SkeletonShimmer(
        child: _BubbleBone(
          // ตัวอักษร 15px กว้างราว 7.5px ต่อตัว บวก padding ซ้ายขวา 28
          width: bodyHeight > 48
              ? maxBubble
              : (message.textLength * 7.5 + 28).clamp(48.0, maxBubble),
          height: bodyHeight,
          isMine: message.isMine,
        ),
      ),
    };
    return SizedBox(
      height: message.height,
      child: Column(
        children: [
          if (showDivider) const SkeletonShimmer(child: _TimeDividerBone()),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: message.isMine
                ? Align(alignment: AlignmentDirectional.centerEnd, child: body)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (message.hasAvatar)
                        const Padding(
                          padding: EdgeInsets.only(right: 8, bottom: 2),
                          child: SkeletonShimmer(
                            child: SkeletonBox(
                              width: 28,
                              height: 28,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 36),
                      Flexible(child: body),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดในแชทสูงตามที่วัดได้ มีรูปด้านบนเมื่อการ์ดสูงพอ
/// แล้วตามด้วยหัวข้อ กล่องรายละเอียด และปุ่มหลัก
class _CardBone extends StatelessWidget {
  const _CardBone({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    // แสดงส่วนย่อยเท่าที่ความสูงที่วัดได้รองรับ การ์ดเตี้ยจึงเหลือกล่องเดียวไม่ล้น
    final hasImage = height >= 360;
    final hasButton = height >= 150;
    final hasLines = height >= 90;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage) ...[
              const SkeletonBox(height: 210, borderRadius: 10),
              const SizedBox(height: 12),
            ],
            if (hasLines) ...[
              const FractionallySizedBox(
                widthFactor: 0.7,
                child: SkeletonBox(height: 14, borderRadius: 5),
              ),
              const SizedBox(height: 6),
              const FractionallySizedBox(
                widthFactor: 0.9,
                child: SkeletonBox(height: 12, borderRadius: 5),
              ),
              const SizedBox(height: 10),
            ],
            const Expanded(
              child: SkeletonBox(height: double.infinity, borderRadius: 12),
            ),
            if (hasButton) ...[
              const SizedBox(height: 12),
              const SkeletonBox(height: 42, borderRadius: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// บับเบิลข้อความบรรทัดเดียว: ตัวอักษร 15 x 1.35 + padding บนล่าง 10
const _bubbleHeight = 40.0;

class _BubbleBone extends StatelessWidget {
  const _BubbleBone({
    required this.width,
    required this.isMine,
    this.height = _bubbleHeight,
  });

  final double width;
  final bool isMine;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 20),
        ),
      ),
    ),
  );
}

/// ตัวคั่นเวลา: ข้อความ 12px กับ padding แนวตั้ง 12
class _TimeDividerBone extends StatelessWidget {
  const _TimeDividerBone();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: Center(child: SkeletonBox(width: 60, height: 12, borderRadius: 6)),
  );
}

class _IncomingBubbleBone extends StatelessWidget {
  const _IncomingBubbleBone({required this.width, this.showAvatar = false});

  final double width;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showAvatar)
          const Padding(
            padding: EdgeInsets.only(right: 8, bottom: 2),
            child: SkeletonBox(width: 28, height: 28, shape: BoxShape.circle),
          )
        else
          const SizedBox(width: 36),
        _BubbleBone(width: width, isMine: false),
      ],
    ),
  );
}

class _OutgoingBubbleBone extends StatelessWidget {
  const _OutgoingBubbleBone({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: _BubbleBone(width: width, isMine: true),
    ),
  );
}

/// การ์ดคำขอเช่าแบบ BookingRequestBubbleCard: พื้นขาว ขอบ E2E8F0 มุม 16
/// padding 12 รูปสูง 210 หัวข้อ ปุ่มดูสินค้า 36 กล่องรายละเอียด และปุ่มหลัก 42
class _BookingCardBone extends StatelessWidget {
  const _BookingCardBone({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Container(
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 210, borderRadius: 10),
            SizedBox(height: 12),
            FractionallySizedBox(
              widthFactor: 0.7,
              child: SkeletonBox(height: 14, borderRadius: 5),
            ),
            SizedBox(height: 6),
            FractionallySizedBox(
              widthFactor: 0.9,
              child: SkeletonBox(height: 12, borderRadius: 5),
            ),
            SizedBox(height: 10),
            SkeletonBox(height: 36, borderRadius: 10),
            SizedBox(height: 8),
            SkeletonBox(height: 140, borderRadius: 12),
            SizedBox(height: 12),
            SkeletonBox(height: 42, borderRadius: 12),
          ],
        ),
      ),
    ),
  );
}

/// อวาตาร์อ่านแล้วขนาด 16 ใต้ข้อความล่าสุดของเรา
class _ReadReceiptBone extends StatelessWidget {
  const _ReadReceiptBone();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Padding(
      padding: EdgeInsets.only(top: 2, right: 2),
      child: SkeletonBox(width: 16, height: 16, shape: BoxShape.circle),
    ),
  );
}

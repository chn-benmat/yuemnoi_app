import 'package:intl/intl.dart';

/// ขั้นตอนในกระบวนการคืนอุปกรณ์
enum RentalReturnStep {
  /// 1. อยู่ระหว่างการเช่า (กำลังใช้งาน)
  inProgress,

  /// 2. แจ้งเตือนฉุกเฉินใกล้หมดเวลา (Urgent Alarm)
  nearReturnAlert,

  /// 3. อยู่ระหว่างการถ่ายภาพสดตรวจสอบสภาพเครื่อง (Live Camera Mode)
  liveVerification,

  /// 4. ส่งรูปแล้ว รอส่งมอบเครื่องคืนที่จุดนัดพบ (Awaiting Handover)
  awaitingHandover,

  /// 5. ร้านค้าตรวจสอบสภาพเครื่องจริง (Merchant Inspecting)
  lenderInspecting,

  /// 6. ร้านค้ายืนยันเครื่องแล้ว แสดง Dynamic QR Code ให้ลูกค้าสแกน
  merchantQrReady,

  /// 7. สแกนสำเร็จ จบกระบวนการ คืนเงินมัดจำสมบูรณ์ (Completed)
  completed,
}

/// สลับบทบาทสำหรับทดสอบและใช้งาน (ผู้เช่า vs ผู้ให้เช่า)
enum RentalUserRole {
  /// มุมมองผู้เช่า (Customer / Renter)
  renter,

  /// มุมมองผู้ปล่อยเช่า (Store / Lender)
  lender,
}

/// ภาพถ่ายยืนยันสภาพเครื่องสดผ่านกล้อง
class ReturnInspectionPhoto {
  final String angleKey;
  final String angleTitle;
  final String? localPath;
  final String? imageUrl;
  final String challengeCode;
  final DateTime timestamp;
  final String? locationText;

  const ReturnInspectionPhoto({
    required this.angleKey,
    required this.angleTitle,
    this.localPath,
    this.imageUrl,
    required this.challengeCode,
    required this.timestamp,
    this.locationText,
  });

  bool get hasPhoto =>
      (localPath != null && localPath!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  String get formattedTime {
    try {
      return DateFormat('HH:mm:ss น. (d MMM yyyy)', 'th').format(timestamp);
    } catch (_) {
      return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')} น.';
    }
  }

  ReturnInspectionPhoto copyWith({
    String? localPath,
    String? imageUrl,
    String? challengeCode,
    DateTime? timestamp,
    String? locationText,
  }) {
    return ReturnInspectionPhoto(
      angleKey: angleKey,
      angleTitle: angleTitle,
      localPath: localPath ?? this.localPath,
      imageUrl: imageUrl ?? this.imageUrl,
      challengeCode: challengeCode ?? this.challengeCode,
      timestamp: timestamp ?? this.timestamp,
      locationText: locationText ?? this.locationText,
    );
  }
}

/// ข้อมูลการเช่าและขั้นตอนการคืนอุปกรณ์ทั้งหมด
class RentalReturnSession {
  final int rentalId;
  final int? itemId;
  final String itemName;
  final String itemImageUrl;
  final String category;
  final String renterId;
  final String renterName;
  final String lenderId;
  final String lenderName;
  final String lenderPhone;
  final DateTime startAt;
  final DateTime endAt;
  final String pickupLocation;
  final double totalPrice;
  final double depositAmount;
  final RentalReturnStep step;
  final List<ReturnInspectionPhoto> photos;
  final Map<String, bool> checklist;
  final String dynamicChallengeCode;
  final String? merchantQrToken;
  final String? merchantOtp;
  final bool isLenderConfirmed;
  final DateTime? completedAt;

  const RentalReturnSession({
    required this.rentalId,
    this.itemId,
    required this.itemName,
    required this.itemImageUrl,
    required this.category,
    required this.renterId,
    required this.renterName,
    required this.lenderId,
    required this.lenderName,
    required this.lenderPhone,
    required this.startAt,
    required this.endAt,
    required this.pickupLocation,
    required this.totalPrice,
    required this.depositAmount,
    this.step = RentalReturnStep.inProgress,
    required this.photos,
    required this.checklist,
    required this.dynamicChallengeCode,
    this.merchantQrToken,
    this.merchantOtp,
    this.isLenderConfirmed = false,
    this.completedAt,
  });

  /// เลขที่คำสั่งซื้อ/เลขออเดอร์ (Order Number)
  String get orderNumber => 'YM-${rentalId.toString().padLeft(5, '0')}';

  /// สรุปเวลาคงเหลือโดยประมาณ เช่น "ประมาณ 2 ชั่วโมง 15 นาที" หรือ "ประมาณ 1 วัน"
  String get remainingDurationText {
    if (step == RentalReturnStep.completed) return 'คืนของเรียบร้อยแล้ว';

    final now = DateTime.now();
    final diff = endAt.difference(now);

    if (diff.isNegative) {
      final overMinutes = diff.abs().inMinutes;
      if (overMinutes < 60) {
        return 'เลยกำหนดมาแล้ว $overMinutes นาที';
      }
      final overHours = diff.abs().inHours;
      return 'เลยกำหนดมาแล้ว $overHours ชั่วโมง';
    }

    final totalMinutes = diff.inMinutes;
    if (totalMinutes < 60) {
      return 'อีกประมาณ $totalMinutes นาที';
    }

    final hours = diff.inHours;
    final minutes = totalMinutes % 60;
    if (hours < 24) {
      if (minutes > 0) {
        return 'อีกประมาณ $hours ชั่วโมง $minutes นาที';
      }
      return 'อีกประมาณ $hours ชั่วโมง';
    }

    final days = diff.inDays;
    final remainHours = hours % 24;
    if (remainHours > 0) {
      return 'อีกประมาณ $days วัน $remainHours ชั่วโมง';
    }
    return 'อีกประมาณ $days วัน';
  }

  /// แสดงกำหนดเวลาเช่าได้ถึง เช่น "วันนี้ เวลา 18:00 น." หรือ "12 ก.ย. 2569 เวลา 18:00 น."
  String get endAtFormatted {
    final now = DateTime.now();
    final isToday =
        now.year == endAt.year &&
        now.month == endAt.month &&
        now.day == endAt.day;
    final timeStr = DateFormat('HH:mm น.', 'th').format(endAt);

    if (isToday) {
      return 'วันนี้ เวลา $timeStr';
    }
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow =
        tomorrow.year == endAt.year &&
        tomorrow.month == endAt.month &&
        tomorrow.day == endAt.day;
    if (isTomorrow) {
      return 'พรุ่งนี้ เวลา $timeStr';
    }

    return DateFormat('d MMM yyyy เวลา HH:mm น.', 'th').format(endAt);
  }

  /// สรุปเวลาที่ต้องคืน เช่น "ต้องคืนภายใน: 18:00 น."
  String get deadlineSummary {
    final timeStr = DateFormat('HH:mm น.', 'th').format(endAt);
    return 'ต้องคืนภายใน: $timeStr';
  }

  /// ใกล้ถึงกำหนดคืน (เหลือน้อยกว่า 1 ชั่วโมง)
  bool get isNearDeadline {
    if (step == RentalReturnStep.completed) return false;
    final diff = endAt.difference(DateTime.now());
    return !diff.isNegative && diff.inMinutes <= 60;
  }

  /// เลยเวลาคืนแล้วหรือไม่
  bool get isOverdue {
    if (step == RentalReturnStep.completed) return false;
    return endAt.isBefore(DateTime.now());
  }

  /// สภาพตรวจครบทุกมุมหรือไม่
  bool get hasAllMandatoryPhotos {
    return photos.length >= 3 && photos.every((p) => p.hasPhoto);
  }

  /// เช็กลิสต์ครบถ้วนแล้วหรือไม่
  bool get isChecklistComplete {
    return (checklist['power_on'] ?? false) &&
        (checklist['no_new_cracks'] ?? false) &&
        (checklist['accessories_complete'] ?? false);
  }

  RentalReturnSession copyWith({
    RentalReturnStep? step,
    List<ReturnInspectionPhoto>? photos,
    Map<String, bool>? checklist,
    String? dynamicChallengeCode,
    String? merchantQrToken,
    String? merchantOtp,
    bool? isLenderConfirmed,
    DateTime? completedAt,
    DateTime? endAt,
  }) {
    return RentalReturnSession(
      rentalId: rentalId,
      itemId: itemId,
      itemName: itemName,
      itemImageUrl: itemImageUrl,
      category: category,
      renterId: renterId,
      renterName: renterName,
      lenderId: lenderId,
      lenderName: lenderName,
      lenderPhone: lenderPhone,
      startAt: startAt,
      endAt: endAt ?? this.endAt,
      pickupLocation: pickupLocation,
      totalPrice: totalPrice,
      depositAmount: depositAmount,
      step: step ?? this.step,
      photos: photos ?? this.photos,
      checklist: checklist ?? this.checklist,
      dynamicChallengeCode: dynamicChallengeCode ?? this.dynamicChallengeCode,
      merchantQrToken: merchantQrToken ?? this.merchantQrToken,
      merchantOtp: merchantOtp ?? this.merchantOtp,
      isLenderConfirmed: isLenderConfirmed ?? this.isLenderConfirmed,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// สร้าง Mock Data ที่สมบูรณ์แบบสำหรับทดสอบและใช้งาน โดยขึ้นตรงกับสินค้าแต่ละตัวตาม rentalId
  static RentalReturnSession createMockSession({int? rentalId}) {
    final effectiveId = rentalId ?? 1024;
    final now = DateTime.now();
    // กำหนดให้คืนในอีก 2 ชั่วโมง 15 นาทีข้างหน้า เพื่อแสดงกรณี "เช่าได้ถึง 18:00 น."
    final scheduledReturn = now.add(const Duration(hours: 2, minutes: 15));
    final randomChallenge = 'YM-${effectiveId.toString().padLeft(5, '0')}';

    // แคตตาล็อกจำลองข้อมูลที่สมจริงสอดคล้องกับรายการสินค้าจริง
    final catalog = <int, Map<String, dynamic>>{
      1: {
        'itemName': 'กล้อง Canon EOS R50 + เลนส์ 18-45mm',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&auto=format&fit=crop',
        'category': 'กล้องและอุปกรณ์ถ่ายภาพ',
        'price': 650.0,
        'deposit': 2000.0,
        'lenderName': 'ร้าน Lens & Shutter BKK',
        'lenderPhone': '082-345-6789',
        'pickupLocation': 'สยามพารากอน (ชั้น 3 โซนไอที หน้าร้านกาแฟ)',
        'photo1': '1. ด้านหน้าจอเปิดติด และเซนเซอร์',
        'photo2': '2. ตัวบอดี้ เลนส์ และฝาปิดหน้าเลนส์',
        'photo3': '3. แบตเตอรี่ แท่นชาร์จ สายคล้อง & Serial Number',
      },
      2: {
        'itemName': 'Sony Alpha A7 IV (Body)',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1502920917128-1aa500764cbd?w=800&auto=format&fit=crop',
        'category': 'กล้องและเลนส์',
        'price': 1200.0,
        'deposit': 4000.0,
        'lenderName': 'ร้าน Bangkok Camera Hub (ผู้ปล่อยเช่า)',
        'lenderPhone': '089-123-4567',
        'pickupLocation': 'ซีคอน บางแค (ชั้น 2 หน้าร้านกาแฟ)',
        'photo1': '1. ด้านหน้าจอเปิดติด',
        'photo2': '2. รอบตัวเครื่องและเซนเซอร์',
        'photo3': '3. อุปกรณ์เสริม & Serial Number',
      },
      1024: {
        'itemName': 'Sony Alpha A7 IV (Body)',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1502920917128-1aa500764cbd?w=800&auto=format&fit=crop',
        'category': 'กล้องและเลนส์',
        'price': 1200.0,
        'deposit': 4000.0,
        'lenderName': 'ร้าน Bangkok Camera Hub (ผู้ปล่อยเช่า)',
        'lenderPhone': '089-123-4567',
        'pickupLocation': 'ซีคอน บางแค (ชั้น 2 หน้าร้านกาแฟ)',
        'photo1': '1. ด้านหน้าจอเปิดติด',
        'photo2': '2. รอบตัวเครื่องและเซนเซอร์',
        'photo3': '3. อุปกรณ์เสริม & Serial Number',
      },
      3: {
        'itemName': 'โดรน DJI Mavic 3 Pro Cine',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1508614589041-895b88991e3e?w=800&auto=format&fit=crop',
        'category': 'โดรนและอุปกรณ์การบิน',
        'price': 1800.0,
        'deposit': 6000.0,
        'lenderName': 'ร้าน SkyHigh Drone Studio',
        'lenderPhone': '081-888-9900',
        'pickupLocation': 'เซ็นทรัล ลาดพร้าว (ชั้น 2 ทางเชื่อม BTS)',
        'photo1': '1. มอเตอร์และใบพัดทั้ง 4 แกน',
        'photo2': '2. กิมบอลและเซนเซอร์กล้อง 3 เลนส์',
        'photo3': '3. รีโมตคอนโทรล แบตเตอรี่ & Serial Number',
      },
      1025: {
        'itemName': 'โดรน DJI Mavic 3 Pro Cine',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1508614589041-895b88991e3e?w=800&auto=format&fit=crop',
        'category': 'โดรนและอุปกรณ์การบิน',
        'price': 1800.0,
        'deposit': 6000.0,
        'lenderName': 'ร้าน SkyHigh Drone Studio',
        'lenderPhone': '081-888-9900',
        'pickupLocation': 'เซ็นทรัล ลาดพร้าว (ชั้น 2 ทางเชื่อม BTS)',
        'photo1': '1. มอเตอร์และใบพัดทั้ง 4 แกน',
        'photo2': '2. กิมบอลและเซนเซอร์กล้อง 3 เลนส์',
        'photo3': '3. รีโมตคอนโทรล แบตเตอรี่ & Serial Number',
      },
      4: {
        'itemName': 'MacBook Pro 16" M2 Max (32GB / 1TB)',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=800&auto=format&fit=crop',
        'category': 'แล็ปท็อปและคอมพิวเตอร์',
        'price': 1500.0,
        'deposit': 8000.0,
        'lenderName': 'ร้าน Siam Mac Rental',
        'lenderPhone': '090-999-1122',
        'pickupLocation': 'อาคารสีลมเอจ (ชั้น B ทางเชื่อม MRT สีลม)',
        'photo1': '1. หน้าจอเปิดติด และคีย์บอร์ดเรืองแสง',
        'photo2': '2. รอบตัวเครื่อง ฝาบน-ล่าง ไร้รอยบุบ',
        'photo3': '3. หัวชาร์จ MagSafe สายชาร์จ & Serial Number',
      },
      1026: {
        'itemName': 'MacBook Pro 16" M2 Max (32GB / 1TB)',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=800&auto=format&fit=crop',
        'category': 'แล็ปท็อปและคอมพิวเตอร์',
        'price': 1500.0,
        'deposit': 8000.0,
        'lenderName': 'ร้าน Siam Mac Rental',
        'lenderPhone': '090-999-1122',
        'pickupLocation': 'อาคารสีลมเอจ (ชั้น B ทางเชื่อม MRT สีลม)',
        'photo1': '1. หน้าจอเปิดติด และคีย์บอร์ดเรืองแสง',
        'photo2': '2. รอบตัวเครื่อง ฝาบน-ล่าง ไร้รอยบุบ',
        'photo3': '3. หัวชาร์จ MagSafe สายชาร์จ & Serial Number',
      },
      13: {
        'itemName': 'สว่านกระแทกไร้สาย Bosch 18V รุ่น GSB 18V-50',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1504148455328-c376907d081c?w=800&auto=format&fit=crop',
        'category': 'เครื่องมือช่างและงานก่อสร้าง',
        'price': 250.0,
        'deposit': 1000.0,
        'lenderName': 'ร้าน ช่างทอง ทูลส์ & เซอร์วิส',
        'lenderPhone': '086-777-3344',
        'pickupLocation': 'ไทวัสดุ สาขาบางนา (จุดรับสินค้าชั้น 1)',
        'photo1': '1. สวิตช์ทำงาน ไฟ LED และหัวจับดอกสว่าน',
        'photo2': '2. รอบตัวเครื่อง โครงสร้างและแบตเตอรี่',
        'photo3': '3. กล่องพกพา แท่นชาร์จ ดอกสว่าน & S/N',
      },
      14: {
        'itemName': 'เครื่องฉีดน้ำแรงดันสูง Karcher 120 Bar K2',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=800&auto=format&fit=crop',
        'category': 'เครื่องมือช่างและงานก่อสร้าง',
        'price': 350.0,
        'deposit': 1500.0,
        'lenderName': 'ร้าน สะอาดโปร คลีนนิ่ง อีควิปเมนต์',
        'lenderPhone': '085-555-1234',
        'pickupLocation': 'เซ็นทรัล พระราม 2 (ลานจอดรถเสา G12)',
        'photo1': '1. ตัวมอเตอร์เครื่องและสวิตช์เปิดปิด',
        'photo2': '2. สายฉีดแรงดันสูง ปืนฉีด และหัวฉีดปรับระดับ',
        'photo3': '3. ข้อต่อ สายไฟ และ Serial Number',
      },
      18: {
        'itemName': 'โปรเจกเตอร์พกพา Wanbo Full HD พร้อมจอพับ 100 นิ้ว',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1517604931442-7e0c8ed2963c?w=800&auto=format&fit=crop',
        'category': 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
        'price': 400.0,
        'deposit': 1500.0,
        'lenderName': 'ร้าน Home Cinema BKK',
        'lenderPhone': '083-444-5566',
        'pickupLocation': 'เดอะมอลล์ ท่าพระ (ชั้น 3 หน้าร้านหนังสือ)',
        'photo1': '1. เลนส์ฉายภาพและหน้าจอฉายติดสมบูรณ์',
        'photo2': '2. บอดี้โปรเจกเตอร์และช่องระบายความร้อน',
        'photo3': '3. รีโมต สายไฟ จอพับ 100 นิ้ว & Serial Number',
      },
      19: {
        'itemName': 'เต็นท์ Coleman Instant Cabin 4 คน กางอัตโนมัติ',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1504280390367-361c6d9f38f4?w=800&auto=format&fit=crop',
        'category': 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
        'price': 450.0,
        'deposit': 1500.0,
        'lenderName': 'ร้าน CampLife Thailand Outdoor',
        'lenderPhone': '089-988-7766',
        'pickupLocation': 'เมกา บางนา (หน้าทางเข้าโฮมโปร)',
        'photo1': '1. ตัวเต็นท์ ผ้าใบ และซิปเปิดปิดครบทุกบาน',
        'photo2': '2. โครงเสาเต็นท์และสมอบก',
        'photo3': '3. ถุงเก็บเต็นท์ ผ้าคลุมกันฝน & ป้ายแบรนด์',
      },
      109: {
        'itemName': 'ชุดลำโพงบลูทูธ JBL PartyBox 310 พร้อมไมค์ลอย',
        'itemImageUrl':
            'https://images.unsplash.com/photo-1545454675-3531b543be5d?w=800&auto=format&fit=crop',
        'category': 'เครื่องเสียงและอุปกรณ์จัดงาน',
        'price': 750.0,
        'deposit': 3000.0,
        'lenderName': 'ร้าน Sound & Beat Studio',
        'lenderPhone': '081-777-6655',
        'pickupLocation': 'บีทีเอส อโศก (ทางออก 3 หน้าห้างเทอร์มินอล 21)',
        'photo1': '1. แผงควบคุม ไฟ LED หน้าลำโพงติดครบ',
        'photo2': '2. รอบตู้ลำโพง ด้ามลาก และล้อเลื่อน',
        'photo3': '3. ไมค์ไร้สาย สายชาร์จไฟ AC & Serial Number',
      },
    };

    // เลือกข้อมูลตาม ID หากไม่มีให้หมุนเวียนตามโมดูลัส
    final targetItem =
        catalog[effectiveId] ??
        catalog[catalog.keys.elementAt(effectiveId.abs() % catalog.length)]!;

    return RentalReturnSession(
      rentalId: effectiveId,
      itemName: targetItem['itemName'] as String,
      itemImageUrl: targetItem['itemImageUrl'] as String,
      category: targetItem['category'] as String,
      renterId: 'renter-user-${effectiveId.toString().padLeft(3, '0')}',
      renterName: 'คุณพัชรพล ผู้เช่า',
      lenderId: '0648414b-83a1-42b0-9abb-dc635258ec4a',
      lenderName: targetItem['lenderName'] as String,
      lenderPhone: targetItem['lenderPhone'] as String,
      startAt: now.subtract(const Duration(hours: 5)),
      endAt: scheduledReturn,
      pickupLocation: targetItem['pickupLocation'] as String,
      totalPrice: (targetItem['price'] as double),
      depositAmount: (targetItem['deposit'] as double),
      step: RentalReturnStep.inProgress,
      dynamicChallengeCode: randomChallenge,
      photos: [
        ReturnInspectionPhoto(
          angleKey: 'angle_1',
          angleTitle: targetItem['photo1'] as String,
          challengeCode: randomChallenge,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_2',
          angleTitle: targetItem['photo2'] as String,
          challengeCode: randomChallenge,
          timestamp: now,
        ),
        ReturnInspectionPhoto(
          angleKey: 'angle_3',
          angleTitle: targetItem['photo3'] as String,
          challengeCode: randomChallenge,
          timestamp: now,
        ),
      ],
      checklist: {
        'power_on': false,
        'no_new_cracks': false,
        'accessories_complete': false,
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_text_styles.dart';
import '../../widgets/support/faq_widgets.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final List<FaqItemData> _faqs = [
    FaqItemData(
      question: 'สถานะของแอปพลิเคชัน',
      answer:
          'Yuemnoi ช่วยให้คุณค้นหาอุปกรณ์ ลงประกาศ และคุยรายละเอียดการเช่าผ่านแชทได้ ขณะนี้ฟีเจอร์กระเป๋าเงิน การเติมเงิน และ QR ชำระเงินบางส่วนยังเป็นระบบจำลอง จึงยังไม่รองรับการรับชำระเงินจริงครบทุกขั้นตอน หน้านี้ไม่ได้แสดงสถานะเซิร์ฟเวอร์แบบเรียลไทม์',
      isExpanded: true,
    ),
    FaqItemData(
      question: 'การลงทะเบียนและการยืนยันตัวตน',
      answer:
          'สามารถลงทะเบียนได้ผ่านอีเมลหรือบัญชี Google ของคุณ หลังจากลงทะเบียนแล้ว ระบบจะส่งอีเมลยืนยันตัวตนไปยังอีเมลที่คุณสมัคร กรุณายืนยันอีเมลก่อนใช้งาน',
    ),
    FaqItemData(
      question: 'ข้อกำหนดสำหรับผู้ให้เช่า (Lender)',
      answer:
          'ผู้ให้เช่าต้องผ่านการยืนยันตัวตนก่อน สามารถลงประกาศอุปกรณ์ได้ทันที โดยต้องระบุรายละเอียด ราคา และเงื่อนไขการเช่าอย่างถูกต้องครบถ้วน',
    ),
    FaqItemData(
      question: 'ข้อกำหนดสำหรับผู้เช่า (Renter)',
      answer:
          'ผู้เช่าต้องยืนยันตัวตนก่อนทำการเช่า และต้องปฏิบัติตามเงื่อนไขที่ผู้ให้เช่ากำหนด รวมถึงรับผิดชอบค่าเสียหายที่เกิดขึ้นจากการใช้งาน',
    ),
    FaqItemData(
      question: 'ลบบัญชีอย่างไร?',
      answer:
          'ไปที่ โปรไฟล์ → ศูนย์ความเป็นส่วนตัว → ลบบัญชีผู้ใช้ แล้วแตะ “ยืนยันลบบัญชี” '
          'หากมีรายการเช่าที่ค้างอยู่ ให้ดำเนินการให้เสร็จก่อนส่งคำขอ\n\n'
          'เมื่อส่งคำขอสำเร็จ ระบบจะซ่อนโปรไฟล์และประกาศของคุณทันทีและนำคุณออกจากระบบ '
          'บัญชีจะถูกลบถาวรเมื่อครบ 30 วัน หากเปลี่ยนใจ ให้เข้าสู่ระบบและกด “ยืนยัน” '
          'ในหน้าต่าง “กู้คืนบัญชี” ก่อนครบกำหนด',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9FD),
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          'คำถามที่พบบ่อย',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'เริ่มต้นใช้งาน · ${_faqs.length} คำถาม',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF665D73),
                ),
              ),
            ),
            ..._faqs.asMap().entries.map((entry) {
              final index = entry.key;
              final faq = entry.value;
              return FaqTile(
                item: faq,
                onToggle: () {
                  setState(() {
                    final willExpand = !_faqs[index].isExpanded;
                    for (int i = 0; i < _faqs.length; i++) {
                      _faqs[i].isExpanded = (i == index) ? willExpand : false;
                    }
                  });
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

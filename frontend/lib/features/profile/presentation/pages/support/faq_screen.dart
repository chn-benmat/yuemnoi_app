import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
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
          'ระบบและเซิร์ฟเวอร์ทั้งหมดของแอปพลิเคชัน Yuemnoi เปิดให้บริการตามปกติ คุณสามารถลงประกาศปล่อยเช่า ค้นหาอุปกรณ์ จองและชำระเงินออนไลน์ รวมถึงติดต่อสนทนาผ่านระบบแชทได้ตลอด 24 ชั่วโมง ทั้งนี้ หากมีช่วงเวลาปิดปรับปรุงระบบเพื่อพัฒนายกระดับการบริการ ทีมงานจะแจ้งให้ทราบล่วงหน้าผ่านการแจ้งเตือนในแอปพลิเคชัน',
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'คำถามที่พบบ่อย',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            Text(
              'คำถามที่พบบ่อย',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 20),
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

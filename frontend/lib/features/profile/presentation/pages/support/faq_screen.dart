import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final List<_FaqItemData> _faqs = [
    _FaqItemData(
      question: 'สถานะของแอปพลิเคชัน',
      answer:
          'ระบบและเซิร์ฟเวอร์ทั้งหมดของแอปพลิเคชัน Yuemnoi เปิดให้บริการตามปกติ คุณสามารถลงประกาศปล่อยเช่า ค้นหาอุปกรณ์ จองและชำระเงินออนไลน์ รวมถึงติดต่อสนทนาผ่านระบบแชทได้ตลอด 24 ชั่วโมง ทั้งนี้ หากมีช่วงเวลาปิดปรับปรุงระบบเพื่อพัฒนายกระดับการบริการ ทีมงานจะแจ้งให้ทราบล่วงหน้าผ่านการแจ้งเตือนในแอปพลิเคชัน',
      isExpanded: true,
    ),
    _FaqItemData(
      question: 'การลงทะเบียนและการยืนยันตัวตน',
      answer:
          'สามารถลงทะเบียนได้ผ่านอีเมลหรือบัญชี Google ของคุณ หลังจากลงทะเบียนแล้ว ระบบจะส่งอีเมลยืนยันตัวตนไปยังอีเมลที่คุณสมัคร กรุณายืนยันอีเมลก่อนใช้งาน',
    ),
    _FaqItemData(
      question: 'ข้อกำหนดสำหรับผู้ให้เช่า (Lender)',
      answer:
          'ผู้ให้เช่าต้องผ่านการยืนยันตัวตนก่อน สามารถลงประกาศอุปกรณ์ได้ทันที โดยต้องระบุรายละเอียด ราคา และเงื่อนไขการเช่าอย่างถูกต้องครบถ้วน',
    ),
    _FaqItemData(
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
              return _FaqTile(
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

class _FaqItemData {
  final String question;
  final String answer;
  bool isExpanded;

  _FaqItemData({
    required this.question,
    required this.answer,
    this.isExpanded = false,
  });
}

class _FaqTile extends StatelessWidget {
  final _FaqItemData item;
  final VoidCallback onToggle;

  const _FaqTile({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'Q',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.question,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: item.isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.primaryColor,
                    ),
                  ),
                ],
              ),
              if (item.isExpanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  item.answer,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    color: AppColors.labelColor,
                    height: 1.7,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

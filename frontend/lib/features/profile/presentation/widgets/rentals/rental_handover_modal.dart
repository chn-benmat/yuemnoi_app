import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';

/// Modal สำหรับกระบวนการ "ตรวจรับอุปกรณ์ & ชำระเงิน" เมื่อนัดพบกัน (In-Person Handover)
class RentalHandoverModal extends StatefulWidget {
  final int? bookingId;
  final String itemTitle;
  final String? itemImageUrl;
  final String ownerName;
  final String? renterName;
  final double totalPrice;
  final String paymentMethod; // 'promptpay' หรือ 'cash'
  final bool initialIsOwner;
  final ValueChanged<String>? onHandoverSuccess;

  const RentalHandoverModal({
    super.key,
    this.bookingId,
    required this.itemTitle,
    this.itemImageUrl,
    required this.ownerName,
    this.renterName,
    required this.totalPrice,
    this.paymentMethod = 'promptpay',
    this.initialIsOwner = false,
    this.onHandoverSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    int? bookingId,
    required String itemTitle,
    String? itemImageUrl,
    required String ownerName,
    String? renterName,
    required double totalPrice,
    String paymentMethod = 'promptpay',
    bool initialIsOwner = false,
    ValueChanged<String>? onHandoverSuccess,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => RentalHandoverModal(
        bookingId: bookingId,
        itemTitle: itemTitle,
        itemImageUrl: itemImageUrl,
        ownerName: ownerName,
        renterName: renterName,
        totalPrice: totalPrice,
        paymentMethod: paymentMethod,
        initialIsOwner: initialIsOwner,
        onHandoverSuccess: onHandoverSuccess,
      ),
    );
  }

  @override
  State<RentalHandoverModal> createState() => _RentalHandoverModalState();
}

class _RentalHandoverModalState extends State<RentalHandoverModal> {
  late bool _isOwner;
  int _currentStep = 0; // 0: ตรวจสภาพ, 1: ชำระเงิน, 2: รหัสยืนยัน PIN, 3: สำเร็จ

  // สเต็ป 1: Checklist
  bool _checkPowerOn = true;
  bool _checkAccessories = true;
  bool _checkNoNewDamage = true;

  // สเต็ป 3: Handover PIN (รหัส 4 หลักสำหรับยืนยันสองฝั่ง)
  final String _generatedPin = '8492';
  final TextEditingController _pinController = TextEditingController();
  String? _pinErrorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _isOwner = widget.initialIsOwner;
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _completeHandover() async {
    setState(() => _isSubmitting = true);

    // บันทึกลง Supabase booking_tb เป็น status 'active' (ถ้ามี bookingId)
    if (widget.bookingId != null && SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.client
            .from('booking_tb')
            .update({'status': 'active'})
            .eq('id', widget.bookingId!);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _currentStep = 3; // หน้าสำเร็จ
    });

    widget.onHandoverSuccess?.call('active');
  }

  void _verifyPinAndSubmit() {
    if (_pinController.text.trim() == _generatedPin) {
      setState(() => _pinErrorMessage = null);
      _completeHandover();
    } else {
      setState(() {
        _pinErrorMessage = 'รหัส PIN ไม่ถูกต้อง (รหัสตัวอย่างคือ $_generatedPin)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ขีดจับลาก
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // หัวแถว: ชื่อหัวข้อ + ปุ่มสลับมุมมองบทบาท (เพื่อความสะดวกในการทดสอบทั้งสองฝั่ง)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ตรวจรับ & ชำระเงิน',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E2022),
                    ),
                  ),
                  // สวิตช์สลับดูมุมมองผู้เช่า / ผู้ปล่อยเช่า
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRoleChip(label: 'มุมมองผู้เช่า', isSelected: !_isOwner, onTap: () => setState(() => _isOwner = false)),
                        _buildRoleChip(label: 'ผู้ปล่อยเช่า', isSelected: _isOwner, onTap: () => setState(() => _isOwner = true)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // การ์ดแสดงชื่ออุปกรณ์ที่ตรวจรับ
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.itemTitle,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E2022),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // สเต็ปบาร์ (Step Progress)
              if (_currentStep < 3) ...[
                Row(
                  children: [
                    _buildStepIndicator(stepIndex: 0, label: '1. ตรวจสภาพ'),
                    _buildStepLine(isActive: _currentStep >= 1),
                    _buildStepIndicator(stepIndex: 1, label: '2. ชำระเงิน'),
                    _buildStepLine(isActive: _currentStep >= 2),
                    _buildStepIndicator(stepIndex: 2, label: '3. รหัสส่งมอบ'),
                  ],
                ),
                const SizedBox(height: 18),
              ],

              // เนื้อหาตามสเต็ป
              if (_currentStep == 0) _buildStepInspection(),
              if (_currentStep == 1) _buildStepPayment(),
              if (_currentStep == 2) _buildStepPinVerification(),
              if (_currentStep == 3) _buildStepSuccess(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator({required int stepIndex, required String label}) {
    final isPassed = _currentStep > stepIndex;
    final isCurrent = _currentStep == stepIndex;

    Color color = const Color(0xFF94A3B8);
    if (isCurrent) color = AppColors.primaryColor;
    if (isPassed) color = const Color(0xFF10B981);

    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: color.withValues(alpha: 0.15),
          child: isPassed
              ? const Icon(Icons.check, size: 14, color: Color(0xFF10B981))
              : Text(
                  '${stepIndex + 1}',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10.5,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine({required bool isActive}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 14),
        color: isActive ? AppColors.primaryColor : const Color(0xFFE2E8F0),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 0: ตรวจสภาพสินค้า (Inspection)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepInspection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.primaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isOwner
                      ? 'โปรดนำอุปกรณ์ให้ผู้เช่าตรวจสอบการทำงาน และถ่ายภาพเก็บเป็นหลักฐาน'
                      : 'โปรดตรวจเช็กสภาพอุปกรณ์จริงและอุปกรณ์เสริมร่วมกับผู้ปล่อยเช่า',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12.5,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        const Text(
          'รายการตรวจสอบสภาพ (Checklist):',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2022),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _checkPowerOn,
          onChanged: (v) => setState(() => _checkPowerOn = v ?? false),
          title: const Text('ตัวเครื่องเปิดติดและใช้งานได้ตามปกติ', style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primaryColor,
        ),
        CheckboxListTile(
          value: _checkAccessories,
          onChanged: (v) => setState(() => _checkAccessories = v ?? false),
          title: const Text('อุปกรณ์เสริมครบถ้วน (สายชาร์จ, แบตเตอรี่, กระเป๋า)', style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primaryColor,
        ),
        CheckboxListTile(
          value: _checkNoNewDamage,
          onChanged: (v) => setState(() => _checkNoNewDamage = v ?? false),
          title: const Text('ตรวจสอบรอยตำหนิร่วมกันเรียบร้อยแล้ว', style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primaryColor,
        ),

        const SizedBox(height: 10),
        // กล่องถ่ายรูปหลักฐาน
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF2563EB), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ภาพถ่ายสภาพก่อนส่งมอบ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E2022),
                      ),
                    ),
                    Text(
                      'บันทึกแล้ว 2 ภาพ (บันทึกอัตโนมัติ)',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
            ],
          ),
        ),

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_checkPowerOn && _checkAccessories && _checkNoNewDamage)
                ? () => setState(() => _currentStep = 1)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text(
              'ยืนยันการตรวจสภาพ ➔ ไปยังการชำระเงิน',
              style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 1: ชำระเงิน (Payment)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepPayment() {
    final isPromptPay = widget.paymentMethod == 'promptpay';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // กล่องยอดเงิน
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7400C9), Color(0xFF5200A0)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ยอดชำระสุทธิ',
                    style: TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '฿${widget.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isPromptPay ? 'พร้อมเพย์ QR' : 'ชำระเงินสด',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (isPromptPay) ...[
          // Mockup PromptPay QR Code
          Center(
            child: Container(
              width: 170,
              height: 170,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 105, color: Color(0xFF1E2022)),
                  const SizedBox(height: 4),
                  Text(
                    'PromptPay: ${widget.ownerName}',
                    style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 10.5, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isOwner
                ? 'ให้ผู้เช่าสแกน QR Code นี้ผ่านแอปธนาคาร เมื่อเงินเข้าบัญชีแล้วให้กดยืนยันด้านล่าง'
                : 'สแกน QR Code เพื่อโอนเงินยอด ฿${widget.totalPrice.toStringAsFixed(0)} แล้วกดยืนยันการโอนเงิน',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 12.5, color: Color(0xFF64748B)),
          ),
        ] else ...[
          // กรณีเงินสด
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Column(
              children: [
                const Icon(Icons.payments_rounded, color: Color(0xFF059669), size: 40),
                const SizedBox(height: 8),
                Text(
                  _isOwner
                      ? 'กรุณารับเงินสดจำนวน ฿${widget.totalPrice.toStringAsFixed(0)} จากผู้เช่าและนับให้ถูกต้อง'
                      : 'กรุณาส่งมอบเงินสดจำนวน ฿${widget.totalPrice.toStringAsFixed(0)} ให้แก่ผู้ปล่อยเช่า',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ปุ่มกดยืนยันการชำระเงิน
        if (!_isOwner) ...[
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('คุณได้แจ้งชำระเงินแล้ว กำลังรอผู้ปล่อยเช่ายืนยัน')),
                );
                setState(() => _currentStep = 2);
              },
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                isPromptPay ? 'ฉันโอนเงินเรียบร้อยแล้ว' : 'ฉันส่งมอบเงินสดเรียบร้อยแล้ว',
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ] else ...[
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _currentStep = 2);
              },
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: Text(
                'ยืนยันว่าได้รับเงินครบถ้วนแล้ว [฿${widget.totalPrice.toStringAsFixed(0)}]',
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 2: รหัสยืนยันการส่งมอบสองฝั่ง (Handover PIN)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepPinVerification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'รหัสยืนยันการรับมอบอุปกรณ์ (Handover PIN)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2022),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isOwner
              ? 'บอกรหัส 4 หลักนี้แก่ผู้เช่า เพื่อให้ผู้เช่ากรอกในเครื่องตนเองยืนยันการรับของ'
              : 'กรุณากรอกรหัส PIN 4 หลักที่ได้รับจากผู้ปล่อยเช่าเพื่อยืนยันการรับมอบ',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12.5,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 18),

        if (_isOwner) ...[
          // ฝั่งผู้ปล่อยเช่า: แสดง PIN ตัวใหญ่
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primaryColor, width: 2),
              ),
              child: Text(
                _generatedPin,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: AppColors.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'รอผู้เช่ากรอกรหัสยืนยันในเครื่อง...',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          // ปุ่มจำลองผู้เช่ากรอกรหัสสำเร็จ (สำหรับทดสอบ)
          OutlinedButton(
            onPressed: _completeHandover,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryColor,
              side: const BorderSide(color: Color(0xFFD8B4FE)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('จำลอง: ผู้เช่ากรอกรหัสตรงกัน ➔ เริ่มการเช่า'),
          ),
        ] else ...[
          // ฝั่งผู้เช่า: กล่องกรอก PIN
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••',
                    hintStyle: const TextStyle(letterSpacing: 8, color: Color(0xFFCBD5E1)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_pinErrorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _pinErrorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                _pinController.text = _generatedPin;
              },
              child: Text(
                'คลิกเพื่อใส่รหัสทดสอบ ($_generatedPin)',
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 12, color: AppColors.primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _verifyPinAndSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text(
                      'ยืนยันการรับมอบอุปกรณ์',
                      style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 3: ส่งมอบสำเร็จ (Success)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepSuccess() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
        ),
        const SizedBox(height: 14),
        const Text(
          'ส่งมอบและเริ่มการเช่าสำเร็จ!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2022),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'สถานะการเช่าเปลี่ยนเป็น "กำลังเช่า" เรียบร้อยแล้ว ตัวนับเวลาการเช่าเริ่มต้นขึ้นแล้ว',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: Color(0xFF64748B),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text(
              'เสร็จสิ้น',
              style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

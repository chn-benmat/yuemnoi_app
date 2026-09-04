import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import 'rental_review_dialog.dart';

/// Modal สำหรับกระบวนการ "ส่งคืนอุปกรณ์และจบการเช่า" (Return Inspection & Completion)
class RentalReturnModal extends StatefulWidget {
  final int? bookingId;
  final String itemTitle;
  final String? itemImageUrl;
  final String ownerName;
  final String? renterName;
  final double depositAmount; // เงินประกัน (ถ้ามี)
  final bool initialIsOwner;
  final ValueChanged<String>? onReturnSuccess;

  const RentalReturnModal({
    super.key,
    this.bookingId,
    required this.itemTitle,
    this.itemImageUrl,
    required this.ownerName,
    this.renterName,
    this.depositAmount = 0.0,
    this.initialIsOwner = false,
    this.onReturnSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    int? bookingId,
    required String itemTitle,
    String? itemImageUrl,
    required String ownerName,
    String? renterName,
    double depositAmount = 0.0,
    bool initialIsOwner = false,
    ValueChanged<String>? onReturnSuccess,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => RentalReturnModal(
        bookingId: bookingId,
        itemTitle: itemTitle,
        itemImageUrl: itemImageUrl,
        ownerName: ownerName,
        renterName: renterName,
        depositAmount: depositAmount,
        initialIsOwner: initialIsOwner,
        onReturnSuccess: onReturnSuccess,
      ),
    );
  }

  @override
  State<RentalReturnModal> createState() => _RentalReturnModalState();
}

class _RentalReturnModalState extends State<RentalReturnModal> {
  late bool _isOwner;
  int _currentStep = 0; // 0: ตรวจสภาพคืน, 1: คืนเงินประกัน/ค่าปรับ, 2: Return PIN, 3: สำเร็จ

  // สเต็ป 0: Checklist รับคืน
  bool _checkDeviceWorks = true;
  bool _checkAccessoriesReturned = true;
  bool _checkNoNewDamage = true;
  bool _isConditionPerfect = true;

  // สเต็ป 2: Return PIN
  final String _generatedReturnPin = '3816';
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

  Future<void> _completeReturn() async {
    setState(() => _isSubmitting = true);

    // บันทึกลง Supabase booking_tb เป็น status 'completed' (ถ้ามี bookingId)
    if (widget.bookingId != null && SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.client
            .from('booking_tb')
            .update({'status': 'completed'})
            .eq('id', widget.bookingId!);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _currentStep = 3; // หน้าสำเร็จ
    });

    widget.onReturnSuccess?.call('completed');
  }

  void _verifyPinAndSubmit() {
    if (_pinController.text.trim() == _generatedReturnPin) {
      setState(() => _pinErrorMessage = null);
      _completeReturn();
    } else {
      setState(() {
        _pinErrorMessage = 'รหัส Return PIN ไม่ถูกต้อง (รหัสตัวอย่างคือ $_generatedReturnPin)';
      });
    }
  }

  void _openReview() {
    Navigator.pop(context);
    RentalReviewDialog.show(
      context,
      itemTitle: widget.itemTitle,
      partnerName: _isOwner ? (widget.renterName ?? 'ผู้เช่า') : widget.ownerName,
      partnerRole: _isOwner ? 'ผู้เช่า' : 'ผู้ให้เช่า',
    );
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

              // หัวแถว + ปุ่มสลับบทบาท
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ส่งคืนอุปกรณ์ & จบการเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 17.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E2022),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRoleChip(label: 'ผู้เช่า', isSelected: !_isOwner, onTap: () => setState(() => _isOwner = false)),
                        _buildRoleChip(label: 'ผู้ปล่อยเช่า', isSelected: _isOwner, onTap: () => setState(() => _isOwner = true)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // การ์ดแสดงชื่ออุปกรณ์ที่ส่งคืน
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

              // สเต็ปบาร์
              if (_currentStep < 3) ...[
                Row(
                  children: [
                    _buildStepIndicator(stepIndex: 0, label: '1. ตรวจของคืน'),
                    _buildStepLine(isActive: _currentStep >= 1),
                    _buildStepIndicator(stepIndex: 1, label: '2. เงินประกัน'),
                    _buildStepLine(isActive: _currentStep >= 2),
                    _buildStepIndicator(stepIndex: 2, label: '3. ยืนยันการคืน'),
                  ],
                ),
                const SizedBox(height: 18),
              ],

              // เนื้อหาแต่ละสเต็ป
              if (_currentStep == 0) _buildStepReturnInspection(),
              if (_currentStep == 1) _buildStepDepositSettlement(),
              if (_currentStep == 2) _buildStepReturnPinVerification(),
              if (_currentStep == 3) _buildStepSuccess(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleChip({required String label, required bool isSelected, required VoidCallback onTap}) {
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
  // Step 0: ตรวจสภาพของคืน
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepReturnInspection() {
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
              const Icon(Icons.compare_arrows_rounded, color: AppColors.primaryColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isOwner
                      ? 'โปรดตรวจสอบอุปกรณ์เทียบกับภาพถ่ายในวันส่งมอบวันแรก เพื่อยืนยันความสมบูรณ์'
                      : 'ส่งมอบอุปกรณ์ให้ผู้ปล่อยเช่าตรวจสอบสภาพก่อนดำเนินการจบรายการ',
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
          'Checklist ตรวจรับของคืน:',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2022),
          ),
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          value: _checkDeviceWorks,
          onChanged: (v) => setState(() => _checkDeviceWorks = v ?? false),
          title: const Text('เครื่องยังทำงานได้ปกติ ไม่มีอาการผิดปกติ', style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primaryColor,
        ),
        CheckboxListTile(
          value: _checkAccessoriesReturned,
          onChanged: (v) => setState(() => _checkAccessoriesReturned = v ?? false),
          title: const Text('อุปกรณ์เสริมและกล่องบรรจุภัณฑ์คืนครบถ้วน', style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primaryColor,
        ),
        CheckboxListTile(
          value: _checkNoNewDamage,
          onChanged: (v) => setState(() => _checkNoNewDamage = v ?? false),
          title: const Text('ไม่มีรอยแตกร้าว บุบ หรือความเสียหายใหม่', style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primaryColor,
        ),

        const SizedBox(height: 10),
        // ผลการประเมิน
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isConditionPerfect = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _isConditionPerfect ? const Color(0xFFECFDF5) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isConditionPerfect ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                      width: _isConditionPerfect ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: _isConditionPerfect ? const Color(0xFF10B981) : Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'สมบูรณ์ 100%',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: _isConditionPerfect ? const Color(0xFF065F46) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isConditionPerfect = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: !_isConditionPerfect ? const Color(0xFFFEF2F2) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: !_isConditionPerfect ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                      width: !_isConditionPerfect ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: !_isConditionPerfect ? const Color(0xFFEF4444) : Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'มีตำหนิ/เกินเวลา',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: !_isConditionPerfect ? const Color(0xFF991B1B) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_checkDeviceWorks && _checkAccessoriesReturned && _checkNoNewDamage)
                ? () => setState(() => _currentStep = 1)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text(
              'ยืนยันการตรวจรับของคืน ➔ ขั้นตอนถัดไป',
              style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 1: เงินประกันและส่วนต่าง
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepDepositSettlement() {
    final hasDeposit = widget.depositAmount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF10B981), size: 36),
              const SizedBox(height: 8),
              Text(
                hasDeposit ? 'ยอดเงินประกันที่ต้องคืน' : 'สถานะการเคลียร์ยอดค่าเช่า',
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              Text(
                hasDeposit ? '฿${widget.depositAmount.toStringAsFixed(0)}' : 'ไม่มีเงินประกันค้างชำระ',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2022),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isConditionPerfect
                    ? 'อุปกรณ์อยู่ในสภาพสมบูรณ์ ไม่มีการหักค่าเสียหายใดๆ'
                    : 'อุปกรณ์มีตำหนิ/เกินเวลา ตรวจสอบข้อตกลงและหักตามจริง',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: _isConditionPerfect ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (hasDeposit) ...[
          if (_isOwner) ...[
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep = 2;
                  });
                },
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  'โอนคืนเงินประกัน ฿${widget.depositAmount.toStringAsFixed(0)} เรียบร้อยแล้ว',
                  style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 13.5),
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
                onPressed: () => setState(() => _currentStep = 2),
                icon: const Icon(Icons.verified_rounded, size: 18),
                label: const Text(
                  'ฉันได้รับเงินประกันคืนเรียบร้อยแล้ว',
                  style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ],
        ] else ...[
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () => setState(() => _currentStep = 2),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text(
                'ดำเนินการต่อ ➔ รหัสยืนยันการคืนของ',
                style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 2: รหัส Return PIN
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepReturnPinVerification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'รหัสยืนยันการรับคืนอุปกรณ์ (Return PIN)',
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
              ? 'บอกรหัส 4 หลักนี้แก่ผู้เช่า เพื่อยืนยันว่าได้รับของคืนครบถ้วนและจบสัญญาเช่า'
              : 'กรุณากรอกรหัส PIN 4 หลักที่ได้รับจากผู้ปล่อยเช่า เพื่อยืนยันการส่งคืนสำเร็จ',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12.5,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 18),

        if (_isOwner) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF10B981), width: 2),
              ),
              child: Text(
                _generatedReturnPin,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: Color(0xFF059669),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'รอผู้เช่ากรอกรหัสยืนยันในเครื่องเพื่อจบรายการ...',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _completeReturn,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF059669),
              side: const BorderSide(color: Color(0xFFA7F3D0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('จำลอง: ผู้เช่ากรอกรหัสตรงกัน ➔ จบการเช่า'),
          ),
        ] else ...[
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
              style: const TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 12, color: Color(0xFFEF4444)),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                _pinController.text = _generatedReturnPin;
              },
              child: Text(
                'คลิกเพื่อใส่รหัสทดสอบ ($_generatedReturnPin)',
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
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text(
                      'ยืนยันการส่งคืนอุปกรณ์',
                      style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 3: ส่งคืนสำเร็จ & ชวนรีวิว
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
          child: const Icon(Icons.task_alt_rounded, color: Color(0xFF10B981), size: 48),
        ),
        const SizedBox(height: 14),
        const Text(
          'ส่งคืนอุปกรณ์และจบการเช่าสำเร็จ!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2022),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'รายการเช่านี้เสร็จสิ้นอย่างสมบูรณ์แล้ว อุปกรณ์ถูกปลดล็อกกลับมาพร้อมใช้งาน และเงินประกันได้รับการจัดการเรียบร้อย',
          textAlign: TextAlign.center,
          style: TextStyle(
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
          child: ElevatedButton.icon(
            onPressed: _openReview,
            icon: const Icon(Icons.star_rounded, size: 20),
            label: const Text(
              'ให้คะแนนรีวิว 5 ดาว',
              style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold, fontSize: 14.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'ปิดหน้าต่างนี้',
            style: TextStyle(fontFamily: AppTextStyles.fontFamily, color: Color(0xFF64748B), fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

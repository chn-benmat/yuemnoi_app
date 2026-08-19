import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

enum WalletFilterPeriod { all, today, last7Days, thisMonth, thisYear }

enum WalletFilterAmountRange { all, under1000, from1000To5000, over5000 }

enum WalletFilterSort { newest, oldest, highestAmount, lowestAmount }

class WalletFilterOptions {
  final WalletFilterPeriod period;
  final WalletFilterAmountRange amountRange;
  final WalletFilterSort sort;

  const WalletFilterOptions({
    this.period = WalletFilterPeriod.all,
    this.amountRange = WalletFilterAmountRange.all,
    this.sort = WalletFilterSort.newest,
  });

  bool get isDefault =>
      period == WalletFilterPeriod.all &&
      amountRange == WalletFilterAmountRange.all &&
      sort == WalletFilterSort.newest;

  WalletFilterOptions copyWith({
    WalletFilterPeriod? period,
    WalletFilterAmountRange? amountRange,
    WalletFilterSort? sort,
  }) {
    return WalletFilterOptions(
      period: period ?? this.period,
      amountRange: amountRange ?? this.amountRange,
      sort: sort ?? this.sort,
    );
  }
}

class WalletFilterBottomSheet extends StatefulWidget {
  final WalletFilterOptions currentOptions;
  final ValueChanged<WalletFilterOptions> onApply;

  const WalletFilterBottomSheet({
    super.key,
    required this.currentOptions,
    required this.onApply,
  });

  static Future<void> show(
    BuildContext context, {
    required WalletFilterOptions currentOptions,
    required ValueChanged<WalletFilterOptions> onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WalletFilterBottomSheet(
        currentOptions: currentOptions,
        onApply: onApply,
      ),
    );
  }

  @override
  State<WalletFilterBottomSheet> createState() =>
      _WalletFilterBottomSheetState();
}

class _WalletFilterBottomSheetState extends State<WalletFilterBottomSheet> {
  late WalletFilterPeriod _period;
  late WalletFilterAmountRange _amountRange;
  late WalletFilterSort _sort;

  @override
  void initState() {
    super.initState();
    _period = widget.currentOptions.period;
    _amountRange = widget.currentOptions.amountRange;
    _sort = widget.currentOptions.sort;
  }

  void _reset() {
    setState(() {
      _period = WalletFilterPeriod.all;
      _amountRange = WalletFilterAmountRange.all;
      _sort = WalletFilterSort.newest;
    });
  }

  void _apply() {
    Navigator.of(context).pop();
    widget.onApply(
      WalletFilterOptions(
        period: _period,
        amountRange: _amountRange,
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 28),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag Handle ──
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'กรองประวัติการเติมเงิน',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _reset,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text(
                          'รีเซ็ต',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF6B7280),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24, color: Color(0xFFF3F4F6)),

              // ── Section 1: ช่วงเวลา ──
              _buildSectionTitle('ช่วงเวลา'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChoiceChip(
                    label: 'ทั้งหมด',
                    isSelected: _period == WalletFilterPeriod.all,
                    onSelected: () =>
                        setState(() => _period = WalletFilterPeriod.all),
                  ),
                  _buildChoiceChip(
                    label: 'วันนี้',
                    isSelected: _period == WalletFilterPeriod.today,
                    onSelected: () =>
                        setState(() => _period = WalletFilterPeriod.today),
                  ),
                  _buildChoiceChip(
                    label: '7 วันล่าสุด',
                    isSelected: _period == WalletFilterPeriod.last7Days,
                    onSelected: () =>
                        setState(() => _period = WalletFilterPeriod.last7Days),
                  ),
                  _buildChoiceChip(
                    label: 'เดือนนี้',
                    isSelected: _period == WalletFilterPeriod.thisMonth,
                    onSelected: () =>
                        setState(() => _period = WalletFilterPeriod.thisMonth),
                  ),
                  _buildChoiceChip(
                    label: 'ปีนี้',
                    isSelected: _period == WalletFilterPeriod.thisYear,
                    onSelected: () =>
                        setState(() => _period = WalletFilterPeriod.thisYear),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Section 2: ช่วงยอดเงิน ──
              _buildSectionTitle('ช่วงยอดเงิน'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChoiceChip(
                    label: 'ทุกยอดเงิน',
                    isSelected: _amountRange == WalletFilterAmountRange.all,
                    onSelected: () => setState(
                      () => _amountRange = WalletFilterAmountRange.all,
                    ),
                  ),
                  _buildChoiceChip(
                    label: 'น้อยกว่า 1,000 ฿',
                    isSelected:
                        _amountRange == WalletFilterAmountRange.under1000,
                    onSelected: () => setState(
                      () => _amountRange = WalletFilterAmountRange.under1000,
                    ),
                  ),
                  _buildChoiceChip(
                    label: '1,000 - 5,000 ฿',
                    isSelected:
                        _amountRange == WalletFilterAmountRange.from1000To5000,
                    onSelected: () => setState(
                      () =>
                          _amountRange = WalletFilterAmountRange.from1000To5000,
                    ),
                  ),
                  _buildChoiceChip(
                    label: 'มากกว่า 5,000 ฿',
                    isSelected:
                        _amountRange == WalletFilterAmountRange.over5000,
                    onSelected: () => setState(
                      () => _amountRange = WalletFilterAmountRange.over5000,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Section 3: เรียงลำดับ ──
              _buildSectionTitle('เรียงตาม'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChoiceChip(
                    label: 'ล่าสุดไปเก่าสุด',
                    isSelected: _sort == WalletFilterSort.newest,
                    onSelected: () =>
                        setState(() => _sort = WalletFilterSort.newest),
                  ),
                  _buildChoiceChip(
                    label: 'เก่าสุดไปล่าสุด',
                    isSelected: _sort == WalletFilterSort.oldest,
                    onSelected: () =>
                        setState(() => _sort = WalletFilterSort.oldest),
                  ),
                  _buildChoiceChip(
                    label: 'ยอดเงินมากสุด',
                    isSelected: _sort == WalletFilterSort.highestAmount,
                    onSelected: () =>
                        setState(() => _sort = WalletFilterSort.highestAmount),
                  ),
                  _buildChoiceChip(
                    label: 'ยอดเงินน้อยสุด',
                    isSelected: _sort == WalletFilterSort.lowestAmount,
                    onSelected: () =>
                        setState(() => _sort = WalletFilterSort.lowestAmount),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Action Button ──
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'ใช้ตัวกรอง',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Color(0xFF374151),
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3E8FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryColor
                : const Color(0xFFE5E7EB),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.primaryColor : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

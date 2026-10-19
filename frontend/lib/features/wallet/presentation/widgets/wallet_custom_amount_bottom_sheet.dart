import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class WalletCustomAmountBottomSheet extends StatefulWidget {
  final ValueChanged<double> onAmountConfirmed;

  const WalletCustomAmountBottomSheet({
    super.key,
    required this.onAmountConfirmed,
  });

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<double> onAmountConfirmed,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          WalletCustomAmountBottomSheet(onAmountConfirmed: onAmountConfirmed),
    );
  }

  @override
  State<WalletCustomAmountBottomSheet> createState() =>
      _WalletCustomAmountBottomSheetState();
}

class _WalletCustomAmountBottomSheetState
    extends State<WalletCustomAmountBottomSheet> {
  String _amountString = '';
  final List<double> _quickAddAmounts = [100, 300, 500, 1000, 2000];

  double get _currentAmount {
    return double.tryParse(_amountString) ?? 0.0;
  }

  void _onKeyPress(String key) {
    setState(() {
      if (key == '.') {
        if (_amountString.isEmpty) {
          _amountString = '0.';
        } else if (!_amountString.contains('.')) {
          _amountString += '.';
        }
      } else {
        // Digits 0-9
        if (_amountString == '0' && key != '.') {
          _amountString = key;
        } else {
          // Check decimal places limit (max 2 decimal digits)
          if (_amountString.contains('.')) {
            final parts = _amountString.split('.');
            if (parts.length > 1 && parts[1].length >= 2) {
              return; // Already 2 decimal digits
            }
          }
          // Check max limit (up to 7 integer digits)
          if (!_amountString.contains('.') && _amountString.length >= 7) {
            return;
          }
          _amountString += key;
        }
      }
    });
  }

  void _onBackspace() {
    setState(() {
      if (_amountString.isNotEmpty) {
        _amountString = _amountString.substring(0, _amountString.length - 1);
      }
    });
  }

  void _onClear() {
    setState(() {
      _amountString = '';
    });
  }

  void _addQuickAmount(double amount) {
    setState(() {
      final current = _currentAmount;
      final newAmount = current + amount;
      _amountString = newAmount == newAmount.roundToDouble()
          ? newAmount.toInt().toString()
          : newAmount.toStringAsFixed(2);
    });
  }

  void _submit() {
    final amount = _currentAmount;
    if (amount > 0) {
      Navigator.of(context).pop();
      widget.onAmountConfirmed(amount);
    }
  }

  String _formatDisplayAmount() {
    if (_amountString.isEmpty) return '0.00';

    if (_amountString.contains('.')) {
      final parts = _amountString.split('.');
      final intPart = int.tryParse(parts[0]) ?? 0;
      final intFormatted = NumberFormat('#,##0', 'en_US').format(intPart);
      final decPart = parts.length > 1 ? parts[1] : '';
      return '$intFormatted.$decPart';
    } else {
      final intVal = int.tryParse(_amountString);
      if (intVal != null) {
        return NumberFormat('#,##0', 'en_US').format(intVal);
      }
      return _amountString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isValid = _currentAmount > 0;
    final displayAmount = _formatDisplayAmount();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag Handle Bar ──
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ระบุจำนวนเงินที่ต้องการเติม',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'เติมเงินเข้ากระเป๋าเงิน Yuemnoi ขั้นต่ำ 20 บาท',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
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
            const SizedBox(height: 16),

            // ── Hero Currency Input Display ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isValid
                      ? AppColors.primaryColor
                      : const Color(0xFFE5E7EB),
                  width: 1.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '฿',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isValid
                          ? AppColors.primaryColor
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayAmount,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _amountString.isNotEmpty
                            ? const Color(0xFF111827)
                            : const Color(0xFFD1D5DB),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (_amountString.isNotEmpty)
                    GestureDetector(
                      onTap: _onClear,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE5E7EB),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Quick-Add Amount Chips ──
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickAddAmounts.map((amt) {
                  final label =
                      '+${NumberFormat('#,###', 'en_US').format(amt)}';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _addQuickAmount(amt),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF3E8FF,
                          ).withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFE9D5FF),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // ── In-App Number Keypad UI (แผงปุ่มตัวเลขบนหน้าจอ) ──
            _buildKeypad(),
            const SizedBox(height: 18),

            // ── Submit / Continue Button ──
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isValid ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  disabledBackgroundColor: AppColors.primaryColor.withValues(
                    alpha: 0.35,
                  ),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  isValid
                      ? 'ดำเนินการต่อ ($displayAmount บาท)'
                      : 'ดำเนินการต่อ',
                  style: const TextStyle(
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
    );
  }

  /// Modern Interactive Number Keypad
  Widget _buildKeypad() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 1),
      ),
      child: Column(
        children: [
          Row(children: [_buildKey('1'), _buildKey('2'), _buildKey('3')]),
          const SizedBox(height: 4),
          Row(children: [_buildKey('4'), _buildKey('5'), _buildKey('6')]),
          const SizedBox(height: 4),
          Row(children: [_buildKey('7'), _buildKey('8'), _buildKey('9')]),
          const SizedBox(height: 4),
          Row(children: [_buildKey('.'), _buildKey('0'), _buildBackspaceKey()]),
        ],
      ),
    );
  }

  Widget _buildKey(String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onKeyPress(value),
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Text(
                value,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _onBackspace,
            borderRadius: BorderRadius.circular(14),
            child: const Center(
              child: Icon(
                Icons.backspace_outlined,
                size: 22,
                color: Color(0xFF374151),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

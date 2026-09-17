import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class RenterQrScannerSheet extends StatefulWidget {
  final ValueChanged<String> onCodeScanned;

  const RenterQrScannerSheet({
    super.key,
    required this.onCodeScanned,
  });

  static Future<void> show({
    required BuildContext context,
    required ValueChanged<String> onCodeScanned,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RenterQrScannerSheet(
        onCodeScanned: (code) {
          Navigator.pop(ctx);
          onCodeScanned(code);
        },
      ),
    );
  }

  @override
  State<RenterQrScannerSheet> createState() => _RenterQrScannerSheetState();
}

class _RenterQrScannerSheetState extends State<RenterQrScannerSheet> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _otpController = TextEditingController();
  bool _isManualInput = false;
  bool _hasDetected = false;

  @override
  void dispose() {
    _scannerController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _handleDetected(BarcodeCapture capture) {
    if (_hasDetected) return;
    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        _hasDetected = true;
        widget.onCodeScanned(code);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // แถบด้านบน
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryColor, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'สแกน QR Code ร้านค้า',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E2022),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isManualInput = !_isManualInput;
                    });
                  },
                  child: Text(
                    _isManualInput ? 'เปิดกล้องสแกน' : 'กรอกรหัส 6 หลัก',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // เนื้อหา: กล้องสแกน หรือ ช่องกรอก OTP
          Expanded(
            child: _isManualInput
                ? _buildManualInputView()
                : _buildCameraScannerView(),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraScannerView() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // วิวกล้อง MobileScanner
        ClipRRect(
          child: MobileScanner(
            controller: _scannerController,
            onDetect: _handleDetected,
          ),
        ),

        // กรอบ Viewfinder
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primaryColor, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),

        // คำแนะนำด้านล่าง
        Positioned(
          bottom: 30,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.crop_free_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'จัดตำแหน่ง QR Code ให้อยู่ในกรอบ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ปุ่มเปิด-ปิดไฟฉาย
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
            ),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ),
      ],
    );
  }

  Widget _buildManualInputView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.pin_outlined,
              size: 40,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'กรอกรหัสยืนยัน 6 หลักจากร้านค้า',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E2022),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'กรณีกล้องสแกนไม่ได้ หรืออยู่ในที่มืด สามารถนำเลข 6 หลักใต้ QR ของร้านค้ามากรอกได้เลย',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8.0,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                final otp = _otpController.text.trim();
                if (otp.length == 6) {
                  widget.onCodeScanned(otp);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'ยืนยันการคืน',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/colors.dart';

// คำอธิบาย: วิดเจ็ตสำหรับแสดงช่องรับรหัส OTP จำนวน 6 หลัก พร้อมระบบย้ายโฟกัสไปยังช่องถัดไปโดยอัตโนมัติ
class OtpInputFields extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;

  const OtpInputFields({
    super.key,
    required this.controllers,
    required this.focusNodes,
  }) : assert(controllers.length == 6 && focusNodes.length == 6);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth < 320 ? 4.0 : 8.0;
        final itemWidth =
            ((constraints.maxWidth - (spacing * 5)) / 6).clamp(28.0, 56.0);
        final itemHeight = itemWidth.clamp(48.0, 64.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < 6; index++) ...[
              if (index > 0) SizedBox(width: spacing),
              SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgFieldColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: controllers[index],
                    focusNode: focusNodes[index],
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        if (index < 5) {
                          focusNodes[index + 1].requestFocus();
                        } else {
                          focusNodes[index].unfocus();
                        }
                      } else {
                        if (index > 0) {
                          focusNodes[index - 1].requestFocus();
                        }
                      }
                    },
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    maxLength: 1,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                      border: InputBorder.none,
                      hintText: '-',
                      hintStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.hintTextColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class BookingSecurityBadge extends StatelessWidget {
  const BookingSecurityBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.shield_outlined,
            color: AppColors.primaryColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'การชำระเงินของคุณได้รับการคุ้มครองโดยนโยบายการรับประกันการเช่าของเรา จนกว่าคุณจะตรวจสอบคุณภาพอุปกรณ์เมื่อรับสินค้า',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF757778),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

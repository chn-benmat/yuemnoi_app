import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import '../../../../core/constants/colors.dart';

class OtpInputFields extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;

  const OtpInputFields({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = constraints.maxWidth < 320 ? 4.0 : 8.0;
        final itemWidth = ((constraints.maxWidth - (spacing * 5)) / 6).clamp(
          20.0,
          56.0,
        );
        final itemHeight = itemWidth.clamp(48.0, 64.0);

        return Pinput(
          length: 6,
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          separatorBuilder: (_) => SizedBox(width: spacing),
          defaultPinTheme: PinTheme(
            width: itemWidth,
            height: itemHeight,
            textStyle: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            decoration: BoxDecoration(
              color: AppColors.bgFieldColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          preFilledWidget: Text(
            '-',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.hintTextColor,
            ),
          ),
        );
      },
    );
  }
}

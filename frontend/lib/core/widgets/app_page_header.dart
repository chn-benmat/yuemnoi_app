import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// หัวหน้าแบบมีชื่อหน้าของแท็บหลัก ใช้ร่วมกันให้ขนาดและตำแหน่งชื่อตรงกันทุกหน้า
class AppPageTitleHeader extends StatelessWidget {
  const AppPageTitleHeader({
    super.key,
    required this.title,
    this.trailing,
    this.bottom,
  });

  final String title;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => AppPageHeader(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // สูงและใช้ตัวอักษรเท่า AppBar มาตรฐาน (เช่นหน้าตั้งค่าบัญชี) ให้หัวทุกหน้าขนาดเท่ากัน
        SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        if (bottom != null)
          Padding(padding: const EdgeInsets.only(bottom: 14), child: bottom),
      ],
    ),
  );
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.bottomSafeArea = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool bottomSafeArea;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: AppTheme.pageHeaderOverlayStyle,
    child: ColoredBox(
      color: AppColors.primaryColor,
      child: SafeArea(
        bottom: bottomSafeArea,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

/// วิดเจ็ตช่องค้นหาอุปกรณ์ในหน้า Home Feed
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onClear,
    this.onFilterTap,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final VoidCallback? onFilterTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        key: const ValueKey('home-search-field'),
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF2D3133),
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'ค้นหาอุปกรณ์ที่ต้องการเช่า...',
          hintStyle: const TextStyle(
            color: Color(0xFF9EA2A7),
            fontSize: 14,
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(
              Icons.search_rounded,
              color: Color(0xFF757778),
              size: 22,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isNotEmpty) {
                return IconButton(
                  tooltip: 'ล้างข้อความ',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                    onClear?.call();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF8C9093),
                    size: 20,
                  ),
                );
              }
              if (onFilterTap != null) {
                return IconButton(
                  tooltip: 'ตัวกรองเพิ่มเติม',
                  onPressed: onFilterTap,
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: AppColors.primaryColor,
                    size: 20,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Color(0xFFF0F1F3), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Color(0xFFECEEF1), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(
              color: AppColors.primaryColor,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

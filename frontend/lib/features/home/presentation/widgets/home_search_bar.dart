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
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final VoidCallback? onFilterTap;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        key: const ValueKey('home-search-field'),
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 14.5,
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'ค้นหาอุปกรณ์ที่ต้องการเช่า...',
          hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13.5,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.search_rounded,
              color: Color(0xFF64748B),
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 42,
            minHeight: 48,
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
                    size: 18,
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
                    size: 18,
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
            vertical: 13,
            horizontal: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primaryColor,
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

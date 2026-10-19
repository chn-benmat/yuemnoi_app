import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_form_field_styles.dart';

class RentalCategoryPicker extends StatefulWidget {
  const RentalCategoryPicker({super.key, required this.options, this.selected});

  final List<String> options;
  final String? selected;

  @override
  State<RentalCategoryPicker> createState() => _RentalCategoryPickerState();
}

class _RentalCategoryPickerState extends State<RentalCategoryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where(
          (option) =>
              option.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'เลือกหมวดหมู่',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'ปิดหมวดหมู่',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                key: const Key('rental-category-search'),
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration:
                    AppFormFieldStyles.decoration(
                      context,
                      variant: AppFormFieldVariant.outlined,
                    ).copyWith(
                      hintText: 'ค้นหาหมวดหมู่',
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: options.isEmpty
                  ? const Center(child: Text('ไม่พบหมวดหมู่ ลองใช้คำค้นอื่น'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final selected = option == widget.selected;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 4,
                          ),
                          title: Text(
                            option,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? AppColors.primaryColor : null,
                              fontWeight: selected ? FontWeight.w600 : null,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.primaryColor,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

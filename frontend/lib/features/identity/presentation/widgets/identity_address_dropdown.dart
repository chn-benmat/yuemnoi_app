import 'package:flutter/material.dart';

import '../../../../core/theme/app_form_field_styles.dart';
import '../../../../core/widgets/app_text_form_field.dart';

class IdentityAddressDropdown<T> extends StatelessWidget {
  const IdentityAddressDropdown({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.hintText,
    required this.controller,
    required this.options,
    required this.optionLabel,
    required this.onSelected,
    required this.validator,
    this.selected,
    this.enabled = true,
  });

  final Key fieldKey;
  final String label, hintText;
  final TextEditingController controller;
  final List<T> options;
  final String Function(T) optionLabel;
  final ValueChanged<T> onSelected;
  final FormFieldValidator<String> validator;
  final T? selected;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final chosen = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: _AddressOptions<T>(
            title: label,
            options: options,
            optionLabel: optionLabel,
            selected: selected,
          ),
        ),
      ),
    );
    if (context.mounted && chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) => AppTextFormField(
    variant: AppFormFieldVariant.outlined,
    fieldKey: fieldKey,
    label: label,
    hintText: hintText,
    controller: controller,
    readOnly: true,
    enableInteractiveSelection: false,
    enabled: enabled && options.isNotEmpty,
    validator: validator,
    suffixIcon: const Icon(Icons.expand_more_rounded),
    onTap: () => _open(context),
  );
}

class _AddressOptions<T> extends StatefulWidget {
  const _AddressOptions({
    required this.title,
    required this.options,
    required this.optionLabel,
    required this.selected,
  });

  final String title;
  final List<T> options;
  final String Function(T) optionLabel;
  final T? selected;

  @override
  State<_AddressOptions<T>> createState() => _AddressOptionsState<T>();
}

class _AddressOptionsState<T> extends State<_AddressOptions<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where((option) => widget.optionLabel(option).contains(_query.trim()))
        .toList(growable: false);
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'เลือก${widget.title}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'ปิดรายการ',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              key: const ValueKey('address_search'),
              decoration:
                  AppFormFieldStyles.decoration(
                    context,
                    variant: AppFormFieldVariant.outlined,
                  ).copyWith(
                    hintText: 'ค้นหา${widget.title}',
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: options.isEmpty
                ? const Center(child: Text('ไม่พบข้อมูลที่ค้นหา'))
                : ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final label = widget.optionLabel(option);
                      final selected = option == widget.selected;
                      return ListTile(
                        key: ValueKey('address_option:$label'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        title: Text(label),
                        selected: selected,
                        trailing: selected
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, option),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

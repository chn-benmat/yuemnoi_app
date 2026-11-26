import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PromptPayIdentifierFields extends StatelessWidget {
  const PromptPayIdentifierFields({
    super.key,
    required this.controller,
    required this.nationalId,
    required this.enabled,
    required this.onTypeChanged,
    required this.onSubmitted,
    this.helperText,
  });

  final TextEditingController controller;
  final bool nationalId;
  final bool enabled;
  final ValueChanged<bool> onTypeChanged;
  final VoidCallback onSubmitted;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('เบอร์มือถือ', textAlign: TextAlign.center),
            ),
            ButtonSegment(
              value: true,
              label: Text('เลขบัตรประชาชน', textAlign: TextAlign.center),
            ),
          ],
          selected: {nationalId},
          showSelectedIcon: false,
          onSelectionChanged: enabled
              ? (selection) {
                  if (selection.single != nationalId)
                    onTypeChanged(selection.single);
                }
              : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey(nationalId),
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(nationalId ? 13 : 10),
          ],
          decoration: InputDecoration(
            labelText: nationalId
                ? 'เลขบัตรประชาชนที่ผูกพร้อมเพย์'
                : 'เบอร์มือถือที่ผูกพร้อมเพย์',
            hintText: nationalId ? null : '08XXXXXXXX',
            helperText: helperText,
            errorMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (nationalId) {
              return value?.length == 13
                  ? null
                  : 'กรุณากรอกเลขบัตรประชาชน 13 หลัก';
            }
            return RegExp(r'^0[689][0-9]{8}$').hasMatch(value ?? '')
                ? null
                : 'กรุณากรอกเบอร์มือถือพร้อมเพย์ 10 หลัก';
          },
          onFieldSubmitted: (_) => onSubmitted(),
        ),
        if (nationalId)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('QR จะมีเลขบัตรประชาชนสำหรับการสแกนโอน'),
          ),
      ],
    );
  }
}

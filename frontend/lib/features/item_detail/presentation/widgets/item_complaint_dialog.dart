import 'package:flutter/material.dart';

import '../../../../core/widgets/app_popup.dart';
import '../../data/datasources/item_complaint_remote_data_source.dart';

class ItemComplaintDialog extends StatefulWidget {
  const ItemComplaintDialog({
    super.key,
    required this.itemId,
    required this.reason,
    required this.dataSource,
  });

  final int itemId;
  final String reason;
  final ItemComplaintRemoteDataSource dataSource;

  @override
  State<ItemComplaintDialog> createState() => _ItemComplaintDialogState();
}

class _ItemComplaintDialogState extends State<ItemComplaintDialog> {
  final _form = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  // เก็บเหตุผลในรายละเอียดเพื่อให้เจ้าหน้าที่อ่านได้ผ่านระบบร้องเรียนเดิม
  String get _descriptionPrefix => 'เหตุผล: ${widget.reason}\n';
  int get _maxDetailsLength => 2000 - _descriptionPrefix.runes.length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    final description = '$_descriptionPrefix${_controller.text.trim()}';
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await widget.dataSource.submit(
        itemId: widget.itemId,
        description: description,
      );
    } on ItemComplaintException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = userFriendlyErrorMessage(error.message);
        _submitting = false;
      });
      return;
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        scrollable: true,
        title: const Text('รายละเอียดปัญหา'),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.reason),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                readOnly: _submitting,
                maxLength: _maxDetailsLength,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText:
                      'อธิบายปัญหาอย่างน้อย 5 ตัวอักษร โดยเว้นข้อมูลส่วนตัว',
                  errorMaxLines: 2,
                ),
                validator: (value) {
                  final length = (value ?? '').trim().runes.length;
                  if (length < 5) {
                    return 'กรุณาระบุรายละเอียดอย่างน้อย 5 ตัวอักษร';
                  }
                  if (length > _maxDetailsLength) {
                    return 'กรุณาระบุรายละเอียดไม่เกิน $_maxDetailsLength ตัวอักษร';
                  }
                  return null;
                },
              ),
              if (_submitError case final error?)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'กำลังส่งรายงาน…' : 'ส่งรายงาน'),
          ),
        ],
      ),
    );
  }
}

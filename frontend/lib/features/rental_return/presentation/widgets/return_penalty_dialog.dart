import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../domain/entities/rental_return_session.dart';

class ReturnPenaltyDialog extends StatefulWidget {
  const ReturnPenaltyDialog({
    super.key,
    required this.session,
    required this.onSave,
    required this.onLoadQr,
  });

  final RentalReturnSession session;
  final Future<RentalReturnPenaltyReport> Function({
    required bool damaged,
    required bool late,
    required String details,
  })
  onSave;
  final Future<String> Function() onLoadQr;

  @override
  State<ReturnPenaltyDialog> createState() => _ReturnPenaltyDialogState();
}

class _ReturnPenaltyDialogState extends State<ReturnPenaltyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _details = TextEditingController();
  late RentalReturnPenaltyReport? _report = widget.session.penaltyReport;
  bool _damaged = true;
  bool _late = false;
  bool _busy = false;
  bool _needsPromptPay = false;
  String? _error;
  String? _qr;

  bool get _canReportLate =>
      widget.session.isOverdue && widget.session.penaltyTerms.lateReturnFee > 0;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _needsPromptPay = false;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is RentalReturnPenaltyException) {
          _error = error.message;
          _needsPromptPay = error.needsPromptPay;
        } else {
          _error = error is StateError
              ? error.message
              : 'ดำเนินการไม่สำเร็จ กรุณาลองอีกครั้ง';
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _run(() async {
      final report = await widget.onSave(
        damaged: _damaged,
        late: _late,
        details: _details.text.trim(),
      );
      if (mounted) setState(() => _report = report);
    });
  }

  void _loadQr() => _run(() async {
    final qr = await widget.onLoadQr();
    if (mounted) setState(() => _qr = qr);
  });

  @override
  Widget build(BuildContext context) {
    final terms = widget.session.penaltyTerms;
    final format = NumberFormat.decimalPattern('th');
    final pendingAmount =
        (_damaged ? terms.damageFee : 0) + (_late ? terms.lateReturnFee : 0);
    final report = _report;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          _qr == null ? 'บันทึกปัญหาการคืนสินค้า' : 'ชำระค่าปรับผ่านพร้อมเพย์',
        ),
        content: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                widget.session.itemName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (report == null) ...[
                if (_canReportLate) ...[
                  CheckboxListTile(
                    value: _damaged,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _damaged = value!),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('สินค้าชำรุด'),
                  ),
                  CheckboxListTile(
                    value: _late,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _late = value!),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('คืนเกินกำหนด'),
                  ),
                ],
                if (_damaged && terms.damageTerms.isNotEmpty)
                  Text(terms.damageTerms),
                TextFormField(
                  controller: _details,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: _damaged
                        ? 'รายละเอียดความเสียหาย'
                        : 'รายละเอียดเพิ่มเติม',
                    hintText: _damaged
                        ? 'ระบุส่วนที่ชำรุดและลักษณะความเสียหาย'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => _damaged && (value ?? '').trim().isEmpty
                      ? 'กรุณาระบุว่าสินค้าชำรุดตรงไหน'
                      : null,
                ),
                Text('ค่าปรับตามเงื่อนไข ${format.format(pendingAmount)} บาท'),
              ] else
                ReturnPenaltyReportSummary(report: report),
              if (_qr case final qr?) ...[
                Center(
                  child: SizedBox.square(
                    dimension: 210,
                    child: QrImageView(
                      data: qr,
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.white,
                      semanticsLabel: 'QR พร้อมเพย์สำหรับชำระค่าปรับ',
                    ),
                  ),
                ),
                const Text('ให้ผู้เช่าสแกน QR ด้วยแอปธนาคาร'),
              ],
              if (_error case final error?)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_needsPromptPay)
                TextButton(
                  onPressed: () => AppRoutes.openPromptPayAccount(context),
                  child: const Text('ตั้งค่าพร้อมเพย์'),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
          if (report == null)
            FilledButton(
              onPressed: _busy || (!_damaged && !_late) ? null : _save,
              child: const Text('บันทึกรายงาน'),
            )
          else if (report.amountSatang > 0 && _qr == null)
            FilledButton(
              onPressed: _busy ? null : _loadQr,
              child: const Text('เรียกเก็บค่าปรับ'),
            ),
        ],
      ),
    );
  }
}

class ReturnPenaltyReportSummary extends StatelessWidget {
  const ReturnPenaltyReportSummary({super.key, required this.report});

  final RentalReturnPenaltyReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(
        [
          if (report.damaged) 'สินค้าชำรุด',
          if (report.late) 'คืนเกินกำหนด',
        ].join(' และ '),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (report.details.isNotEmpty) Text(report.details),
      Text('ค่าปรับ ${report.formattedAmount} บาท'),
    ],
  );
}

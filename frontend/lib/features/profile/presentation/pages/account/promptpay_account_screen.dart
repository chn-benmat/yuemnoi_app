import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../bloc/promptpay_account_cubit.dart';
import '../../widgets/promptpay_identifier_fields.dart';

class PromptPayAccountScreen extends StatefulWidget {
  const PromptPayAccountScreen({super.key});

  @override
  State<PromptPayAccountScreen> createState() => _PromptPayAccountScreenState();
}

class _PromptPayAccountScreenState extends State<PromptPayAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  bool _nationalId = false;

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    context.read<PromptPayAccountCubit>().save(
      _identifier.text,
      nationalId: _nationalId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: BackButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(AppRoutes.settingAccount);
            }
          },
        ),
        title: const Text('แก้ไขพร้อมเพย์'),
      ),
      body: SafeArea(
        child: BlocConsumer<PromptPayAccountCubit, PromptPayAccountState>(
          listenWhen: (previous, current) =>
              previous.account != current.account,
          listener: (context, state) {
            _nationalId = state.account?.usesNationalId ?? false;
            _identifier.text = state.account?.phone ?? '';
            if (state.saved) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('บันทึกพร้อมเพย์แล้ว')),
                );
            }
          },
          builder: (context, state) {
            final account = state.account;
            if (account == null && state.error == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final lastFour = account?.nationalIdLastFour;
            final error = state.error;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (account != null) ...[
                          const Text(
                            'พร้อมเพย์สำหรับรับค่าเช่าเมื่อส่งมอบอุปกรณ์',
                          ),
                          if (lastFour != null)
                            Text(
                              'เลขบัตรประชาชนที่บันทึกไว้ลงท้ายด้วย $lastFour',
                            )
                          else if (account.usesNationalId)
                            const Text(
                              'กรอกเลขบัตรใหม่หรือเลือกเบอร์มือถือเพื่ออัปเดตพร้อมเพย์',
                            ),
                          const SizedBox(height: 16),
                          PromptPayIdentifierFields(
                            controller: _identifier,
                            nationalId: _nationalId,
                            enabled: !state.busy,
                            onTypeChanged: (nationalId) {
                              setState(() {
                                _identifier.clear();
                                _nationalId = nationalId;
                              });
                              context
                                  .read<PromptPayAccountCubit>()
                                  .clearSaveError();
                            },
                            onSubmitted: _save,
                          ),
                        ],
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (account == null)
                          OutlinedButton(
                            onPressed: context
                                .read<PromptPayAccountCubit>()
                                .load,
                            child: const Text('ลองอีกครั้ง'),
                          )
                        else
                          FilledButton(
                            onPressed: state.busy ? null : _save,
                            child: Text(
                              state.busy ? 'กำลังบันทึก...' : 'บันทึกพร้อมเพย์',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

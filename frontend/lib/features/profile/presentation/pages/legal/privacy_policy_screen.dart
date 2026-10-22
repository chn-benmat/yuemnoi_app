import 'package:flutter/material.dart';
import '../../widgets/legal/legal_document_page.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      title: 'นโยบายความเป็นส่วนตัว',
      description: 'ข้อมูลเกี่ยวกับความเป็นส่วนตัวของคุณบน Yuemnoi',
    );
  }
}

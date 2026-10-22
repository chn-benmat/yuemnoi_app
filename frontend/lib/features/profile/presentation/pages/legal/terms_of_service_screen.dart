import 'package:flutter/material.dart';
import '../../widgets/legal/legal_document_page.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      title: 'เงื่อนไขการให้บริการ',
      description: 'ข้อตกลงสำหรับการใช้บริการ Yuemnoi',
    );
  }
}

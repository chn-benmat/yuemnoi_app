import 'package:flutter/material.dart';
import '../account/account_page_intro.dart';

class LegalDocumentSection {
  const LegalDocumentSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.description,
    this.sections = const [],
  });

  final String title;
  final String description;
  final List<LegalDocumentSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9FD),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF9FD),
        foregroundColor: const Color(0xFF292235),
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountPageIntro(title: title, description: description),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE5DFEC)),
                ),
                child: sections.isEmpty
                    ? const _UnpublishedDocument()
                    : SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (index, section)
                                in sections.indexed) ...[
                              if (index > 0) ...[
                                const SizedBox(height: 16),
                                const Divider(color: Color(0xFFE5DFEC)),
                                const SizedBox(height: 16),
                              ],
                              Semantics(
                                header: true,
                                child: Text(
                                  section.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF292235),
                                  ),
                                ),
                              ),
                              for (final paragraph in section.paragraphs)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    paragraph,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.7,
                                      color: Color(0xFF51495E),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnpublishedDocument extends StatelessWidget {
  const _UnpublishedDocument();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'เนื้อหาอยู่ระหว่างจัดทำ',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF292235),
          ),
        ),
        SizedBox(height: 12),
        Text(
          'ยังไม่มีเอกสารฉบับสมบูรณ์เผยแพร่ในหน้านี้',
          style: TextStyle(fontSize: 16, height: 1.7, color: Color(0xFF665D73)),
        ),
        SizedBox(height: 20),
        Divider(color: Color(0xFFE5DFEC)),
        SizedBox(height: 12),
        Text(
          'สถานะเอกสาร',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF292235),
          ),
        ),
        SizedBox(height: 6),
        Text(
          'ยังไม่ประกาศใช้ • ยังไม่มีวันที่มีผลบังคับใช้',
          style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF665D73)),
        ),
      ],
    );
  }
}

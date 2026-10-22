import 'package:flutter/material.dart';

class ReviewContent extends StatelessWidget {
  const ReviewContent({super.key, required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final text = description.trim();
    // แยกเฉพาะบรรทัดแท็กที่แบบฟอร์มรีวิวบันทึกไว้ โดยไม่แก้ข้อความต้นฉบับ
    final match = RegExp(r'(^|\n)จุดที่ประทับใจ: *([^\n]+)$').firstMatch(text);
    final comment = match == null
        ? text
        : text.substring(0, match.start).trim();
    final highlights =
        match
            ?.group(2)
            ?.split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList() ??
        const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (comment.isNotEmpty)
          Text(
            comment,
            style: const TextStyle(
              color: Color(0xFF241B32),
              fontSize: 15,
              height: 1.65,
            ),
          ),
        if (highlights.isNotEmpty) ...[
          if (comment.isNotEmpty) const SizedBox(height: 16),
          const Text(
            'จุดที่ประทับใจ',
            style: TextStyle(
              color: Color(0xFF746B80),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final highlight in highlights)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F3FC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    highlight,
                    style: const TextStyle(
                      color: Color(0xFF49365F),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

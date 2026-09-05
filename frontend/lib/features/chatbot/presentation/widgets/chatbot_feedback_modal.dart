import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

class ChatbotFeedbackResult {
  const ChatbotFeedbackResult({
    required this.reasonCategory,
    this.comment,
  });

  final String reasonCategory;
  final String? comment;
}

class ChatbotFeedbackModal extends StatefulWidget {
  const ChatbotFeedbackModal({
    this.initialCategory,
    this.initialComment,
    super.key,
  });

  final String? initialCategory;
  final String? initialComment;

  static Future<ChatbotFeedbackResult?> show(
    BuildContext context, {
    String? initialCategory,
    String? initialComment,
  }) {
    return showModalBottomSheet<ChatbotFeedbackResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatbotFeedbackModal(
        initialCategory: initialCategory,
        initialComment: initialComment,
      ),
    );
  }

  @override
  State<ChatbotFeedbackModal> createState() => _ChatbotFeedbackModalState();
}

class _ChatbotFeedbackModalState extends State<ChatbotFeedbackModal> {
  late final TextEditingController _commentController;
  String? _selectedReason;

  static const List<String> _reasons = [
    'ข้อมูลไม่ถูกต้อง',
    'แนะนำอุปกรณ์ไม่ตรง',
    'เข้าใจคำถามผิด',
    'ตอบกว้างเกินไป',
    'มโนอุปกรณ์ที่ไม่มี',
    'อื่นๆ',
  ];

  @override
  void initState() {
    super.initState();
    _selectedReason = widget.initialCategory ?? 'ข้อมูลไม่ถูกต้อง';
    _commentController = TextEditingController(text: widget.initialComment ?? '');
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    final comment = _commentController.text.trim();
    Navigator.of(context).pop(
      ChatbotFeedbackResult(
        reasonCategory: _selectedReason ?? 'อื่นๆ',
        comment: comment.isNotEmpty ? comment : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Color(0x20000000),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E2E5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.thumb_down_rounded,
                        size: 20,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ช่วยเราปรับปรุงคำตอบให้ดียิ่งขึ้น',
                            style: TextStyle(
                              fontFamily: 'Prompt',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E1B2E),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'โปรดเลือกสิ่งที่ควรปรับปรุงสำหรับคำตอบนี้',
                            style: TextStyle(
                              fontFamily: 'Prompt',
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF8E8E93)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _reasons.map((reason) {
                    final isSelected = _selectedReason == reason;
                    return ChoiceChip(
                      label: Text(
                        reason,
                        style: TextStyle(
                          fontFamily: 'Prompt',
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppColors.primaryColor : const Color(0xFF4A4A4A),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFFF3E8FF),
                      backgroundColor: const Color(0xFFF5F5F7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: isSelected ? AppColors.primaryColor : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedReason = selected ? reason : null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  style: const TextStyle(
                    fontFamily: 'Prompt',
                    fontSize: 14,
                    color: Color(0xFF1E1B2E),
                  ),
                  decoration: InputDecoration(
                    hintText: 'ระบุรายละเอียดเพิ่มเติมเพื่อช่วย AI เรียนรู้ (ถ้ามี)...',
                    hintStyle: const TextStyle(
                      fontFamily: 'Prompt',
                      fontSize: 13,
                      color: Color(0xFFA0A0A0),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8F8FA),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE8E8EC)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE8E8EC)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'ยกเลิก',
                          style: TextStyle(
                            fontFamily: 'Prompt',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF757575),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'ส่งข้อเสนอแนะ',
                          style: TextStyle(
                            fontFamily: 'Prompt',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';

class InteractiveQuestionnaireCard extends StatefulWidget {
  const InteractiveQuestionnaireCard({
    required this.questions,
    required this.onCompleted,
    required this.onDismiss,
    required this.onCustomInput,
    super.key,
  });

  final List<ClarificationQuestion> questions;
  final ValueChanged<String> onCompleted;
  final VoidCallback onDismiss;
  final VoidCallback onCustomInput;

  @override
  State<InteractiveQuestionnaireCard> createState() =>
      _InteractiveQuestionnaireCardState();
}

class _InteractiveQuestionnaireCardState
    extends State<InteractiveQuestionnaireCard> {
  int _currentIndex = 0;
  final Map<int, String> _selectedAnswers = {};
  String? _tapFeedbackOption;

  @override
  void initState() {
    super.initState();
    final firstUnanswered =
        widget.questions.indexWhere((q) => q.selectedOption == null);
    if (firstUnanswered != -1) {
      _currentIndex = firstUnanswered;
    }
  }

  void _selectOption(String optionText) {
    if (_tapFeedbackOption != null) return; // Prevent double taps during transition
    setState(() {
      _tapFeedbackOption = optionText;
      _selectedAnswers[_currentIndex] = optionText;
    });

    if (_currentIndex < widget.questions.length - 1) {
      // Instant local progression to next question after tap feedback
      Future.delayed(const Duration(milliseconds: 160), () {
        if (!mounted) return;
        setState(() {
          _currentIndex++;
          _tapFeedbackOption = null;
        });
      });
    } else {
      // All questions completed, compile combined answer and submit
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        final answers = <String>[];
        for (var i = 0; i < widget.questions.length; i++) {
          final ans = _selectedAnswers[i] ?? widget.questions[i].selectedOption;
          if (ans != null && ans.isNotEmpty) {
            answers.add(ans);
          }
        }
        final summary = answers.isNotEmpty ? answers.join(', ') : optionText;
        widget.onCompleted(summary);
      });
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _tapFeedbackOption = null;
      });
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.questions.length - 1 &&
        _selectedAnswers.containsKey(_currentIndex)) {
      setState(() {
        _currentIndex++;
        _tapFeedbackOption = null;
      });
    }
  }

  void _skip() {
    widget.onCompleted('ข้ามแบบสอบถาม');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();

    // If all questions are already answered, show recap card for the last one
    if (widget.questions.every((q) => q.selectedOption != null)) {
      return QuestionnaireRecapCard(question: widget.questions.last);
    }

    final safeIndex = _currentIndex.clamp(0, widget.questions.length - 1);
    final currentQuestion = widget.questions[safeIndex];
    final totalSteps = widget.questions.length > 1
        ? widget.questions.length
        : currentQuestion.totalSteps;
    final currentStep = widget.questions.length > 1
        ? safeIndex + 1
        : currentQuestion.step;
    final stepText = '$currentStep of $totalSteps';
    final canGoBack = safeIndex > 0;
    final canGoForward = safeIndex < widget.questions.length - 1 &&
        _selectedAnswers.containsKey(safeIndex);

    final selectedForCurrent = _tapFeedbackOption ??
        _selectedAnswers[safeIndex] ??
        currentQuestion.selectedOption;

    return Container(
      key: const Key('chatbot-questionnaire-card'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEDE9FE), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x187400C9),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Step Badge + Title + Close Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Claude-like Step Badge: < 1 of 2 > with clickable chevron navigation
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFDDD6FE),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      key: const Key('chatbot-questionnaire-prev'),
                      onTap: canGoBack ? _goToPrevious : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 15,
                          color: canGoBack
                              ? AppColors.primaryColor
                              : const Color(0xFFC4B5FD).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        stepText,
                        style: const TextStyle(
                          fontFamily: 'Prompt',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                    InkWell(
                      key: const Key('chatbot-questionnaire-next'),
                      onTap: canGoForward ? _goToNext : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: canGoForward
                              ? AppColors.primaryColor
                              : const Color(0xFFC4B5FD).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  currentQuestion.title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E1B2E),
                    fontFamily: 'Prompt',
                  ),
                ),
              ),
              IconButton(
                key: const Key('chatbot-questionnaire-close'),
                tooltip: 'ปิด',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFF8E8E93),
                ),
                onPressed: widget.onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dynamic Option Items with Number Chips
          for (var i = 0; i < currentQuestion.options.length; i++) ...[
            _OptionTile(
              index: i,
              optionText: currentQuestion.options[i],
              isSelected: selectedForCurrent == currentQuestion.options[i],
              onTap: () => _selectOption(currentQuestion.options[i]),
            ),
          ],

          const SizedBox(height: 6),

          // Footer: Something else / ตอบเอง & Skip
          Row(
            children: [
              TextButton.icon(
                key: const Key('chatbot-questionnaire-custom'),
                onPressed: widget.onCustomInput,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 15,
                  color: AppColors.primaryColor,
                ),
                label: const Text(
                  'ตอบเอง',
                  style: TextStyle(
                    fontFamily: 'Prompt',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryColor,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Spacer(),
              TextButton(
                key: const Key('chatbot-questionnaire-skip'),
                onPressed: _skip,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    fontFamily: 'Prompt',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF757575),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.index,
    required this.optionText,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final String optionText;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('chatbot-questionnaire-option-$optionText'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFF3E8FF)
                  : const Color(0xFFF9F8FD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppColors.primaryColor
                    : const Color(0xFFEDE9FE),
                width: isSelected ? 1.4 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryColor
                        : const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.primaryColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    optionText,
                    style: TextStyle(
                      fontFamily: 'Prompt',
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: const Color(0xFF2A2A2E),
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primaryColor,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sleek recap card shown in chat history once user answers a clarification question.
class QuestionnaireRecapCard extends StatelessWidget {
  const QuestionnaireRecapCard({
    required this.question,
    super.key,
  });

  final ClarificationQuestion question;

  @override
  Widget build(BuildContext context) {
    final selected = question.selectedOption ?? '';
    final stepText = '${question.step} of ${question.totalSteps}';

    return Container(
      key: Key('chatbot-questionnaire-recap-${question.id}'),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE9FE), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stepText,
                  style: const TextStyle(
                    fontFamily: 'Prompt',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question.title,
                  style: const TextStyle(
                    fontFamily: 'Prompt',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected,
                    style: const TextStyle(
                      fontFamily: 'Prompt',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E1B2E),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


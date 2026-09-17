import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';

class InteractiveQuestionnaireCard extends StatefulWidget {
  const InteractiveQuestionnaireCard({
    required this.questions,
    required this.onCompleted,
    this.onCompletedWithAnswers,
    required this.onDismiss,
    required this.onCustomInput,
    super.key,
  });

  final List<ClarificationQuestion> questions;
  final ValueChanged<String> onCompleted;
  final void Function(String, Map<String, String>)? onCompletedWithAnswers;
  final VoidCallback onDismiss;
  final VoidCallback onCustomInput;

  @override
  State<InteractiveQuestionnaireCard> createState() =>
      _InteractiveQuestionnaireCardState();
}

class _InteractiveQuestionnaireCardState
    extends State<InteractiveQuestionnaireCard> {
  late List<ClarificationQuestion> _questions;
  int _currentIndex = 0;
  final Map<int, String> _selectedAnswers = {};
  String? _tapFeedbackOption;

  @override
  void initState() {
    super.initState();
    _initQuestions();
  }

  @override
  void didUpdateWidget(covariant InteractiveQuestionnaireCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questions != widget.questions) {
      _initQuestions();
    }
  }

  void _initQuestions() {
    _questions = List<ClarificationQuestion>.from(widget.questions);
    final firstUnanswered = _questions.indexWhere(
      (q) => q.selectedOption == null,
    );
    _currentIndex = firstUnanswered != -1 ? firstUnanswered : 0;
  }

  void _complete(String summary) {
    final answers = <String, String>{};
    for (var i = 0; i < _questions.length; i++) {
      final selected = _selectedAnswers[i] ?? _questions[i].selectedOption;
      if (selected != null) {
        answers[_questions[i].id] = selected;
      }
    }
    final callback = widget.onCompletedWithAnswers;
    if (callback != null) {
      callback(summary, answers);
    } else {
      widget.onCompleted(summary);
    }
  }

  void _selectOption(String optionText) {
    if (_tapFeedbackOption != null) {
      return; // ป้องกันการกดซ้ำระหว่างเปลี่ยนข้อ
    }
    setState(() {
      _tapFeedbackOption = optionText;
      final prevChoice = _selectedAnswers[_currentIndex];
      _selectedAnswers[_currentIndex] = optionText;
      // If user changed their answer on a previous step, invalidate subsequent step answers
      if (prevChoice != null && prevChoice != optionText) {
        _selectedAnswers.removeWhere((step, _) => step > _currentIndex);
      }
    });

    if (_currentIndex < _questions.length - 1) {
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
        for (var i = 0; i < _questions.length; i++) {
          final ans = _selectedAnswers[i] ?? _questions[i].selectedOption;
          if (ans != null && ans.isNotEmpty) {
            answers.add(ans);
          }
        }
        final summary = answers.isNotEmpty ? answers.join(', ') : optionText;
        _complete(summary);
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
    if (_currentIndex < _questions.length - 1 &&
        _selectedAnswers.containsKey(_currentIndex)) {
      setState(() {
        _currentIndex++;
        _tapFeedbackOption = null;
      });
    }
  }

  void _skip() {
    if (_selectedAnswers.isNotEmpty) {
      final answers = <String>[];
      for (var i = 0; i < _questions.length; i++) {
        final ans = _selectedAnswers[i] ?? _questions[i].selectedOption;
        if (ans != null && ans.isNotEmpty) {
          answers.add(ans);
        }
      }
      if (answers.isNotEmpty) {
        _complete(answers.join(', '));
        return;
      }
    }
    _complete('ข้ามแบบสอบถาม');
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) return const SizedBox.shrink();

    // If all questions are already answered, show recap card for all of them
    if (_questions.every((q) => q.selectedOption != null)) {
      return QuestionnaireRecapCard(questions: _questions);
    }

    final safeIndex = _currentIndex.clamp(0, _questions.length - 1);
    final currentQuestion = _questions[safeIndex];

    var effectiveTitle = currentQuestion.title;
    var effectiveOptions = currentQuestion.options;
    // ใช้เฉพาะตัวเลือกที่โมเดลส่งมา และจับคู่รหัสตัวเลือกตรงตัว
    if (safeIndex > 0) {
      final previous = _selectedAnswers[safeIndex - 1];
      if (previous != null) {
        final prevTrim = previous.trim();
        final branchTitle = currentQuestion.branchTitles?[previous] ??
            currentQuestion.branchTitles?[prevTrim];
        final branchOpt = currentQuestion.branchOptions?[previous] ??
            currentQuestion.branchOptions?[prevTrim];

        if (branchTitle != null && branchTitle.isNotEmpty) {
          effectiveTitle = branchTitle;
        }
        if (branchOpt != null && branchOpt.isNotEmpty) {
          effectiveOptions = branchOpt;
        }
      }
    }

    if (effectiveOptions.length > 4) {
      effectiveOptions = effectiveOptions.take(4).toList();
    }

    final totalSteps = _questions.length;
    final currentStep = safeIndex + 1;
    final stepText = '$currentStep of $totalSteps';
    final hasMultipleSteps = totalSteps > 1;
    final canGoBack = hasMultipleSteps && safeIndex > 0;
    final canGoForward =
        hasMultipleSteps &&
        safeIndex < _questions.length - 1 &&
        _selectedAnswers.containsKey(safeIndex);

    final selectedForCurrent =
        _tapFeedbackOption ??
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
                padding: EdgeInsets.symmetric(
                  horizontal: hasMultipleSteps ? 4 : 8,
                  vertical: 2,
                ),
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
                    if (hasMultipleSteps)
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
                                : const Color(
                                    0xFFC4B5FD,
                                  ).withValues(alpha: 0.6),
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
                    if (hasMultipleSteps)
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
                                : const Color(
                                    0xFFC4B5FD,
                                  ).withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  effectiveTitle,
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
          for (var i = 0; i < effectiveOptions.length; i++) ...[
            _OptionTile(
              index: i,
              optionText: effectiveOptions[i],
              isSelected: selectedForCurrent == effectiveOptions[i],
              onTap: () => _selectOption(effectiveOptions[i]),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Spacer(),
              TextButton(
                key: const Key('chatbot-questionnaire-skip'),
                onPressed: _skip,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
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
  const QuestionnaireRecapCard({this.question, this.questions, super.key})
    : assert(question != null || questions != null);

  final ClarificationQuestion? question;
  final List<ClarificationQuestion>? questions;

  @override
  Widget build(BuildContext context) {
    final list =
        questions ??
        (question != null ? [question!] : const <ClarificationQuestion>[]);
    final answered = list
        .where(
          (q) =>
              q.selectedOption != null && q.selectedOption!.trim().isNotEmpty,
        )
        .toList();
    if (answered.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const Key('chatbot-questionnaire-recap'),
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 14, color: Color(0xFF64748B)),
              SizedBox(width: 6),
              Text(
                'ความต้องการที่คุณเลือก',
                style: TextStyle(
                  fontFamily: 'Prompt',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < answered.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(color: Color(0xFFE2E8F0), height: 1),
              ),
            Container(
              key: Key('chatbot-questionnaire-recap-${answered[i].id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    answered[i].title,
                    style: const TextStyle(
                      fontFamily: 'Prompt',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    answered[i].selectedOption ?? '',
                    style: const TextStyle(
                      fontFamily: 'Prompt',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

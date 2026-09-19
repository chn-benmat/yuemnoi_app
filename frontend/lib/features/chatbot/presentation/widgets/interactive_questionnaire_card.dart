import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';

class InteractiveQuestionnaireCard extends StatefulWidget {
  const InteractiveQuestionnaireCard({
    required this.questions,
    required this.onCompleted,
    this.onCompletedWithAnswers,
    required this.onDismiss,
    this.onCustomInput,
    super.key,
  });

  final List<ClarificationQuestion> questions;
  final ValueChanged<String> onCompleted;
  final void Function(String, Map<String, String>)? onCompletedWithAnswers;
  final VoidCallback onDismiss;
  final VoidCallback? onCustomInput;

  @override
  State<InteractiveQuestionnaireCard> createState() =>
      InteractiveQuestionnaireCardState();
}

class InteractiveQuestionnaireCardState
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
  void dispose() {
    super.dispose();
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

  void submitCustomAnswer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      widget.onCustomInput?.call();
      return;
    }
    _selectedAnswers[_currentIndex] = trimmed;
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _tapFeedbackOption = null;
      });
    } else {
      final answers = <String>[];
      for (var i = 0; i < _questions.length; i++) {
        final ans = _selectedAnswers[i] ?? _questions[i].selectedOption;
        if (ans != null && ans.isNotEmpty) {
          answers.add(ans);
        }
      }
      final summary = answers.isNotEmpty ? answers.join(', ') : trimmed;
      _complete(summary);
    }
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x087400C9),
            blurRadius: 10,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Progress Bar
          if (hasMultipleSteps)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: List.generate(totalSteps, (i) {
                  final isPassedOrCurrent = i <= safeIndex;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i < totalSteps - 1 ? 6 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: isPassedOrCurrent
                            ? AppColors.primaryColor
                            : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

          // Header: Step count badge + Skip + Close Button
          Row(
            children: [
              if (hasMultipleSteps)
                InkWell(
                  key: const Key('chatbot-questionnaire-prev'),
                  onTap: canGoBack ? _goToPrevious : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 20,
                      color: canGoBack
                          ? const Color(0xFF4B5563)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryColor.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      size: 13,
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      stepText,
                      style: const TextStyle(
                        fontFamily: 'Prompt',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasMultipleSteps)
                InkWell(
                  key: const Key('chatbot-questionnaire-next'),
                  onTap: canGoForward ? _goToNext : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: canGoForward
                          ? const Color(0xFF4B5563)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                key: const Key('chatbot-questionnaire-skip'),
                onPressed: _skip,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    fontFamily: 'Prompt',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('chatbot-questionnaire-close'),
                tooltip: 'ปิด',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Color(0xFF9CA3AF),
                ),
                onPressed: widget.onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Question Title
          Text(
            effectiveTitle,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              fontFamily: 'Prompt',
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          // Options List as Interactive Selectable Cards
          for (var i = 0; i < effectiveOptions.length; i++)
            _OptionTile(
              index: i,
              optionText: effectiveOptions[i],
              isSelected: selectedForCurrent == effectiveOptions[i],
              onTap: () => _selectOption(effectiveOptions[i]),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryColor.withValues(alpha: 0.08)
            : const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppColors.primaryColor
              : const Color(0xFFE2E8F0),
          width: isSelected ? 1.6 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('chatbot-questionnaire-option-$optionText'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primaryColor.withValues(alpha: 0.12),
          highlightColor: AppColors.primaryColor.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryColor
                        : const Color(0xFFEDF0F3),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontFamily: 'Prompt',
                      color: isSelected ? Colors.white : const Color(0xFF4B5563),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    optionText,
                    style: TextStyle(
                      fontFamily: 'Prompt',
                      fontSize: 15,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primaryColor
                          : const Color(0xFF1E293B),
                      height: 1.35,
                    ),
                  ),
                ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: AppColors.primaryColor,
                    ),
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

import 'package:flutter/material.dart';

import '../../domain/entities/chat_message.dart';
import 'chatbot_design.dart';

class InteractiveQuestionnaireCard extends StatefulWidget {
  const InteractiveQuestionnaireCard({
    required this.questions,
    required this.onCompleted,
    this.onCompletedWithAnswers,
    this.onCompletedWithContext,
    required this.onDismiss,
    this.onCustomInput,
    this.onRequestStarted,
    this.onContentRendered,
    this.onQuestionChanged,
    super.key,
  });

  final List<ClarificationQuestion> questions;
  final ValueChanged<String> onCompleted;
  final void Function(String, Map<String, String>)? onCompletedWithAnswers;
  final void Function(String, List<QuestionnaireAnswer>, bool)?
  onCompletedWithContext;
  final VoidCallback onDismiss;
  final VoidCallback? onCustomInput;
  final VoidCallback? onRequestStarted;
  final VoidCallback? onContentRendered;
  final VoidCallback? onQuestionChanged;

  @override
  State<InteractiveQuestionnaireCard> createState() =>
      InteractiveQuestionnaireCardState();
}

class InteractiveQuestionnaireCardState
    extends State<InteractiveQuestionnaireCard> {
  late List<ClarificationQuestion> _questions;
  int _currentIndex = 0;
  final Map<int, String> _selectedAnswers = {};
  final Map<int, String> _selectedChoiceIds = {};
  String? _tapFeedbackOption;
  int _progressGeneration = 0;

  String? get activeQuestionId =>
      _questions.isEmpty ? null : _questions[_currentIndex].id;
  String? get activeQuestionTitle =>
      _questions.isEmpty ? null : _effectiveQuestion(_currentIndex).$1;

  (String, List<String>, List<QuestionChoice>) _effectiveQuestion(int index) {
    final question = _questions[index];
    if (question.branchQuestionId != null) {
      final source = _questions.indexWhere(
        (q) => q.id == question.branchQuestionId,
      );
      final optionId = source < 0
          ? null
          : _selectedChoiceIds[source] ?? _questions[source].selectedOptionId;
      final choices = question.branchChoices[optionId];
      if (choices != null) {
        return (
          question.branchTitles?[optionId] ?? question.title,
          choices.map((c) => c.label).toList(),
          choices,
        );
      }
    }
    return (question.title, question.options, question.choices);
  }

  List<QuestionnaireAnswer> get partialAnswers {
    final answers = <QuestionnaireAnswer>[];
    for (var i = 0; i < _questions.length; i++) {
      final text = _selectedAnswers[i] ?? _questions[i].selectedOption;
      final choiceId = _selectedChoiceIds[i] ?? _questions[i].selectedOptionId;
      if (text != null) {
        answers.add(
          QuestionnaireAnswer(
            questionId: _questions[i].id,
            optionId: choiceId,
            text: choiceId == null ? text : null,
          ),
        );
      }
    }
    return List.unmodifiable(answers);
  }

  // ยกเลิกการเลื่อนข้อหรือส่งคำตอบที่รออยู่ เมื่อผู้ใช้ส่งข้อความแทรก
  void suspendProgression() => _progressGeneration++;

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
    _progressGeneration++;
    _selectedAnswers.clear();
    _selectedChoiceIds.clear();
    _tapFeedbackOption = null;
    _questions = List<ClarificationQuestion>.from(widget.questions);
    final firstUnanswered = _questions.indexWhere(
      (q) => q.selectedOption == null,
    );
    _currentIndex = firstUnanswered != -1 ? firstUnanswered : 0;
  }

  void _complete(String summary, {bool skipped = false}) {
    final answers = <String, String>{};
    for (var i = 0; i < _questions.length; i++) {
      final selected = _selectedAnswers[i] ?? _questions[i].selectedOption;
      if (selected != null) {
        answers[_questions[i].id] = selected;
      }
    }
    if (widget.onCompletedWithContext != null) {
      widget.onCompletedWithContext!(summary, partialAnswers, skipped);
      return;
    }
    final callback = widget.onCompletedWithAnswers;
    if (callback != null) {
      callback(summary, answers);
    } else {
      widget.onCompleted(summary);
    }
  }

  void _selectOption(String optionText, String? optionId) {
    if (_tapFeedbackOption != null) {
      return; // ป้องกันการกดซ้ำระหว่างเปลี่ยนข้อ
    }
    final generation = _progressGeneration;
    setState(() {
      _tapFeedbackOption = optionText;
      final prevChoice = _selectedAnswers[_currentIndex];
      _selectedAnswers[_currentIndex] = optionText;
      if (optionId == null) {
        _selectedChoiceIds.remove(_currentIndex);
      } else {
        _selectedChoiceIds[_currentIndex] = optionId;
      }
      // If user changed their answer on a previous step, invalidate subsequent step answers
      if (prevChoice != null && prevChoice != optionText) {
        _selectedAnswers.removeWhere((step, _) => step > _currentIndex);
        _selectedChoiceIds.removeWhere((step, _) => step > _currentIndex);
      }
    });

    if (_currentIndex < _questions.length - 1) {
      // เปลี่ยนข้อหลังให้ feedback สั้น ๆ และไม่หน่วงเมื่อผู้ใช้ลดแอนิเมชัน
      Future.delayed(
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        () {
          if (!mounted || generation != _progressGeneration) return;
          setState(() {
            _currentIndex++;
            _tapFeedbackOption = null;
          });
          widget.onQuestionChanged?.call();
        },
      );
    } else {
      widget.onRequestStarted?.call();
      // All questions completed, compile combined answer and submit
      Future.delayed(ChatbotDesign.motionFor(context), () {
        if (!mounted || generation != _progressGeneration) return;
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
      widget.onQuestionChanged?.call();
    }
  }

  void _goToNext() {
    if (_currentIndex < _questions.length - 1 &&
        _selectedAnswers.containsKey(_currentIndex)) {
      setState(() {
        _currentIndex++;
        _tapFeedbackOption = null;
      });
      widget.onQuestionChanged?.call();
    }
  }

  void _skip() {
    widget.onRequestStarted?.call();
    if (_selectedAnswers.isNotEmpty) {
      final answers = <String>[];
      for (var i = 0; i < _questions.length; i++) {
        final ans = _selectedAnswers[i] ?? _questions[i].selectedOption;
        if (ans != null && ans.isNotEmpty) {
          answers.add(ans);
        }
      }
      if (answers.isNotEmpty) {
        _complete(answers.join(', '), skipped: true);
        return;
      }
    }
    _complete('ข้ามแบบสอบถาม', skipped: true);
  }

  void submitCustomAnswer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      widget.onCustomInput?.call();
      return;
    }
    suspendProgression();
    final previous = _selectedAnswers[_currentIndex];
    if (previous != null && previous != trimmed) {
      _selectedAnswers.removeWhere((step, _) => step > _currentIndex);
      _selectedChoiceIds.removeWhere((step, _) => step > _currentIndex);
    }
    _selectedAnswers[_currentIndex] = trimmed;
    _selectedChoiceIds.remove(_currentIndex);
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _tapFeedbackOption = null;
      });
      widget.onQuestionChanged?.call();
    } else {
      widget.onRequestStarted?.call();
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

    // แสดงสรุปเมื่อคำถามทุกข้อมีคำตอบแล้ว
    if (_questions.every((q) => q.selectedOption != null)) {
      return QuestionnaireRecapCard(questions: _questions);
    }

    final safeIndex = _currentIndex.clamp(0, _questions.length - 1);
    final currentQuestion = _questions[safeIndex];

    var (effectiveTitle, effectiveOptions, effectiveChoices) =
        _effectiveQuestion(safeIndex);
    // ใช้เฉพาะตัวเลือกที่โมเดลส่งมา และจับคู่รหัสตัวเลือกตรงตัว
    if (safeIndex > 0 && currentQuestion.branchQuestionId == null) {
      final previous = _selectedAnswers[safeIndex - 1];
      if (previous != null) {
        final prevTrim = previous.trim();
        final branchTitle =
            currentQuestion.branchTitles?[previous] ??
            currentQuestion.branchTitles?[prevTrim];
        final branchOpt =
            currentQuestion.branchOptions?[previous] ??
            currentQuestion.branchOptions?[prevTrim];

        if (branchTitle != null && branchTitle.isNotEmpty) {
          effectiveTitle = branchTitle;
        }
        if (branchOpt != null && branchOpt.isNotEmpty) {
          effectiveOptions = branchOpt;
          effectiveChoices = const [];
        }
      }
    }

    final renderedQuestions = widget.questions;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(renderedQuestions, widget.questions)) {
        widget.onContentRendered?.call();
      }
    });
    final totalSteps = _questions.length;
    final selected =
        _tapFeedbackOption ??
        _selectedAnswers[safeIndex] ??
        currentQuestion.selectedOption;
    return Container(
      key: const Key('chatbot-questionnaire-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ChatbotDesign.subtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ChatbotDesign.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ข้อ ${safeIndex + 1} จาก $totalSteps',
                  style: ChatbotDesign.caption.copyWith(
                    color: ChatbotDesign.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const Key('chatbot-questionnaire-close'),
                tooltip: 'ปิดคำถาม',
                onPressed: widget.onDismiss,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(
                  Icons.close_rounded,
                  color: ChatbotDesign.muted,
                ),
              ),
            ],
          ),
          if (totalSteps > 1) ...[
            LinearProgressIndicator(
              value: (safeIndex + 1) / totalSteps,
              color: ChatbotDesign.primary,
              backgroundColor: ChatbotDesign.border,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            effectiveTitle,
            style: ChatbotDesign.body.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < effectiveOptions.length; i++)
            _OptionTile(
              optionText: effectiveOptions[i],
              isSelected: selected == effectiveOptions[i],
              onTap: () => _selectOption(
                effectiveOptions[i],
                i < effectiveChoices.length ? effectiveChoices[i].id : null,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (totalSteps > 1)
                IconButton(
                  key: const Key('chatbot-questionnaire-prev'),
                  tooltip: 'ข้อก่อนหน้า',
                  onPressed: safeIndex > 0 ? _goToPrevious : null,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
              TextButton(
                key: const Key('chatbot-questionnaire-skip'),
                onPressed: _skip,
                style: TextButton.styleFrom(minimumSize: ChatbotDesign.button),
                child: const Text('ข้าม'),
              ),
              if (totalSteps > 1)
                IconButton(
                  key: const Key('chatbot-questionnaire-next'),
                  tooltip: 'ข้อถัดไป',
                  onPressed:
                      safeIndex < totalSteps - 1 &&
                          _selectedAnswers.containsKey(safeIndex)
                      ? _goToNext
                      : null,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              if (widget.onCustomInput != null)
                TextButton(
                  key: const Key('chatbot-questionnaire-custom-input'),
                  style: TextButton.styleFrom(
                    minimumSize: ChatbotDesign.button,
                  ),
                  onPressed: () {
                    suspendProgression();
                    widget.onCustomInput!();
                  },
                  child: const Text('พิมพ์ตอบเอง'),
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
    required this.optionText,
    required this.isSelected,
    required this.onTap,
  });
  final String optionText;
  final bool isSelected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: isSelected,
    child: AnimatedContainer(
      duration: ChatbotDesign.motionFor(context),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? ChatbotDesign.tint : ChatbotDesign.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? ChatbotDesign.primary : ChatbotDesign.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('chatbot-questionnaire-option-$optionText'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: isSelected
                        ? ChatbotDesign.primary
                        : ChatbotDesign.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      optionText,
                      style: ChatbotDesign.body.copyWith(
                        fontSize: 15,
                        color: isSelected
                            ? ChatbotDesign.primary
                            : ChatbotDesign.ink,
                        fontWeight: isSelected
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// สรุปคำตอบที่เลือกไว้ในประวัติสนทนา
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
        color: ChatbotDesign.subtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChatbotDesign.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 14, color: ChatbotDesign.muted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'ความต้องการที่คุณเลือก',
                  style: ChatbotDesign.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < answered.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(color: ChatbotDesign.border, height: 1),
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
                      color: ChatbotDesign.muted,
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
                      color: ChatbotDesign.ink,
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

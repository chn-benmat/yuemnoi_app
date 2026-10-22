import 'package:frontend/core/widgets/app_popup.dart';
import '../../../../core/widgets/package_chat_list.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/responsive_app_bar_title.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_turn_timing.dart';
import '../bloc/chatbot_bloc.dart';
import '../bloc/chatbot_event.dart';
import '../bloc/chatbot_state.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/interactive_questionnaire_card.dart';
import '../widgets/chatbot_composer.dart';
import '../widgets/chatbot_design.dart';
import '../widgets/chatbot_welcome.dart';
import '../widgets/chatbot_state_card.dart';

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({this.now = DateTime.now, super.key});
  final DateTime Function() now;

  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen> {
  static const double _scrollButtonThreshold = 120;
  static const double _autoScrollThreshold = 320;

  final GlobalKey<InteractiveQuestionnaireCardState> _questionnaireKey =
      GlobalKey<InteractiveQuestionnaireCardState>();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final Set<int> _pendingAssistantAnimations = <int>{};
  final Set<int> _startedAssistantAnimations = <int>{};
  int _observedMessageCount = 0;
  ChatTurnTiming? _questionnaireTiming;
  final Set<String> _renderedBubbles = {};
  final Set<String> _renderedQuestionnaires = {};
  final Set<String> _reportedRenders = {};

  void _observeRender(ChatMessage message, {bool questionnaire = false}) {
    if (message.id.isEmpty || message.isStreaming) return;
    (questionnaire ? _renderedQuestionnaires : _renderedBubbles).add(
      message.id,
    );
    if (!_renderedBubbles.contains(message.id) ||
        (message.questions.any((q) => q.selectedOption == null) &&
            !_renderedQuestionnaires.contains(message.id)) ||
        !_reportedRenders.add(message.id)) {
      return;
    }
    context.read<ChatbotBloc>().add(ChatbotResponseRendered(message.id));
  }

  int? _editingMessageIndex;
  bool _showScrollToBottomButton = false;
  bool _dismissedQuestionnaire = false;
  String? _customAnswerQuestionId;
  bool _isScrollToBottomScheduled = false;
  bool _isScrollScheduled = false;
  bool _hasPendingScroll = false;
  bool _pendingScrollForce = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollPosition);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScrollPosition);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _sendMessage(ChatbotState state) {
    final query = _messageController.text.trim();
    if (query.isEmpty || state.isSending) return;

    final editingMessageIndex = _editingMessageIndex;
    if (editingMessageIndex != null) {
      _observedMessageCount = editingMessageIndex + 1;
      _pendingAssistantAnimations.clear();
      _startedAssistantAnimations.clear();
      context.read<ChatbotBloc>().add(
        ChatbotMessageEdited(
          index: editingMessageIndex,
          content: query,
          timing: ChatTurnTiming(),
        ),
      );
      setState(() {
        _editingMessageIndex = null;
        _dismissedQuestionnaire = false;
      });
    } else {
      final hasActiveQuestionnaire =
          !_dismissedQuestionnaire &&
          state.messages.isNotEmpty &&
          state.messages.last.role == ChatMessageRole.assistant &&
          state.messages.last.questions.isNotEmpty &&
          state.messages.last.questions.any((q) => q.selectedOption == null);

      if (hasActiveQuestionnaire && _questionnaireKey.currentState != null) {
        final questionnaire = _questionnaireKey.currentState!;
        if (_customAnswerQuestionId != null &&
            _customAnswerQuestionId == questionnaire.activeQuestionId) {
          questionnaire.suspendProgression();
          setState(() => _customAnswerQuestionId = null);
          _messageController.clear();
          questionnaire.submitCustomAnswer(query);
          _messageFocusNode.requestFocus();
          return;
        }
        final answers = questionnaire.partialAnswers;
        questionnaire.suspendProgression();
        context.read<ChatbotBloc>().add(
          ChatbotMessageSubmitted(
            query,
            activeQuestionId: questionnaire.activeQuestionId,
            questionnaireAnswers: answers,
            selectedOptions: {
              for (final answer in answers)
                answer.questionId: answer.optionId ?? answer.text!,
            },
            timing: ChatTurnTiming(),
          ),
        );
        _messageController.clear();
        _messageFocusNode.requestFocus();
        return;
      }

      context.read<ChatbotBloc>().add(
        ChatbotMessageSubmitted(query, timing: ChatTurnTiming()),
      );
      setState(() {
        _dismissedQuestionnaire = false;
      });
    }
    _messageController.clear();
    _messageFocusNode.requestFocus();
  }

  void _stopGeneration() {
    context.read<ChatbotBloc>().add(const ChatbotStreamStopped());
  }

  void _sendQuickReply(String text, ChatbotState state) {
    if (state.isSending || text.trim().isEmpty) return;
    context.read<ChatbotBloc>().add(
      ChatbotMessageSubmitted(text.trim(), timing: ChatTurnTiming()),
    );
    setState(() {
      _dismissedQuestionnaire = false;
      _customAnswerQuestionId = null;
    });
    _messageController.clear();
    _scrollToBottom(force: true);
  }

  void _sendQuestionnaireAnswer(
    String text,
    ChatbotState state, {
    Map<String, String> selectedOptions = const {},
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
  }) {
    if (state.isSending || text.trim().isEmpty) return;
    context.read<ChatbotBloc>().add(
      ChatbotMessageSubmitted(
        text.trim(),
        isVisibleInChat: false,
        selectedOptions: selectedOptions,
        questionnaireAnswers: questionnaireAnswers,
        questionnaireSkipped: questionnaireSkipped,
        timing: _questionnaireTiming ?? ChatTurnTiming(),
      ),
    );
    _questionnaireTiming = null;
    setState(() {
      _dismissedQuestionnaire = false;
      _customAnswerQuestionId = null;
    });
    _messageController.clear();
    _scrollToBottom(force: true);
  }

  void _startEditingMessage(int index, ChatMessage message) {
    setState(() {
      _customAnswerQuestionId = null;
      _editingMessageIndex = index;
      _messageController.text = message.content;
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
    });
    _messageFocusNode.requestFocus();
  }

  void _cancelEditingMessage() {
    setState(() {
      _editingMessageIndex = null;
      _messageController.clear();
    });
    _messageFocusNode.requestFocus();
  }

  Future<void> _showMessageActions(int index, ChatMessage message) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => SafeArea(
        child: Container(
          key: const Key('chatbot-message-action-sheet'),
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: ChatbotDesign.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ChatbotDesign.border),
            boxShadow: [
              BoxShadow(
                color: ChatbotDesign.ink.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('chatbot-copy-message-action'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(modalContext).pop();
                      Clipboard.setData(ClipboardData(text: message.content));
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            color: ChatbotDesign.primary,
                            size: 20,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'คัดลอก',
                              style: TextStyle(
                                fontFamily: 'Prompt',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: ChatbotDesign.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(color: ChatbotDesign.border, height: 1),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('chatbot-edit-message-action'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(modalContext).pop();
                      _startEditingMessage(index, message);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_rounded,
                            color: ChatbotDesign.primary,
                            size: 20,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'แก้ไข',
                              style: TextStyle(
                                fontFamily: 'Prompt',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: ChatbotDesign.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleScrollPosition() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    final shouldShow = distanceFromBottom > _scrollButtonThreshold;
    if (shouldShow == _showScrollToBottomButton || !mounted) return;

    setState(() {
      _showScrollToBottomButton = shouldShow;
    });
  }

  void _scrollToBottom({bool force = false}) {
    if (_isScrollToBottomScheduled) {
      _hasPendingScroll = true;
      if (force) _pendingScrollForce = true;
      return;
    }
    _isScrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted || !_scrollController.hasClients) return;
        if (_showScrollToBottomButton && !force) return;

        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
        if (!mounted || !_scrollController.hasClients) return;
        if (_showScrollToBottomButton && !force) return;

        final position = _scrollController.position;
        if (position.pixels != position.maxScrollExtent) {
          position.jumpTo(position.maxScrollExtent);
        }
      } catch (_) {
        // Safe against animation interruption during user gesture
      } finally {
        _isScrollToBottomScheduled = false;
        if (_hasPendingScroll && mounted) {
          final shouldForce = _pendingScrollForce;
          _hasPendingScroll = false;
          _pendingScrollForce = false;
          _scrollToBottom(force: shouldForce);
        }
      }
    });
  }

  void _keepLatestMessageVisible() {
    if (!mounted || !_scrollController.hasClients || _isScrollScheduled) {
      return;
    }
    final currentPosition = _scrollController.position;
    if (!currentPosition.hasContentDimensions) return;
    final currentDistanceFromBottom =
        currentPosition.maxScrollExtent - currentPosition.pixels;
    if (currentDistanceFromBottom >= _autoScrollThreshold) return;

    _isScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isScrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final distanceFromBottom = position.maxScrollExtent - position.pixels;
      if (distanceFromBottom < _autoScrollThreshold &&
          position.pixels != position.maxScrollExtent) {
        position.jumpTo(position.maxScrollExtent);
      }
    });
  }

  void _trackNewAssistantMessage(ChatbotState state) {
    if (state.messages.isNotEmpty &&
        state.messages.last.role == ChatMessageRole.assistant &&
        (state.messages.length > _observedMessageCount ||
            !_startedAssistantAnimations.contains(state.messages.length - 1))) {
      _pendingAssistantAnimations.add(state.messages.length - 1);
    }
    _observedMessageCount = state.messages.length;
  }

  void _markAssistantAnimationStarted(int messageIndex) {
    _pendingAssistantAnimations.remove(messageIndex);
    _startedAssistantAnimations.add(messageIndex);
  }

  void _prefillMessage(String text) {
    _messageController.text = text;
    _messageController.selection = TextSelection.collapsed(offset: text.length);
    _messageFocusNode.requestFocus();
  }

  Widget _questionnaire(ChatbotState state) => InteractiveQuestionnaireCard(
    key: _questionnaireKey,
    questions: state.messages.last.questions,
    onRequestStarted: () => _questionnaireTiming = ChatTurnTiming(),
    onContentRendered: () =>
        _observeRender(state.messages.last, questionnaire: true),
    onCompleted: (summary) => _sendQuestionnaireAnswer(summary, state),
    onCompletedWithAnswers: (summary, answers) =>
        _sendQuestionnaireAnswer(summary, state, selectedOptions: answers),
    onCompletedWithContext: (summary, answers, skipped) =>
        _sendQuestionnaireAnswer(
          summary,
          state,
          questionnaireAnswers: answers,
          questionnaireSkipped: skipped,
        ),
    onDismiss: () => setState(() {
      _dismissedQuestionnaire = true;
      _customAnswerQuestionId = null;
    }),
    onCustomInput: () {
      _questionnaireKey.currentState?.suspendProgression();
      _questionnaireTiming = null;
      setState(() {
        _customAnswerQuestionId =
            _questionnaireKey.currentState?.activeQuestionId;
      });
      _messageFocusNode.requestFocus();
    },
    onQuestionChanged: () {
      if (_customAnswerQuestionId != null) {
        setState(() => _customAnswerQuestionId = null);
      }
    },
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: ChatbotDesign.primary),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ChatbotDesign.primary,
          minimumSize: ChatbotDesign.button,
        ),
      ),
    ),
    child: Scaffold(
      backgroundColor: ChatbotDesign.canvas,
      appBar: AppBar(
        backgroundColor: ChatbotDesign.surface,
        foregroundColor: ChatbotDesign.ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: ChatbotDesign.border),
        ),
        leading: IconButton(
          tooltip: 'ย้อนกลับ',
          onPressed: () => AppRoutes.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              color: ChatbotDesign.primary,
              size: 18,
            ),
            SizedBox(width: 8),
            Flexible(
              child: ResponsiveAppBarTitle(
                'ยืมหน่อย AI',
                style: TextStyle(
                  fontFamily: 'Prompt',
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: ChatbotDesign.ink,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: BlocConsumer<ChatbotBloc, ChatbotState>(
          listenWhen: (previous, current) =>
              previous.messages != current.messages ||
              previous.isSending != current.isSending,
          listener: (context, state) {
            _trackNewAssistantMessage(state);
            if (state.messages.isNotEmpty && state.messages.last.isStreaming) {
              _keepLatestMessageVisible();
            } else {
              _scrollToBottom();
            }
          },
          builder: (context, state) {
            final lastMessage = state.messages.isEmpty
                ? null
                : state.messages.last;
            final hasActiveQuestionnaire =
                !_dismissedQuestionnaire &&
                !state.isSending &&
                lastMessage?.role == ChatMessageRole.assistant &&
                lastMessage!.questions.any((q) => q.selectedOption == null);
            final isAssistantEmpty =
                lastMessage?.role == ChatMessageRole.assistant &&
                lastMessage!.content.isEmpty &&
                lastMessage.recommendedItems.isEmpty &&
                lastMessage.questions.isEmpty;
            final waiting =
                state.isSending &&
                (lastMessage == null ||
                    lastMessage.role == ChatMessageRole.user ||
                    isAssistantEmpty);
            final visibleEntries = <(int, ChatMessage)>[
              for (var i = 0; i < state.messages.length; i++)
                if (state.messages[i].isVisibleInChat &&
                    !(i == state.messages.length - 1 && isAssistantEmpty))
                  (i, state.messages[i]),
            ];
            return LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: ChatbotDesign.maxWidth,
                        ),
                        child: Stack(
                          children: [
                            if (state.messages.isEmpty)
                              ChatbotWelcome(onSelect: _prefillMessage)
                            else
                              PackageChatList(
                                key: const Key('chatbot-conversation'),
                                scrollController: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  20,
                                  16,
                                  24,
                                ),
                                entries: [
                                  for (final (originalIndex, message)
                                      in visibleEntries)
                                    PackageChatEntry(
                                      id: 'ai:${message.id.isEmpty ? 'entry-$originalIndex' : message.id}',
                                      authorId: message.role.apiValue,
                                      revision: Object.hash(
                                        message,
                                        state.failure,
                                        state.currentStatusMessage,
                                        hasActiveQuestionnaire,
                                      ),
                                    ),
                                  if (waiting)
                                    PackageChatEntry(
                                      id: '__ai_waiting',
                                      authorId: 'assistant',
                                      revision: state.currentStatusMessage,
                                    ),
                                ],
                                itemBuilder: (context, index) {
                                  if (index == visibleEntries.length) {
                                    return _TypingIndicator(
                                      statusMessage: state.currentStatusMessage,
                                      startedAt: state.requestStartTime,
                                      now: widget.now,
                                    );
                                  }
                                  final (originalIndex, message) =
                                      visibleEntries[index];
                                  final active =
                                      hasActiveQuestionnaire &&
                                      originalIndex ==
                                          state.messages.length - 1;
                                  final failure = state.failure;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: _ConversationEntry(
                                      key: ValueKey(
                                        'chat-message-$originalIndex',
                                      ),
                                      keepAlive: active,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (failure?.messageId == message.id)
                                            ChatbotFailureCard(
                                              failure: failure!,
                                              onRetry: () => context
                                                  .read<ChatbotBloc>()
                                                  .add(
                                                    ChatbotRetryRequested(
                                                      message.id,
                                                      timing: ChatTurnTiming(),
                                                    ),
                                                  ),
                                              onRevise: () => _prefillMessage(
                                                message.userQuery ?? '',
                                              ),
                                            )
                                          else
                                            ChatMessageBubble(
                                              message: message,
                                              onRentPressed: _showRentMessage,
                                              animateAssistantResponse:
                                                  _pendingAssistantAnimations
                                                      .contains(
                                                        originalIndex,
                                                      ) &&
                                                  !_startedAssistantAnimations
                                                      .contains(originalIndex),
                                              onAnimationStarted: () =>
                                                  _markAssistantAnimationStarted(
                                                    originalIndex,
                                                  ),
                                              onTextProgress:
                                                  _keepLatestMessageVisible,
                                              onContentRendered: () =>
                                                  _observeRender(message),
                                              onCardRevealed:
                                                  _keepLatestMessageVisible,
                                              onEdit:
                                                  message.role ==
                                                          ChatMessageRole
                                                              .user &&
                                                      !state.isSending
                                                  ? () => _showMessageActions(
                                                      originalIndex,
                                                      message,
                                                    )
                                                  : null,
                                              onReviseQuery: () =>
                                                  _prefillMessage(
                                                    message.userQuery ?? '',
                                                  ),
                                              onOptionSelected: (choice) =>
                                                  _sendQuickReply(
                                                    choice,
                                                    state,
                                                  ),
                                              questionnaire: active
                                                  ? _questionnaire(state)
                                                  : null,
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: AnimatedScale(
                                key: const Key(
                                  'chatbot-scroll-to-bottom-control',
                                ),
                                scale: _showScrollToBottomButton ? 1 : 0,
                                duration: ChatbotDesign.motionFor(context),
                                child: IgnorePointer(
                                  ignoring: !_showScrollToBottomButton,
                                  child: Material(
                                    key: const Key(
                                      'chatbot-scroll-to-bottom-button',
                                    ),
                                    color: ChatbotDesign.surface,
                                    elevation: 2,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: 'เลื่อนไปข้อความล่าสุด',
                                      onPressed: () =>
                                          _scrollToBottom(force: true),
                                      color: ChatbotDesign.primary,
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                        minHeight: 48,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ให้ช่องพิมพ์เลื่อนได้เมื่อคีย์บอร์ดและตัวอักษรใหญ่เหลือพื้นที่น้อย
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .55,
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: ChatbotComposer(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        isSending: state.isSending,
                        editingMessage: _editingMessageIndex == null
                            ? null
                            : state.messages[_editingMessageIndex!],
                        onCancelEdit: _cancelEditingMessage,
                        customQuestionTitle:
                            hasActiveQuestionnaire &&
                                _customAnswerQuestionId ==
                                    _questionnaireKey
                                        .currentState
                                        ?.activeQuestionId
                            ? _questionnaireKey
                                  .currentState
                                  ?.activeQuestionTitle
                            : null,
                        onCancelCustomAnswer: () =>
                            setState(() => _customAnswerQuestionId = null),
                        onSend: () => _sendMessage(state),
                        onStop: _stopGeneration,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  void _showRentMessage(RecommendedItem item) {
    final itemId = item.id;
    if (itemId != null) {
      AppRoutes.openItemDetail(context, itemId: itemId);
      return;
    }

    showAppPopup(context, content: Text('ไม่พบรหัสอุปกรณ์ กรุณาลองค้นหาใหม่'));
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({
    this.statusMessage,
    this.startedAt,
    required this.now,
  });
  final String? statusMessage;
  final DateTime? startedAt;
  final DateTime Function() now;
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final DateTime _mountedAt;
  Timer? _elapsedTimer;
  @override
  void initState() {
    super.initState();
    _mountedAt = widget.now();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.statusMessage?.trim();
    final elapsed = widget.now().difference(widget.startedAt ?? _mountedAt);
    final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ChatbotDesign.subtle,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: ChatbotDesign.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  status?.isNotEmpty == true ? status! : 'กำลังประมวลผล',
                  style: ChatbotDesign.caption.copyWith(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final count = MediaQuery.disableAnimationsOf(context)
                      ? 3
                      : 1 + (_controller.value * 3).floor().clamp(0, 2);
                  return SizedBox(
                    width: 18,
                    child: Text(
                      '.' * count,
                      key: const Key('chatbot-thinking-dots'),
                      style: ChatbotDesign.caption,
                    ),
                  );
                },
              ),
            ),
            Text(
              ' $seconds วินาที',
              key: const Key('chatbot-analysis-elapsed'),
              style: ChatbotDesign.caption,
            ),
          ],
        ),
      ),
    );
  }
}

// รักษาการ์ดคำถามและคำตอบบางส่วนไว้เมื่อเลื่อนออกจาก viewport
class _ConversationEntry extends StatefulWidget {
  const _ConversationEntry({
    required this.child,
    required this.keepAlive,
    super.key,
  });
  final Widget child;
  final bool keepAlive;
  @override
  State<_ConversationEntry> createState() => _ConversationEntryState();
}

class _ConversationEntryState extends State<_ConversationEntry>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;
  @override
  void didUpdateWidget(covariant _ConversationEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

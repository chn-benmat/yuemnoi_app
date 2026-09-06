import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../domain/entities/chat_message.dart';
import '../bloc/chatbot_bloc.dart';
import '../bloc/chatbot_event.dart';
import '../bloc/chatbot_state.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chatbot_feedback_modal.dart';
import '../widgets/interactive_questionnaire_card.dart';

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key});

  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen> {
  static const double _scrollButtonThreshold = 120;
  static const double _autoScrollThreshold = 180;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final Set<int> _pendingAssistantAnimations = <int>{};
  final Set<int> _startedAssistantAnimations = <int>{};
  int _observedMessageCount = 0;
  int? _editingMessageIndex;
  bool _showScrollToBottomButton = false;
  bool _dismissedQuestionnaire = false;
  bool _isScrollToBottomScheduled = false;
  bool _isScrollScheduled = false;

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
        ChatbotMessageEdited(index: editingMessageIndex, content: query),
      );
      setState(() {
        _editingMessageIndex = null;
        _dismissedQuestionnaire = false;
      });
    } else {
      context.read<ChatbotBloc>().add(ChatbotMessageSubmitted(query));
      setState(() {
        _dismissedQuestionnaire = false;
      });
    }
    _messageController.clear();
    _messageFocusNode.requestFocus();
  }

  void _sendQuickReply(String text, ChatbotState state) {
    if (state.isSending || text.trim().isEmpty) return;
    context.read<ChatbotBloc>().add(ChatbotMessageSubmitted(text.trim()));
    setState(() {
      _dismissedQuestionnaire = false;
    });
    _messageController.clear();
    _scrollToBottom(force: true);
  }

  void _startEditingMessage(int index, ChatMessage message) {
    setState(() {
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
            color: const Color(0xFF26262A),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
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
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('คัดลอกข้อความแล้ว'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 14),
                        Text(
                          'คัดลอก',
                          style: TextStyle(
                            fontFamily: 'Prompt',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(color: Color(0x22FFFFFF), height: 1),
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
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 14),
                        Text(
                          'แก้ไข',
                          style: TextStyle(
                            fontFamily: 'Prompt',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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
    );
  }

  void _copyMessage(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              SizedBox(width: 8),
              Text('คัดลอกข้อความแล้ว', style: TextStyle(fontFamily: 'Prompt')),
            ],
          ),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleLikeMessage(int index, ChatMessage message) {
    if (message.isLiked == true) return;

    context.read<ChatbotBloc>().add(
      ChatbotFeedbackSubmitted(messageIndex: index, isLiked: true),
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.thumb_up_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'ขอบคุณสำหรับข้อเสนอแนะค่ะ 😊',
                style: TextStyle(fontFamily: 'Prompt'),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryColor,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleDislikeMessage(int index, ChatMessage message) async {
    final result = await ChatbotFeedbackModal.show(
      context,
      initialCategory: message.feedbackReason,
      initialComment: message.feedbackComment,
    );

    if (result != null && mounted) {
      context.read<ChatbotBloc>().add(
        ChatbotFeedbackSubmitted(
          messageIndex: index,
          isLiked: false,
          reasonCategory: result.reasonCategory,
          feedbackComment: result.comment,
        ),
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.volunteer_activism_rounded,
                color: Colors.white,
                size: 18,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ขอบคุณสำหรับข้อเสนอแนะค่ะ ระบบจะนำไปพัฒนาการตอบให้ดียิ่งขึ้น 🙏',
                  style: TextStyle(fontFamily: 'Prompt'),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFF323238),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    if (_isScrollToBottomScheduled) return;
    _isScrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted || !_scrollController.hasClients) return;
        if (_showScrollToBottomButton && !force) return;

        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
        if (!mounted || !_scrollController.hasClients) return;

        final position = _scrollController.position;
        if (position.pixels != position.maxScrollExtent) {
          position.jumpTo(position.maxScrollExtent);
        }
      } catch (_) {
        // Safe against animation interruption during user gesture
      } finally {
        _isScrollToBottomScheduled = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        toolbarHeight: 72,
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          tooltip: 'ย้อนกลับ',
          onPressed: () => AppRoutes.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 30),
        ),
        title: const Text(
          'Yuemnoi AI',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: BlocConsumer<ChatbotBloc, ChatbotState>(
          listenWhen: (previous, current) =>
              previous.messages.length != current.messages.length ||
              previous.isSending != current.isSending ||
              previous.errorMessage != current.errorMessage ||
              (current.messages.isNotEmpty &&
                  current.messages.last.role == ChatMessageRole.assistant &&
                  current.messages.last.isStreaming),
          listener: (context, state) {
            _trackNewAssistantMessage(state);
            final isStreamingNow =
                state.messages.isNotEmpty &&
                state.messages.last.role == ChatMessageRole.assistant &&
                state.messages.last.isStreaming;

            if (isStreamingNow) {
              _keepLatestMessageVisible();
            } else {
              _scrollToBottom();
            }
            final errorMessage = state.errorMessage;
            if (errorMessage != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(errorMessage)));
            }
          },
          builder: (context, state) {
            final hasActiveQuestionnaire =
                !state.isSending &&
                !_dismissedQuestionnaire &&
                state.messages.isNotEmpty &&
                state.messages.last.role == ChatMessageRole.assistant &&
                state.messages.last.questions.isNotEmpty &&
                state.messages.last.questions.any(
                  (q) => q.selectedOption == null,
                );

            final lastMessage = state.messages.isNotEmpty
                ? state.messages.last
                : null;
            final isAssistantEmpty =
                lastMessage != null &&
                lastMessage.role == ChatMessageRole.assistant &&
                lastMessage.content.isEmpty &&
                lastMessage.recommendedItems.isEmpty &&
                lastMessage.questions.isEmpty;
            final isWaitingForFirstChunk =
                state.isSending &&
                (lastMessage == null ||
                    lastMessage.role == ChatMessageRole.user ||
                    isAssistantEmpty);
            final visibleMessagesCount = isAssistantEmpty
                ? state.messages.length - 1
                : state.messages.length;

            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: ListView.separated(
                            controller: _scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              MediaQuery.sizeOf(context).width < 340 ? 16 : 28,
                              24,
                              MediaQuery.sizeOf(context).width < 340 ? 16 : 28,
                              18,
                            ),
                            itemCount:
                                visibleMessagesCount +
                                (isWaitingForFirstChunk ? 1 : 0),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 24),
                            itemBuilder: (context, index) {
                              if (index == visibleMessagesCount) {
                                return const _TypingIndicator();
                              }
                              final message = state.messages[index];
                              final isAlreadyStreamed =
                                  message.role == ChatMessageRole.assistant &&
                                  (message.isStreaming ||
                                      message.responseDuration != null);
                              return ChatMessageBubble(
                                key: ValueKey('chat-message-$index'),
                                message: message,
                                onRentPressed: _showRentMessage,
                                animateAssistantResponse:
                                    !isAlreadyStreamed &&
                                    _pendingAssistantAnimations.contains(
                                      index,
                                    ) &&
                                    !_startedAssistantAnimations.contains(
                                      index,
                                    ),
                                onAnimationStarted: () =>
                                    _markAssistantAnimationStarted(index),
                                onTextProgress: _keepLatestMessageVisible,
                                onLike:
                                    message.role == ChatMessageRole.assistant &&
                                        !message.isStreaming
                                    ? () => _handleLikeMessage(index, message)
                                    : null,
                                onDislike:
                                    message.role == ChatMessageRole.assistant &&
                                        !message.isStreaming
                                    ? () =>
                                          _handleDislikeMessage(index, message)
                                    : null,
                                onCopy:
                                    message.role == ChatMessageRole.assistant &&
                                        !message.isStreaming
                                    ? () => _copyMessage(message.content)
                                    : null,
                                onEdit:
                                    state.messages[index].role ==
                                            ChatMessageRole.user &&
                                        !state.isSending
                                    ? () => _showMessageActions(
                                        index,
                                        state.messages[index],
                                      )
                                    : null,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    if (hasActiveQuestionnaire)
                      InteractiveQuestionnaireCard(
                        questions: state.messages.last.questions,
                        onCompleted: (summary) =>
                            _sendQuickReply(summary, state),
                        onDismiss: () =>
                            setState(() => _dismissedQuestionnaire = true),
                        onCustomInput: () {
                          _messageFocusNode.requestFocus();
                        },
                      )
                    else if (!state.isSending &&
                        state.messages.isNotEmpty &&
                        state.messages.last.suggestedReplies.isNotEmpty)
                      _QuickRepliesBar(
                        suggestions: state.messages.last.suggestedReplies,
                        onSelect: (text) => _sendQuickReply(text, state),
                      ),
                    _ChatComposer(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      isSending: state.isSending,
                      editingMessage: _editingMessageIndex == null
                          ? null
                          : state.messages[_editingMessageIndex!],
                      onCancelEdit: _cancelEditingMessage,
                      onSend: () => _sendMessage(state),
                    ),
                  ],
                ),
                Positioned(
                  bottom: 92,
                  child: AnimatedScale(
                    key: const Key('chatbot-scroll-to-bottom-control'),
                    scale: _showScrollToBottomButton ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: IgnorePointer(
                      ignoring: !_showScrollToBottomButton,
                      child: Material(
                        key: const Key('chatbot-scroll-to-bottom-button'),
                        color: Colors.white,
                        elevation: 5,
                        shadowColor: const Color(0x30000000),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'เลื่อนไปข้อความล่าสุด',
                          onPressed: () => _scrollToBottom(force: true),
                          color: AppColors.primaryColor,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showRentMessage(RecommendedItem item) {
    final itemId = item.id;
    if (itemId != null) {
      AppRoutes.openItemDetail(context, itemId: itemId);
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('ไม่พบรหัสอุปกรณ์ กรุณาลองค้นหาใหม่')),
      );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _secondTimer;
  int _secondsElapsed = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _secondTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsElapsed += 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _secondTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _statusText {
    if (_secondsElapsed < 3) return 'กำลังคิด';
    if (_secondsElapsed < 6) return 'ค้นหาอุปกรณ์';
    return 'สรุปคำแนะนำ';
  }

  String get _timeText {
    if (_secondsElapsed < 60) return '$_secondsElapsed วิ';
    final m = _secondsElapsed ~/ 60;
    final s = _secondsElapsed % 60;
    return '$m นาที $s วิ';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 14,
              color: Color(0xFF8E8E93),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$_statusText ($_timeText)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Prompt',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF757575),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Semantics(
              label: 'AI กำลังคิด',
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final dotCount = 1 + (_controller.value * 3).floor();
                  final dots = switch (dotCount) {
                    1 => '.',
                    2 => '..',
                    _ => '...',
                  };
                  return SizedBox(
                    width: 18,
                    child: Text(
                      dots,
                      key: const Key('chatbot-thinking-dots'),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        color: Color(0xFF757575),
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    this.editingMessage,
    this.onCancelEdit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final ChatMessage? editingMessage;
  final VoidCallback? onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final horizontalInset = MediaQuery.sizeOf(context).width < 340
        ? 12.0
        : 20.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalInset,
        8,
        horizontalInset,
        14 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editingMessage != null)
                Container(
                  key: const Key('chatbot-editing-banner'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: AppColors.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'กำลังแก้ไขข้อความ',
                              style: TextStyle(
                                color: AppColors.primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              editingMessage!.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('chatbot-cancel-edit-button'),
                        tooltip: 'ยกเลิกแก้ไข',
                        onPressed: onCancelEdit,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: const Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ),
              Container(
                key: const Key('chatbot-composer'),
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x17000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('chatbot-message-field'),
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !isSending,
                        maxLength: 200,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        buildCounter:
                            (
                              context, {
                              required currentLength,
                              required isFocused,
                              required maxLength,
                            }) => null,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: editingMessage != null
                              ? 'แก้ไขข้อความ...'
                              : 'ถามข้อมูลเกี่ยวกับอุปกรณ์...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF8C8C94),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      key: const Key('chatbot-send-gradient'),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSending ? const Color(0xFFC8A5DE) : null,
                        gradient: isSending
                            ? null
                            : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.gradient1,
                                  AppColors.gradient2,
                                ],
                              ),
                      ),
                      child: IconButton(
                        key: const Key('chatbot-send-button'),
                        tooltip: editingMessage != null
                            ? 'บันทึกแก้ไข'
                            : 'ส่งข้อความ',
                        onPressed: isSending ? null : onSend,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          minimumSize: const Size.square(48),
                        ),
                        icon: Icon(
                          editingMessage != null
                              ? Icons.check_rounded
                              : Icons.arrow_upward_rounded,
                          size: 25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickRepliesBar extends StatelessWidget {
  const _QuickRepliesBar({required this.suggestions, required this.onSelect});

  final List<String> suggestions;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final horizontalInset = MediaQuery.sizeOf(context).width < 340
        ? 12.0
        : 20.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          height: 38,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: horizontalInset),
            itemCount: suggestions.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ActionChip(
                backgroundColor: Colors.white,
                elevation: 1.5,
                shadowColor: const Color(0x18000000),
                surfaceTintColor: Colors.transparent,
                side: const BorderSide(color: Color(0xFFE9D5FF), width: 1.2),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                avatar: const Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: AppColors.primaryColor,
                ),
                label: Text(
                  suggestion,
                  style: const TextStyle(
                    color: AppColors.primaryColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => onSelect(suggestion),
              );
            },
          ),
        ),
      ),
    );
  }
}

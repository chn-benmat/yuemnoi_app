import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../domain/entities/chat_message.dart';
import '../bloc/chatbot_bloc.dart';
import '../bloc/chatbot_event.dart';
import '../bloc/chatbot_state.dart';
import '../widgets/chat_message_bubble.dart';

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key});

  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen> {
  static const double _scrollButtonThreshold = 120;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final Set<int> _pendingAssistantAnimations = <int>{};
  final Set<int> _startedAssistantAnimations = <int>{};
  int _observedMessageCount = 0;
  bool _showScrollToBottomButton = false;

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

    context.read<ChatbotBloc>().add(ChatbotMessageSubmitted(query));
    _messageController.clear();
    _messageFocusNode.requestFocus();
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scrollController.hasClients) return;
      if (_showScrollToBottomButton && !force) return;

      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      if (!_scrollController.hasClients) return;

      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _keepLatestMessageVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final distanceFromBottom = position.maxScrollExtent - position.pixels;
      if (distanceFromBottom < 180) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  void _trackNewAssistantMessage(ChatbotState state) {
    if (state.messages.length > _observedMessageCount &&
        state.messages.last.role == ChatMessageRole.assistant) {
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
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            _trackNewAssistantMessage(state);
            _scrollToBottom();
            final errorMessage = state.errorMessage;
            if (errorMessage != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(errorMessage)));
            }
          },
          builder: (context, state) {
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
                                state.messages.length +
                                (state.isSending ? 1 : 0),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 24),
                            itemBuilder: (context, index) {
                              if (index == state.messages.length) {
                                return const _TypingIndicator();
                              }
                              return ChatMessageBubble(
                                key: ValueKey('chat-message-$index'),
                                message: state.messages[index],
                                onRentPressed: _showRentMessage,
                                animateAssistantResponse:
                                    _pendingAssistantAnimations.contains(
                                      index,
                                    ) &&
                                    !_startedAssistantAnimations.contains(
                                      index,
                                    ),
                                onAnimationStarted: () =>
                                    _markAssistantAnimationStarted(index),
                                onTextProgress: _keepLatestMessageVisible,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    _ChatComposer(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      isSending: state.isSending,
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(28),
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Semantics(
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
                  width: 38,
                  child: Text(
                    dots,
                    key: const Key('chatbot-thinking-dots'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                );
              },
            ),
          ),
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;

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
          child: Container(
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
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'ถามข้อมูลเกี่ยวกับอุปกรณ์...',
                      hintStyle: TextStyle(
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
                            colors: [AppColors.gradient1, AppColors.gradient2],
                          ),
                  ),
                  child: IconButton(
                    key: const Key('chatbot-send-button'),
                    tooltip: 'ส่งข้อความ',
                    onPressed: isSending ? null : onSend,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size.square(48),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 25),
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

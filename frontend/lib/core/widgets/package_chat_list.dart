import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as chat;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as chat_ui;

class PackageChatEntry {
  const PackageChatEntry({
    required this.id,
    required this.authorId,
    this.createdAt,
    this.revision,
  });
  final String id;
  final String authorId;
  final DateTime? createdAt;
  final Object? revision;
}

/// ให้ package จัดการรายการและการเปลี่ยนข้อความ โดยการ์ดธุรกรรมยังใช้กฎของ feature
class PackageChatList extends StatefulWidget {
  const PackageChatList({
    super.key,
    required this.entries,
    required this.itemBuilder,
    required this.scrollController,
    this.currentUserId = 'user',
    this.reversed = false,
    this.padding = EdgeInsets.zero,
  });

  final List<PackageChatEntry> entries;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController scrollController;
  final String currentUserId;
  final bool reversed;
  final EdgeInsets padding;

  @override
  State<PackageChatList> createState() => _PackageChatListState();
}

class _PackageChatListState extends State<PackageChatList> {
  late final chat.InMemoryChatController _controller;
  Map<String, int> _indices = {};

  List<chat.Message> _messages() {
    _indices = {
      for (var i = 0; i < widget.entries.length; i++) widget.entries[i].id: i,
    };
    return [
      for (var i = 0; i < widget.entries.length; i++)
        chat.Message.custom(
          id: widget.entries[i].id,
          authorId: widget.entries[i].authorId,
          createdAt: widget.entries[i].createdAt,
          metadata: {'revision': widget.entries[i].revision},
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _controller = chat.InMemoryChatController(messages: _messages());
  }

  @override
  void didUpdateWidget(covariant PackageChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_controller.setMessages(_messages()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: widget.padding.left,
      right: widget.padding.right,
    ),
    child: chat_ui.Chat(
      currentUserId: widget.currentUserId,
      resolveUser: (id) async => chat.User(id: id),
      chatController: _controller,
      backgroundColor: Colors.transparent,
      builders: chat.Builders(
        composerBuilder: (_) => const SizedBox.shrink(),
        emptyChatListBuilder: (_) => const SizedBox.shrink(),
        scrollToBottomBuilder: (_, _, _) => const SizedBox.shrink(),
        customMessageBuilder:
            (context, message, index, {required isSentByMe, groupStatus}) {
              final currentIndex = _indices[message.id];
              // รายการของ package อาจยังมีข้อความที่ถูกลบระหว่างประมวลผล diff
              return currentIndex == null
                  ? const SizedBox.shrink()
                  : widget.itemBuilder(context, currentIndex);
            },
        chatMessageBuilder:
            (
              context,
              message,
              index,
              animation,
              child, {
              isRemoved,
              required isSentByMe,
              groupStatus,
            }) => child,
        chatAnimatedListBuilder: (context, builder) => chat_ui.ChatAnimatedList(
          itemBuilder: builder,
          scrollController: widget.scrollController,
          reversed: widget.reversed,
          // รักษา animation หนึ่งเฟรมเพื่อให้ callback เลื่อนของ package จบก่อนรายการนิ่ง
          insertAnimationDuration: const Duration(milliseconds: 16),
          removeAnimationDuration: Duration.zero,
          topPadding: widget.padding.top,
          bottomPadding: widget.padding.bottom,
          handleSafeArea: false,
          initialScrollToEndMode: chat_ui.InitialScrollToEndMode.none,
          shouldScrollToEndWhenSendingMessage: false,
          shouldScrollToEndWhenAtBottom: false,
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../domain/entities/chat_conversation.dart';
import '../widgets/chat_avatar.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _sentMessages = [];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.conversation.name.split(' ').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      body: Column(
        children: [
          _ChatHeader(conversation: widget.conversation),
          Expanded(
            child: ListView(
              key: const ValueKey('chat-message-list'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
              children: [
                const Center(
                  child: Text(
                    'วันนี้',
                    style: TextStyle(
                      color: Color(0xFF6A6D70),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const _MessageBubble(
                  text:
                      'สวัสดีฉันเห็นว่าคุณสนใจอุปกรณ์กล้องถ่ายรูป มีสิ่งใดที่คุณอยากทราบเป็นพิเศษบ้างไหม?',
                ),
                const _TimeLabel(label: '09:41'),
                const SizedBox(height: 14),
                _MessageBubble(
                  text:
                      'สวัสดี$displayName ใช่ฉันอยากทราบว่าชุดเลนส์รวมอยู่ในอัตราค่าบริการรายวันหรือไม่ และเราจะนัดเจอกันเพื่อส่งมอบอุปกรณ์ได้ที่ไหน?',
                  isMine: true,
                ),
                const SizedBox(height: 14),
                const _MessageBubble(text: 'ส่งมอบที่ล็อบบี้บางแค'),
                const SizedBox(height: 14),
                const _MessageBubble(
                  text:
                      'เยี่ยมเลย โอเคสำหรับฉัน ฉันจะไปถึงที่นั่นประมาณ 10 โมงเช้าวันเสาร์',
                  isMine: true,
                ),
                const _TimeLabel(label: '09:50', alignEnd: true),
                const SizedBox(height: 10),
                _RentalRequestCard(senderName: displayName),
                for (final message in _sentMessages) ...[
                  const SizedBox(height: 14),
                  _MessageBubble(text: message, isMine: true),
                ],
              ],
            ),
          ),
          _MessageComposer(
            controller: _messageController,
            onSend: _sendMessage,
            onAttach: () => _showMessage('เลือกไฟล์แนบ (ข้อมูล mock)'),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _sentMessages.add(message);
      _messageController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primaryColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              IconButton(
                tooltip: 'ย้อนกลับ',
                onPressed: () => AppRoutes.pop(context),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 2),
              ChatAvatar(
                asset: conversation.avatarAsset,
                size: 46,
                isOnline: conversation.isOnline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      'กำลังใช้งานอยู่',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'โทรหา',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('เริ่มการโทร (ข้อมูล mock)')),
                ),
                icon: const Icon(
                  Icons.phone_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, this.isMine = false});

  final String text;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primaryColor : const Color(0xFFE1E4E5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(34),
            topRight: const Radius.circular(34),
            bottomLeft: Radius.circular(isMine ? 34 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 34),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMine ? Colors.white : const Color(0xFF595C60),
            fontSize: 15,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.label, this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF5F6264), fontSize: 9),
        ),
      ),
    );
  }
}

class _RentalRequestCard extends StatelessWidget {
  const _RentalRequestCard({required this.senderName});

  final String senderName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(34),
              bottom: Radius.circular(28),
            ),
            child: Stack(
              alignment: Alignment.bottomLeft,
              children: [
                AspectRatio(
                  aspectRatio: 2.05,
                  child: Image.asset(
                    'assets/images/chat_lens_set.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 7,
                        backgroundColor: AppColors.primaryColor,
                        child: Icon(
                          Icons.photo_camera_outlined,
                          color: Colors.white,
                          size: 9,
                        ),
                      ),
                      SizedBox(width: 5),
                      Text(
                        'ชุดเลนส์รวม',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Text(
              '$senderNameส่งรายละเอียด\nตรวจสอบอย่างละเอียดข้อมูลถูกต้องไหม',
              style: const TextStyle(
                color: Color(0xFF65686A),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              height: 38,
              child: FilledButton(
                key: const ValueKey('review-rental-button'),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('เปิดรายละเอียดรายการเช่า (ข้อมูล mock)'),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE0E3E4),
                  foregroundColor: const Color(0xFF5A5D67),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'ตรวจสอบ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F6F7),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 48,
              child: IconButton.filled(
                tooltip: 'แนบไฟล์',
                onPressed: onAttach,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4F5460),
                ),
                icon: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('chat-message-field'),
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'พิมพ์ข้อความ...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF7A8090),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox.square(
              dimension: 48,
              child: IconButton.filled(
                key: const ValueKey('send-message-button'),
                tooltip: 'ส่งข้อความ',
                onPressed: onSend,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  shadowColor: AppColors.primaryColor.withValues(alpha: 0.35),
                  elevation: 8,
                ),
                icon: const Icon(Icons.send_rounded, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

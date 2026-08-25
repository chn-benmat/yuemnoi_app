import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/user_presence_service.dart';
import '../../domain/entities/chat_conversation.dart';
import '../bloc/chat_detail_bloc.dart';
import '../bloc/chat_detail_state.dart';
import 'chat_avatar.dart';

class ChatDetailHeader extends StatelessWidget {
  const ChatDetailHeader({
    super.key,
    required this.conversation,
    required this.onPhoneCallPressed,
    this.isPhoneCallLoading = false,
  });

  final ChatConversation conversation;
  final VoidCallback onPhoneCallPressed;
  final bool isPhoneCallLoading;

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
              ValueListenableBuilder<Set<String>>(
                valueListenable:
                    UserPresenceService.instance.onlineUsersNotifier,
                builder: (context, onlineUsers, _) {
                  final isCurrentlyOnline =
                      conversation.isOnline ||
                      onlineUsers.contains(conversation.otherUserId);
                  return ChatAvatar(
                    asset: conversation.avatarAsset,
                    size: 46,
                    isOnline: isCurrentlyOnline,
                  );
                },
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
                    BlocBuilder<ChatDetailBloc, ChatDetailState>(
                      buildWhen: (p, c) =>
                          p.isOtherUserTyping != c.isOtherUserTyping,
                      builder: (context, state) {
                        if (state.isOtherUserTyping) {
                          return const Text(
                            'กำลังพิมพ์...',
                            key: ValueKey('chat-header-typing-status'),
                            style: TextStyle(
                              color: Color(0xFF6EE7B7),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }
                        return ValueListenableBuilder<Set<String>>(
                          valueListenable:
                              UserPresenceService.instance.onlineUsersNotifier,
                          builder: (context, onlineUsers, _) {
                            final isCurrentlyOnline =
                                conversation.isOnline ||
                                onlineUsers.contains(conversation.otherUserId);
                            return Text(
                              isCurrentlyOnline ? 'ออนไลน์' : 'ออฟไลน์',
                              key: const ValueKey('chat-header-online-status'),
                              style: TextStyle(
                                color: isCurrentlyOnline
                                    ? const Color(0xFF6EE7B7)
                                    : Colors.white60,
                                fontSize: 12,
                                fontWeight: isCurrentlyOnline
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('chat-phone-call-button'),
                tooltip: 'โทรศัพท์',
                onPressed: isPhoneCallLoading ? null : onPhoneCallPressed,
                icon: isPhoneCallLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.call_rounded, color: Colors.white),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/user_presence_service.dart';
import '../../domain/entities/chat_conversation.dart';
import '../bloc/chat_detail_bloc.dart';
import '../bloc/chat_detail_state.dart';
import 'chat_avatar.dart';
import '../../../profile/presentation/pages/profile/user_profile_view_screen.dart';

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

  void _openProfile(BuildContext context) {
    if (conversation.isOtherUserUnavailable ||
        conversation.otherUserId.isEmpty) {
      return;
    }
    AppRoutes.openUserProfile(
      context,
      args: UserProfileViewArgs(
        userId: conversation.otherUserId,
        displayName: conversation.name,
        avatarUrl: conversation.avatarAsset,
      ),
    );
  }

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
              if (conversation.isOtherUserUnavailable)
                ChatAvatar(asset: conversation.avatarAsset, size: 46)
              else
                ValueListenableBuilder<Set<String>>(
                  valueListenable:
                      UserPresenceService.instance.onlineUsersNotifier,
                  builder: (context, onlineUsers, _) {
                    final isCurrentlyOnline =
                        conversation.isOnline ||
                        onlineUsers.contains(conversation.otherUserId);
                    return InkWell(
                      key: const ValueKey('chat-profile-avatar'),
                      onTap: () => _openProfile(context),
                      child: ChatAvatar(
                        asset: conversation.avatarAsset,
                        size: 46,
                        isOnline: isCurrentlyOnline,
                      ),
                    );
                  },
                ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _openProfile(context),
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
                      if (!conversation.isOtherUserUnavailable)
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
                              valueListenable: UserPresenceService
                                  .instance
                                  .onlineUsersNotifier,
                              builder: (context, onlineUsers, _) {
                                final isCurrentlyOnline =
                                    conversation.isOnline ||
                                    onlineUsers.contains(
                                      conversation.otherUserId,
                                    );
                                return Text(
                                  isCurrentlyOnline ? 'ออนไลน์' : 'ออฟไลน์',
                                  key: const ValueKey(
                                    'chat-header-online-status',
                                  ),
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
              ),
              if (!conversation.isOtherUserUnavailable)
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

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../domain/entities/chat_conversation.dart';
import '../mock/chat_mock_data.dart';
import '../widgets/chat_avatar.dart';

enum _ConversationFilter { all, owner, renter }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _searchController = TextEditingController();
  _ConversationFilter _filter = _ConversationFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatConversation> get _visibleConversations {
    final query = _searchController.text.trim().toLowerCase();
    return ChatMockData.conversations.where((conversation) {
      final matchesQuery =
          query.isEmpty ||
          conversation.name.toLowerCase().contains(query) ||
          conversation.preview.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        _ConversationFilter.all => true,
        _ConversationFilter.owner =>
          conversation.role == ChatParticipantRole.owner,
        _ConversationFilter.renter =>
          conversation.role == ChatParticipantRole.renter,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = _visibleConversations;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('chat-search-field'),
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ค้นหา',
                hintStyle: const TextStyle(color: Color(0xFF777A7C)),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF6D7072),
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'ล้างการค้นหา',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: const Color(0xFFF0F1F2),
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'ทั้งหมด',
                    selected: _filter == _ConversationFilter.all,
                    onTap: () => _setFilter(_ConversationFilter.all),
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    label: 'ผู้ปล่อยเช่า',
                    selected: _filter == _ConversationFilter.owner,
                    onTap: () => _setFilter(_ConversationFilter.owner),
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    label: 'ผู้เช่า',
                    selected: _filter == _ConversationFilter.renter,
                    onTap: () => _setFilter(_ConversationFilter.renter),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: conversations.isEmpty
                  ? const _EmptyConversations()
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: conversations.length,
                      separatorBuilder: (_, _) => const SizedBox.shrink(),
                      itemBuilder: (context, index) =>
                          _ConversationCard(conversation: conversations[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _setFilter(_ConversationFilter filter) {
    setState(() {
      _filter = filter;
    });
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primaryColor : const Color(0xFFF0F1F2),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 11),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF4C4F51),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('conversation-${conversation.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            AppRoutes.openConversation(context, conversation: conversation),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              ChatAvatar(
                asset: conversation.avatarAsset,
                size: 64,
                isOnline: conversation.isOnline,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF303234),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          conversation.timeLabel,
                          style: TextStyle(
                            color: conversation.hasUnreadMessage
                                ? AppColors.primaryColor
                                : const Color(0xFF858789),
                            fontSize: 11,
                            fontWeight: conversation.hasUnreadMessage
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF585B5D),
                        fontSize: 13,
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

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 48, color: Color(0xFFB5B7B9)),
          SizedBox(height: 12),
          Text(
            'ไม่พบการสนทนา',
            style: TextStyle(color: Color(0xFF777A7C), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

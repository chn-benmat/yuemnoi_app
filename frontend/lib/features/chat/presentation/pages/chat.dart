import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/chat_pin_service.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/usecases/get_conversations_usecase.dart';
import '../bloc/chat_list_bloc.dart';
import '../bloc/chat_list_event.dart';
import '../bloc/chat_list_state.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_list_loading_skeleton.dart';
import '../widgets/conversation_action_sheet.dart';
import '../widgets/guest_chat_view.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';

enum _ConversationFilter { all, owner, renter }

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, this.chatListBloc});

  final ChatListBloc? chatListBloc;

  @override
  Widget build(BuildContext context) {
    if (chatListBloc != null) {
      return BlocProvider.value(
        value: chatListBloc!,
        child: const _ChatScreenContent(),
      );
    }

    try {
      final existingBloc = BlocProvider.of<ChatListBloc>(
        context,
        listen: false,
      );
      return BlocProvider.value(
        value: existingBloc,
        child: const _ChatScreenContent(),
      );
    } catch (_) {}

    final repository = ChatRepositoryImpl(
      remoteDataSource: ChatRemoteDataSource(),
    );

    return BlocProvider(
      create: (context) =>
          ChatListBloc(getConversations: GetConversationsUseCase(repository))
            ..add(const LoadChatListStarted()),
      child: const _ChatScreenContent(),
    );
  }
}

class _ChatScreenContent extends StatefulWidget {
  const _ChatScreenContent();

  @override
  State<_ChatScreenContent> createState() => _ChatScreenContentState();
}

class _ChatScreenContentState extends State<_ChatScreenContent> {
  final _searchController = TextEditingController();
  _ConversationFilter _filter = _ConversationFilter.all;
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _searchedUsers = [];
  bool _isSearchingUsers = false;

  @override
  void initState() {
    super.initState();
    ChatPinService.instance.pinNotifier.addListener(_onPinChanged);
  }

  @override
  void dispose() {
    ChatPinService.instance.pinNotifier.removeListener(_onPinChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onPinChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchedUsers = [];
          _isSearchingUsers = false;
        });
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchUsersFromSupabase(query);
    });
  }

  Future<void> _searchUsersFromSupabase(String query) async {
    if (!SupabaseConfig.isInitialized) return;
    if (mounted) setState(() => _isSearchingUsers = true);
    try {
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
      final results = await SupabaseConfig.client
          .from('public_profile_v')
          .select('user_id, display_name, user_image_url, email, is_online')
          .or('display_name.ilike.%$query%,email.ilike.%$query%')
          .limit(8);

      if (!mounted) return;
      final list = (results as List)
          .cast<Map<String, dynamic>>()
          .where((u) => u['user_id'] != currentUserId)
          .toList();

      setState(() {
        _searchedUsers = list;
        _isSearchingUsers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isSearchingUsers = false);
    }
  }

  Future<void> _startChatWithUser(Map<String, dynamic> user) async {
    final otherUserId = user['user_id']?.toString() ?? '';
    if (otherUserId.isEmpty) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กำลังเปิดบทสนทนา...'),
          duration: Duration(seconds: 1),
        ),
      );
      final conversation = await ChatRemoteDataSource().getOrCreateConversation(
        ownerId: otherUserId,
      );
      if (!mounted) return;
      AppRoutes.openConversation(context, conversation: conversation).then((_) {
        if (mounted) {
          context.read<ChatListBloc>().add(const ChatListRefreshed());
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถเริ่มแชทได้: $e')),
      );
    }
  }

  List<ChatConversation> _filterConversations(List<ChatConversation> conversations) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = conversations.where((conversation) {
      final matchesQuery = query.isEmpty ||
          conversation.name.toLowerCase().contains(query) ||
          conversation.preview.toLowerCase().contains(query) ||
          (conversation.itemName?.toLowerCase().contains(query) ?? false);

      final matchesFilter = switch (_filter) {
        _ConversationFilter.all => true,
        _ConversationFilter.owner =>
          conversation.role == ChatParticipantRole.owner,
        _ConversationFilter.renter =>
          conversation.role == ChatParticipantRole.renter,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    // จัดเรียงให้แชทที่ถูกปักหมุดอยู่บนสุดเสมอ (จำกัดปักหมุดได้ 1 แชท)
    final pinnedId = ChatPinService.instance.pinnedConversationId;
    if (pinnedId != null) {
      filtered.sort((a, b) {
        if (a.id == pinnedId) return -1;
        if (b.id == pinnedId) return 1;
        return 0;
      });
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.isAuthenticated) {
      return const GuestChatView();
    }

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
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'ค้นหาการสนทนา, บัญชี หรือชื่ออุปกรณ์',
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
                          _onSearchChanged('');
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
              child: BlocBuilder<ChatListBloc, ChatListState>(
                builder: (context, state) {
                  if (state.status == ChatListStatus.loading &&
                      state.conversations.isEmpty) {
                    return const ChatListLoadingSkeleton();
                  }

                  if (state.status == ChatListStatus.failure &&
                      state.conversations.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            state.errorMessage ?? 'โหลดรายการแชทไม่สำเร็จ',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF777A7C)),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => context.read<ChatListBloc>().add(
                              const LoadChatListStarted(),
                            ),
                            child: const Text('ลองใหม่'),
                          ),
                        ],
                      ),
                    );
                  }

                  final visibleConversations = _filterConversations(
                    state.conversations,
                  );

                  final isSearching = _searchController.text.trim().isNotEmpty;
                  final activeUserIds =
                      visibleConversations.map((c) => c.otherUserId).toSet();
                  final discoveredUsers = _searchedUsers
                      .where(
                        (u) =>
                            !activeUserIds.contains(u['user_id']?.toString()),
                      )
                      .toList();

                  if (visibleConversations.isEmpty && discoveredUsers.isEmpty) {
                    if (isSearching) {
                      if (_isSearchingUsers) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryColor,
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: () async {
                          context.read<ChatListBloc>().add(
                            const ChatListRefreshed(),
                          );
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 120),
                            _EmptySearch(query: _searchController.text.trim()),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        context.read<ChatListBloc>().add(
                          const ChatListRefreshed(),
                        );
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          _EmptyConversations(),
                        ],
                      ),
                    );
                  }

                  if (isSearching && discoveredUsers.isNotEmpty) {
                    return RefreshIndicator(
                      color: AppColors.primaryColor,
                      onRefresh: () async {
                        context.read<ChatListBloc>().add(
                          const ChatListRefreshed(),
                        );
                      },
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (visibleConversations.isNotEmpty) ...[
                            _buildSectionHeader(
                              'การสนทนา (${visibleConversations.length})',
                            ),
                            ...visibleConversations.map(
                              (c) => _ConversationCard(
                                key: ValueKey('card-${c.id}'),
                                conversation: c,
                              ),
                            ),
                            const Divider(
                              height: 24,
                              thickness: 1,
                              color: Color(0xFFF0F1F2),
                            ),
                          ],
                          _buildSectionHeader(
                            'บัญชีผู้ใช้ในระบบ (${discoveredUsers.length})',
                          ),
                          ...discoveredUsers.map(
                            (u) => _DiscoveredUserCard(
                              user: u,
                              onTap: () => _startChatWithUser(u),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.primaryColor,
                    onRefresh: () async {
                      context.read<ChatListBloc>().add(
                        const ChatListRefreshed(),
                      );
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: visibleConversations.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: Color(0xFFEBEBEF),
                        indent: 84,
                      ),
                      itemBuilder: (context, index) => _ConversationCard(
                        key: ValueKey('card-${visibleConversations[index].id}'),
                        conversation: visibleConversations[index],
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF858789),
          letterSpacing: 0.2,
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
  const _ConversationCard({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.hasUnreadMessage;
    final isPinned = ChatPinService.instance.isPinned(conversation.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('conversation-${conversation.id}'),
        onLongPress: () {
          ConversationActionSheet.show(
            context,
            conversation: conversation,
            onTogglePin: () async {
              await ChatPinService.instance.togglePin(conversation.id);
            },
            onDelete: () {
              context.read<ChatListBloc>().add(
                    ChatConversationDeleted(conversation.id),
                  );
            },
          );
        },
        onTap: () {
          // 1. อัปเดตสถานะอ่านแล้วทันทีใน UI และส่งคำสั่งไป Supabase ในเบื้องหลัง
          context.read<ChatListBloc>().add(
            ChatConversationMarkedAsRead(conversation.id),
          );
          ChatRemoteDataSource().markMessagesAsRead(
            conversationId: conversation.id,
          );

          // 2. เปิดหน้าห้องแชทขึ้นมาทันที 0ms แบบลื่นไหลเหมือน Messenger / LINE
          AppRoutes.openConversation(context, conversation: conversation).then((
            _,
          ) {
            if (context.mounted) {
              context.read<ChatListBloc>().add(const ChatListRefreshed());
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ChatAvatar(
                asset: conversation.avatarAsset,
                size: 60,
                isOnline: conversation.isOnline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  conversation.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: const Color(0xFF222427),
                                    fontSize: 16,
                                    fontWeight: hasUnread
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isPinned) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.push_pin_rounded,
                                  size: 15,
                                  color: AppColors.primaryColor,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          conversation.timeLabel,
                          style: TextStyle(
                            color: hasUnread
                                ? AppColors.primaryColor
                                : const Color(0xFF858789),
                            fontSize: 11,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread
                                  ? const Color(0xFF1E2022)
                                  : const Color(0xFF858789),
                              fontSize: 13,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            key: const ValueKey('unread-conversation-dot'),
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
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
          Icon(Icons.forum_outlined, size: 52, color: Color(0xFFB5B7B9)),
          SizedBox(height: 14),
          Text(
            'ยังไม่มีการสนทนา',
            style: TextStyle(
              color: Color(0xFF5A5D60),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'เมื่อคุณกด "แชท" กับผู้ปล่อยเช่าในหน้าอุปกรณ์\nรายการแชทจะปรากฏที่นี่',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8D9094),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 52,
              color: Color(0xFFB5B7B9),
            ),
            const SizedBox(height: 14),
            const Text(
              'ไม่พบบัญชีหรือการสนทนา',
              style: TextStyle(
                color: Color(0xFF5A5D60),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ไม่พบผลการค้นหาสำหรับ "$query"\nลองตรวจสอบตัวสะกดหรือค้นหาด้วยชื่ออื่น',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8D9094),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredUserCard extends StatelessWidget {
  const _DiscoveredUserCard({
    required this.user,
    required this.onTap,
  });

  final Map<String, dynamic> user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final displayName = user['display_name']?.toString().trim();
    final email = user['email']?.toString().trim() ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (emailName.isNotEmpty ? emailName : 'ผู้ใช้งาน Yuemnoi');
    final avatar = user['user_image_url']?.toString().trim() ?? '';
    final isOnline = user['is_online'] == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ChatAvatar(
                asset: avatar.isEmpty ? 'assets/images/user.png' : avatar,
                size: 52,
                isOnline: isOnline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF222427),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF858789),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryColor.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('ทักแชท', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

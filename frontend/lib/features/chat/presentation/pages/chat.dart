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

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';

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
  bool _oldestFirst = false;
  bool _unreadOnly = false;

  void _showFilters() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ตัวกรองแชท',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                const Text(
                  'เรียงลำดับ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final oldest in [false, true])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(oldest ? 'เก่าสุด' : 'ใหม่ล่าสุด'),
                    leading: Icon(
                      _oldestFirst == oldest
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: AppColors.primaryColor,
                    ),
                    selected: _oldestFirst == oldest,
                    onTap: () {
                      setState(() => _oldestFirst = oldest);
                      updateSheet(() {});
                    },
                  ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ยังไม่ได้อ่าน'),
                  value: _unreadOnly,
                  onChanged: (value) {
                    setState(() => _unreadOnly = value);
                    updateSheet(() {});
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('เสร็จสิ้น'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    ChatPinService.instance.pinNotifier.addListener(_onPinChanged);
  }

  @override
  void dispose() {
    ChatPinService.instance.pinNotifier.removeListener(_onPinChanged);

    _searchController.dispose();
    super.dispose();
  }

  void _onPinChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    setState(() {});
  }

  List<ChatConversation> _filterConversations(
    List<ChatConversation> conversations,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = conversations.where((conversation) {
      final matchesQuery =
          query.isEmpty ||
          conversation.name.toLowerCase().contains(query) ||
          conversation.preview.toLowerCase().contains(query) ||
          (conversation.itemName?.toLowerCase().contains(query) ?? false);

      return matchesQuery && (!_unreadOnly || conversation.hasUnreadMessage);
    }).toList();

    // จัดเรียงให้แชทที่ถูกปักหมุดอยู่บนสุดเสมอ (จำกัดปักหมุดได้ 1 แชท)
    final pinnedId = ChatPinService.instance.pinnedConversationId;
    final originalOrder = {
      for (var i = 0; i < conversations.length; i++) conversations[i].id: i,
    };
    filtered.sort((a, b) {
      if (pinnedId != null) {
        if (a.id == pinnedId) return -1;
        if (b.id == pinnedId) return 1;
      }
      final byTime = (b.lastMessageAt?.microsecondsSinceEpoch ?? 0).compareTo(
        a.lastMessageAt?.microsecondsSinceEpoch ?? 0,
      );
      final order = byTime == 0
          ? originalOrder[a.id]!.compareTo(originalOrder[b.id]!)
          : byTime;
      return _oldestFirst ? -order : order;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    AuthBloc? authBloc;
    try {
      authBloc = BlocProvider.of<AuthBloc>(context);
    } catch (_) {}

    if (authBloc != null) {
      return BlocConsumer<AuthBloc, AuthState>(
        listener: (context, authState) {
          if (authState is LoginSuccess || authState is GoogleLoginSuccess) {
            context.read<ChatListBloc>().add(const LoadChatListStarted());
            if (mounted) setState(() {});
          } else if (authState is AuthInitial) {
            if (mounted) setState(() {});
          }
        },
        builder: (context, authState) {
          final isAuthenticated =
              AuthSession.isAuthenticated ||
              authState is LoginSuccess ||
              authState is GoogleLoginSuccess;

          if (!isAuthenticated) {
            return GuestChatView(
              onLoginSuccess: () {
                if (mounted) setState(() {});
              },
            );
          }

          return _buildChatMainView(context);
        },
      );
    }

    if (!AuthSession.isAuthenticated) {
      return GuestChatView(
        onLoginSuccess: () {
          if (mounted) setState(() {});
        },
      );
    }

    return _buildChatMainView(context);
  }

  Widget _buildChatMainView(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'แชท',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: Color(0xFF292235),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'คุยรายละเอียด แล้วนัดรับของกัน',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Color(0xFF665D73),
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              key: const ValueKey('chat-search-field'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'ค้นหา',
                hintStyle: const TextStyle(color: Color(0xFF777A7C)),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF6D7072),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        tooltip: 'ล้างการค้นหา',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    IconButton(
                      key: const ValueKey('chat-filter-button'),
                      tooltip: 'ตัวกรองแชท',
                      onPressed: _showFilters,
                      icon: Icon(
                        Icons.tune_rounded,
                        color: _oldestFirst || _unreadOnly
                            ? AppColors.primaryColor
                            : const Color(0xFF6D7072),
                      ),
                    ),
                  ],
                ),
                filled: true,
                fillColor: const Color(0xFFF0F1F2),
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: BlocBuilder<ChatListBloc, ChatListState>(
                builder: (context, state) {
                  if ((state.status == ChatListStatus.loading ||
                          state.status == ChatListStatus.initial) &&
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
                  if (visibleConversations.isEmpty) {
                    if (isSearching) {
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
                        children: [
                          const SizedBox(height: 120),
                          if (_unreadOnly)
                            const Center(
                              child: Text('ไม่มีแชทที่ยังไม่ได้อ่าน'),
                            )
                          else
                            const _EmptyConversations(),
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
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.hasUnreadMessage;
    final isPinned = ChatPinService.instance.isPinned(conversation.id);

    return Material(
      color: hasUnread ? const Color(0xFFF5EFFD) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
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
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.25,
                          ),
                          child: Text(
                            conversation.timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread
                                  ? AppColors.primaryColor
                                  : const Color(0xFF706779),
                              fontSize: 12,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
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
                                  : const Color(0xFF706779),
                              fontSize: 14,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Semantics(
                            label: 'มีข้อความที่ยังไม่ได้อ่าน',
                            child: Container(
                              key: const ValueKey('unread-conversation-dot'),
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                              ),
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
              fontSize: 14,
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
              'ไม่พบการสนทนา',
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
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/usecases/fetch_messages_usecase.dart';
import '../../domain/usecases/mark_messages_as_read_usecase.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import '../../domain/usecases/stream_messages_usecase.dart';
import '../../domain/usecases/upload_chat_image_usecase.dart';
import '../bloc/chat_detail_bloc.dart';
import '../bloc/chat_detail_event.dart';
import '../bloc/chat_detail_state.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_item_header_card.dart';

class ChatDetailScreen extends StatelessWidget {
  const ChatDetailScreen({
    super.key,
    required this.conversation,
    this.chatDetailBloc,
  });

  final ChatConversation conversation;
  final ChatDetailBloc? chatDetailBloc;

  @override
  Widget build(BuildContext context) {
    if (chatDetailBloc != null) {
      return BlocProvider.value(
        value: chatDetailBloc!,
        child: _ChatDetailView(conversation: conversation),
      );
    }

    final repository = ChatRepositoryImpl(
      remoteDataSource: ChatRemoteDataSource(),
    );

    return BlocProvider(
      create: (context) => ChatDetailBloc(
        conversationId: conversation.id,
        streamMessages: StreamMessagesUseCase(repository),
        sendMessage: SendChatMessageUseCase(repository),
        fetchMessages: FetchMessagesUseCase(repository),
        uploadChatImage: UploadChatImageUseCase(repository),
        markMessagesAsRead: MarkMessagesAsReadUseCase(repository),
      ),
      child: _ChatDetailView(conversation: conversation),
    );
  }
}

class _ChatDetailView extends StatefulWidget {
  const _ChatDetailView({required this.conversation});

  final ChatConversation conversation;

  @override
  State<_ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<_ChatDetailView> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    context.read<ChatDetailBloc>().add(
      ChatMessagesSubscriptionRequested(widget.conversation.id),
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 40) {
      final bloc = context.read<ChatDetailBloc>();
      if (!bloc.state.hasReachedMax &&
          !bloc.state.isFetchingOlder &&
          bloc.state.messages.length >= 25) {
        bloc.add(ChatOlderMessagesRequested(widget.conversation.id));
      }
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 100;
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (animate) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<ChatDetailBloc>().add(
      ChatMessageSent(
        conversationId: widget.conversation.id,
        message: text,
      ),
    );

    _messageController.clear();
    _scrollToBottom(animate: true);
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (pickedFile == null || !mounted) return;

      final rawBytes = await pickedFile.readAsBytes();
      final compressedBytes = await FlutterImageCompress.compressWithList(
        rawBytes,
        minWidth: 1024,
        minHeight: 1024,
        quality: 80,
      );

      if (!mounted) return;

      context.read<ChatDetailBloc>().add(
        ChatImageUploadedAndSent(
          conversationId: widget.conversation.id,
          imageBytes: compressedBytes,
          fileName: pickedFile.name,
        ),
      );
      _scrollToBottom(animate: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเลือกรูปภาพได้')),
        );
      }
    }
  }

  void _showImagePickerSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primaryColor),
                  title: const Text('ถ่ายรูปจากกล้อง', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndSendImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: AppColors.primaryColor),
                  title: const Text('เลือกจากคลังรูปภาพ', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndSendImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      body: Column(
        children: [
          _ChatHeader(conversation: widget.conversation),
          if (widget.conversation.itemId != null &&
              widget.conversation.itemName != null)
            ChatItemHeaderCard(
              itemId: widget.conversation.itemId!,
              itemName: widget.conversation.itemName!,
              itemImageUrl: widget.conversation.itemImageUrl,
              itemPrice: widget.conversation.itemPrice,
              itemRentalType: widget.conversation.itemRentalType,
            ),
          Expanded(
            child: BlocConsumer<ChatDetailBloc, ChatDetailState>(
              listener: (context, state) {
                if (state.status == ChatDetailStatus.failure &&
                    state.errorMessage != null) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
                } else if (state.status == ChatDetailStatus.success &&
                    state.messages.isNotEmpty) {
                  if (state.messages.length > _lastMessageCount) {
                    final lastMsg = state.messages.last;
                    if (lastMsg.isMine || _isNearBottom()) {
                      _scrollToBottom(animate: true);
                    }
                  }
                  _lastMessageCount = state.messages.length;
                }
              },
              builder: (context, state) {
                if (state.messages.isEmpty) {
                  // ถ้ามีการคุยไว้ก่อนแล้ว และกำลังรอสตรีมส่งข้อมูลข้อความเข้ามา
                  // แสดง Skeleton Shimmer Animation
                  if (_hasChatHistory &&
                      state.status != ChatDetailStatus.success) {
                    return const _ChatSkeletonLoadingView();
                  }
                  return _EmptyChatView(conversation: widget.conversation);
                }

                return ListView.builder(
                  key: const ValueKey('chat-message-list'),
                  reverse: true,
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final actualIndex = state.messages.length - 1 - index;
                    final message = state.messages[actualIndex];
                    final showTimeDivider = _shouldShowTimeDivider(
                      state.messages,
                      actualIndex,
                    );
                    final previousDate = actualIndex > 0
                        ? state.messages[actualIndex - 1].createdAt
                        : null;
                    final showAvatar = _shouldShowAvatar(
                      state.messages,
                      actualIndex,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showTimeDivider)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                _formatTimeDivider(
                                  message.createdAt,
                                  previousDate,
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF8A8E92),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        _MessageBubble(
                          message: message,
                          otherAvatarAsset: widget.conversation.avatarAsset,
                          showAvatar: showAvatar,
                          onCallBack: () {
                            AppRoutes.openVoiceCall(
                              context,
                              conversation: widget.conversation,
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          BlocBuilder<ChatDetailBloc, ChatDetailState>(
            buildWhen: (prev, curr) => prev.isUploadingImage != curr.isUploadingImage,
            builder: (context, state) {
              if (!state.isUploadingImage) return const SizedBox.shrink();
              return Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: const Row(
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'กำลังอัปโหลดรูปภาพ...',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6A6D70)),
                    ),
                  ],
                ),
              );
            },
          ),
          _MessageComposer(
            controller: _messageController,
            onSend: _sendMessage,
            onAttach: _showImagePickerSheet,
          ),
        ],
      ),
    );
  }

  bool get _hasChatHistory =>
      widget.conversation.preview.trim().isNotEmpty &&
      widget.conversation.preview.trim() != 'เริ่มการสนทนา' &&
      widget.conversation.preview.trim() != 'ยังไม่มีข้อความ';

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  bool _shouldShowTimeDivider(List<ChatMessage> messages, int index) {
    if (index == 0) return true;
    final prev = messages[index - 1];
    final curr = messages[index];
    if (_isDifferentDay(prev.createdAt, curr.createdAt)) return true;
    return curr.createdAt.difference(prev.createdAt).inMinutes.abs() >= 15;
  }

  bool _shouldShowAvatar(List<ChatMessage> messages, int index) {
    final curr = messages[index];
    if (curr.isMine) return false;
    if (index == messages.length - 1) return true;
    final next = messages[index + 1];
    if (next.isMine || next.message.startsWith('📞')) return true;
    if (_shouldShowTimeDivider(messages, index + 1)) return true;
    return false;
  }

  String _formatTimeDivider(DateTime date, DateTime? previousDate) {
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(date);

    if (previousDate == null || _isDifferentDay(previousDate, date)) {
      if (now.year == date.year &&
          now.month == date.month &&
          now.day == date.day) {
        return '$timeStr น.';
      } else if (now.year == date.year &&
          now.month == date.month &&
          now.day - date.day == 1) {
        return 'เมื่อวาน $timeStr น.';
      } else if (now.year == date.year) {
        final dayStr = DateFormat('d MMM', 'th').format(date);
        return '$dayStr $timeStr น.';
      } else {
        final fullDateStr = DateFormat('d/M/yy').format(date);
        return '$fullDateStr $timeStr น.';
      }
    }

    return '$timeStr น.';
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
                    Text(
                      conversation.isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                      key: const ValueKey('chat-header-online-status'),
                      style: TextStyle(
                        color: conversation.isOnline
                            ? const Color(0xFF6EE7B7)
                            : Colors.white60,
                        fontSize: 12,
                        fontWeight: conversation.isOnline
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // ปุ่มโทรในแอป (In-App Voice Call) อยู่ด้านขวาของชื่อ
              IconButton(
                key: const ValueKey('chat-call-button'),
                tooltip: 'โทรในแอป',
                onPressed: () {
                  AppRoutes.openVoiceCall(context, conversation: conversation);
                },
                icon: const Icon(
                  Icons.phone_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  const _EmptyChatView({required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatAvatar(
              asset: conversation.avatarAsset,
              size: 72,
              isOnline: conversation.isOnline,
            ),
            const SizedBox(height: 16),
            Text(
              conversation.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2C2D30),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              conversation.itemName != null
                  ? 'เริ่มพูดคุยเกี่ยวกับ "${conversation.itemName}"'
                  : 'ยังไม่มีประวัติการสนทนา เริ่มพิมพ์ข้อความได้เลย',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7A8090),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatSkeletonLoadingView extends StatefulWidget {
  const _ChatSkeletonLoadingView();

  @override
  State<_ChatSkeletonLoadingView> createState() =>
      _ChatSkeletonLoadingViewState();
}

class _ChatSkeletonLoadingViewState extends State<_ChatSkeletonLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              colors: const [
                Color(0xFFE2E4E8),
                Color(0xFFF7F8FA),
                Color(0xFFE2E4E8),
              ],
              stops: const [0.1, 0.5, 0.9],
              transform:
                  _SlidingGradientTransform(slidePercent: _controller.value),
            ).createShader(bounds);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Centered date divider skeleton
                Center(
                  child: Container(
                    width: 70,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Incoming bubble 1
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 170,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Incoming bubble 2 (shorter)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 36),
                    Container(
                      width: 110,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Outgoing bubble 1 (right)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 210,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Outgoing bubble 2 (right shorter)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 130,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Incoming bubble 3
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 190,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Outgoing image skeleton (right)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 180,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0.0,
      0.0,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.otherAvatarAsset,
    this.showAvatar = false,
    this.onCallBack,
  });

  final ChatMessage message;
  final String? otherAvatarAsset;
  final bool showAvatar;
  final VoidCallback? onCallBack;

  static (String title, String subtitle, IconData icon) _parseCallLog(String raw) {
    final text = raw.replaceFirst('📞 ', '').trim();
    String title = 'โทรด้วยเสียง';
    IconData icon = Icons.phone_rounded;

    if (text.contains('วิดีโอ')) {
      title = 'วิดีโอคอล';
      icon = Icons.videocam_rounded;
    }

    String subtitle = 'โทรด้วยเสียง';
    if (text.contains('ไม่ได้รับสาย')) {
      subtitle = 'ไม่ได้รับสาย';
      icon = Icons.phone_missed_rounded;
    } else if (text.contains('ยกเลิก') || text.contains('วางสาย')) {
      subtitle = 'วางสายแล้ว';
      icon = Icons.phone_disabled_rounded;
    } else if (text.contains('ปฏิเสธ')) {
      subtitle = 'สายถูกปฏิเสธ';
      icon = Icons.phone_disabled_rounded;
    } else if (text.contains('สนทนา') || text.contains('•')) {
      final durationInParen = RegExp(r'\(สนทนา\s+([^)]+)\)').firstMatch(text);
      if (durationInParen != null) {
        subtitle = durationInParen.group(1)!.trim();
      } else {
        final parts = text.split('•');
        var dur = parts.length > 1 ? parts.last.trim() : text;
        dur = dur.replaceFirst('สนทนา', '').trim();
        subtitle = dur.isNotEmpty ? dur : 'วางสายแล้ว';
      }
    } else {
      subtitle = text;
    }

    return (title, subtitle, icon);
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final isCallLog = message.message.startsWith('📞');

    if (isCallLog) {
      final (title, subtitle, icon) = _parseCallLog(message.message);

      final callCard = Container(
        width: 220,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onCallBack,
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  child: const Text(
                    'โทรกลับ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      if (isMine) {
        return Align(
          alignment: Alignment.centerRight,
          child: callCard,
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: ChatAvatar(
                asset: otherAvatarAsset ?? 'assets/images/user1.png',
                size: 28,
                showStatus: false,
              ),
            )
          else
            const SizedBox(width: 36),
          Flexible(child: callCard),
        ],
      );
    }

    final hasImage = message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasText = message.message.isNotEmpty && message.message != '📷 ส่งรูปภาพ';

    // ถ้ามีรูปภาพอย่างเดียว -> แสดงเป็นการ์ดรูปภาพมุมมนขนาดกำลังดี (เห็นภาพเต็ม ไม่ครอบรูป)
    if (hasImage && !hasText) {
      final imageCard = Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          maxHeight: 300,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            onTap: () => _showFullImage(context, message.imageUrl!),
            child: Hero(
              tag: message.imageUrl!,
              child: CachedNetworkImage(
                imageUrl: message.imageUrl!,
                fit: BoxFit.contain,
                placeholder: (context, url) => Container(
                  width: 220,
                  height: 220,
                  color: const Color(0xFFE5E7EB),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 220,
                  height: 220,
                  color: const Color(0xFFE5E7EB),
                  child: const Icon(Icons.broken_image_rounded, size: 40),
                ),
              ),
            ),
          ),
        ),
      );

      if (isMine) {
        return Align(
          alignment: Alignment.centerRight,
          child: imageCard,
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: ChatAvatar(
                asset: otherAvatarAsset ?? 'assets/images/user1.png',
                size: 28,
                showStatus: false,
              ),
            )
          else
            const SizedBox(width: 36),
          Flexible(child: imageCard),
        ],
      );
    }

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isMine ? AppColors.primaryColor : const Color(0xFFE4E6EB),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 20),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (hasImage)
            GestureDetector(
              onTap: () => _showFullImage(context, message.imageUrl!),
              child: Hero(
                tag: message.imageUrl!,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                    maxHeight: 300,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: message.imageUrl!,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Container(
                      width: 220,
                      height: 180,
                      color: Colors.black12,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 220,
                      height: 140,
                      color: Colors.black12,
                      child: const Icon(Icons.broken_image_rounded, size: 40),
                    ),
                  ),
                ),
              ),
            ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                message.message,
                style: TextStyle(
                  color: isMine ? Colors.white : const Color(0xFF1C1E21),
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );

    if (isMine) {
      return Align(
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showAvatar)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 2),
            child: ChatAvatar(
              asset: otherAvatarAsset ?? 'assets/images/user1.png',
              size: 28,
              showStatus: false,
            ),
          )
        else
          const SizedBox(width: 36),
        Flexible(child: bubble),
      ],
    );
  }

  void _showFullImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(
              child: InteractiveViewer(
                child: Hero(
                  tag: imageUrl,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
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
        padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
        child: Text(
          '$label น.',
          style: const TextStyle(
            color: Color(0xFF8A8E92),
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
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
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 46,
              child: IconButton.filled(
                key: const ValueKey('attach-button'),
                tooltip: 'แนบไฟล์',
                onPressed: onAttach,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4F5460),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 24),
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
                    horizontal: 20,
                    vertical: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox.square(
              dimension: 46,
              child: IconButton.filled(
                key: const ValueKey('send-message-button'),
                tooltip: 'ส่งข้อความ',
                onPressed: onSend,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 4,
                ),
                icon: const Icon(Icons.send_rounded, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

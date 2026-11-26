import 'package:frontend/core/widgets/app_popup.dart';
import '../../../item_detail/data/datasources/item_detail_remote_data_source.dart';
import '../../../item_detail/domain/entities/item_detail.dart';
import '../../../../core/widgets/package_chat_list.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/colors.dart';
import '../../../../core/services/item_review_service.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/active_conversation_tracker.dart';
import '../../../../core/services/app_permission_service.dart';
import '../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../core/services/chat_notification_service.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_reply_content.dart';
import '../../domain/entities/item_inquiry_data.dart';
import '../../domain/usecases/fetch_messages_usecase.dart';
import '../../domain/usecases/get_conversation_contact_phone_usecase.dart';
import '../../domain/usecases/get_owned_chat_item_ids_usecase.dart';
import '../../domain/usecases/mark_messages_as_read_usecase.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import '../../domain/usecases/stream_messages_usecase.dart';
import '../../domain/usecases/upload_chat_image_usecase.dart';
import '../bloc/chat_detail_bloc.dart';
import '../bloc/chat_detail_event.dart';
import '../bloc/chat_detail_state.dart';
import '../widgets/chat_detail_header.dart';
import '../widgets/chat_empty_view.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_message_composer.dart';
import '../widgets/chat_skeleton_loading_view.dart';
import '../widgets/chat_typing_indicator_bubble.dart';

String _extractActualTextMessage(String raw) =>
    ChatReplyContent.messageText(raw);

class ChatDetailScreen extends StatelessWidget {
  const ChatDetailScreen({
    super.key,
    required this.conversation,
    this.initialMessageId,
    this.chatDetailBloc,
    this.getContactPhone,
    this.phoneCallService = const UrlPhoneCallService(),
  });

  final ChatConversation conversation;
  final String? initialMessageId;
  final ChatDetailBloc? chatDetailBloc;
  final GetConversationContactPhoneUseCase? getContactPhone;
  final PhoneCallService phoneCallService;

  @override
  Widget build(BuildContext context) {
    final repository = ChatRepositoryImpl(
      remoteDataSource: ChatRemoteDataSource(),
    );
    final contactPhoneUseCase =
        getContactPhone ?? GetConversationContactPhoneUseCase(repository);
    final chatDetailView = _ChatDetailView(
      conversation: conversation,
      getContactPhone: contactPhoneUseCase,
      phoneCallService: phoneCallService,
      initialMessageId: initialMessageId,
    );

    if (chatDetailBloc != null) {
      return BlocProvider.value(value: chatDetailBloc!, child: chatDetailView);
    }

    return BlocProvider(
      create: (context) => ChatDetailBloc(
        conversationId: conversation.id,
        streamMessages: StreamMessagesUseCase(repository),
        sendMessage: SendChatMessageUseCase(repository),
        fetchMessages: FetchMessagesUseCase(repository),
        uploadChatImage: UploadChatImageUseCase(repository),
        markMessagesAsRead: MarkMessagesAsReadUseCase(repository),
        getOwnedItemIds: GetOwnedChatItemIdsUseCase(repository),
      ),
      child: chatDetailView,
    );
  }
}

class _ChatDetailView extends StatefulWidget {
  const _ChatDetailView({
    required this.conversation,
    required this.getContactPhone,
    required this.phoneCallService,
    this.initialMessageId,
  });

  final ChatConversation conversation;
  final GetConversationContactPhoneUseCase getContactPhone;
  final PhoneCallService phoneCallService;
  final String? initialMessageId;

  @override
  State<_ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<_ChatDetailView> {
  late ChatConversation _conversation;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  int _lastMessageCount = 0;
  ChatMessage? _replyingMessage;
  ChatMessage? _editingMessage;
  Timer? _typingDebounceTimer;
  Timer? _highlightTimer;
  String? _highlightedMessageId;
  bool _showScrollToBottom = false;
  bool _isStartingPhoneCall = false;
  final _messageKeys = <String, GlobalKey>{};

  GlobalKey _getKeyForMessage(String id) =>
      _messageKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    ActiveConversationTracker.instance.setActive(widget.conversation.id);
    context.read<ChatDetailBloc>().add(
      ChatMessagesSubscriptionRequested(
        widget.conversation.id,
        itemId: widget.conversation.itemId,
      ),
    );
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onTextChanged);

    // ⚡ ส่งสัญญาณอ่านข้อความแบบ Direct WebSocket ทันทีเมื่อเปิดห้องแชท
    ChatRemoteDataSource().broadcastReadReceipt(
      conversationId: widget.conversation.id,
    );
    ChatNotificationService.instance.clearConversationNotifications(
      widget.conversation.id,
    );

    if (_conversation.otherUserId.isEmpty || _conversation.name == 'ห้องแชท') {
      ChatRemoteDataSource().getConversationById(widget.conversation.id).then((
        fullConv,
      ) {
        if (fullConv != null && mounted) {
          setState(() {
            _conversation = fullConv;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _typingDebounceTimer?.cancel();
    _highlightTimer?.cancel();
    _messageController.removeListener(_onTextChanged);
    ActiveConversationTracker.instance.clearActive(widget.conversation.id);
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      ChatRemoteDataSource().broadcastTypingStatus(
        conversationId: widget.conversation.id,
        isTyping: true,
      );
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
        ChatRemoteDataSource().broadcastTypingStatus(
          conversationId: widget.conversation.id,
          isTyping: false,
        );
      });
    } else {
      _typingDebounceTimer?.cancel();
      ChatRemoteDataSource().broadcastTypingStatus(
        conversationId: widget.conversation.id,
        isTyping: false,
      );
    }
  }

  Future<void> _startPhoneCall() async {
    if (_isStartingPhoneCall) return;
    setState(() => _isStartingPhoneCall = true);

    try {
      final phone = await widget.getContactPhone(_conversation.id);
      final launched = await widget.phoneCallService.call(phone);
      if (!launched) {
        throw const ChatRemoteException('ไม่สามารถเปิดแอปโทรศัพท์ได้');
      }
    } on ChatRemoteException catch (error) {
      if (!mounted) return;
      _showPhoneCallError(error.message);
    } catch (_) {
      if (!mounted) return;
      _showPhoneCallError('ไม่สามารถโทรหาผู้ใช้นี้ได้ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _isStartingPhoneCall = false);
    }
  }

  void _showPhoneCallError(String message) {
    showAppPopup(context, content: Text(message));
  }

  void _handleReply(ChatMessage message) {
    setState(() {
      _replyingMessage = message;
      _editingMessage = null;
    });
  }

  void _handleEdit(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _replyingMessage = null;
      _messageController.text = _extractActualTextMessage(message.message);
    });
  }

  void _cancelReplyOrEdit() {
    setState(() {
      _replyingMessage = null;
      _editingMessage = null;
      _messageController.clear();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final shouldShow = _scrollController.position.pixels > 200;
    if (shouldShow != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = shouldShow;
      });
    }

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

  void _scrollToMessage(String messageId) {
    if (messageId.isEmpty || !mounted) return;
    final messages = context.read<ChatDetailBloc>().state.messages;
    final renderItems = _buildRenderItems(messages);
    final targetIndex = renderItems.indexWhere(
      (item) =>
          item.message.id == messageId || item.messageIds.contains(messageId),
    );
    if (targetIndex == -1 || !_scrollController.hasClients) return;

    final targetItem = renderItems[targetIndex];

    // ไฮไลต์เฉพาะข้อความเป้าหมายตาม ID ที่แท้จริง (ไม่ไฮไลต์ข้อความซ้ำอื่น)
    setState(() {
      _highlightedMessageId = targetItem.message.id;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && _highlightedMessageId == targetItem.message.id) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });

    final key = _messageKeys[targetItem.message.id];
    final renderBox = key?.currentContext?.findRenderObject();
    if (renderBox is RenderBox && _scrollController.hasClients) {
      final viewport = RenderAbstractViewport.of(renderBox);
      final revealed = viewport.getOffsetToReveal(renderBox, 0.5);
      _scrollController.animateTo(
        revealed.offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
      return;
    }

    // หาก Widget อยู่นอกระยะเรนเดอร์ ให้คำนวณตำแหน่งอย่างแม่นยำตามความสูงของแต่ละ Item
    double estimatedOffset = 0.0;
    for (int i = renderItems.length - 1; i > targetIndex; i--) {
      final it = renderItems[i];
      if (it.imageUrls.length > 1) {
        estimatedOffset += 260.0;
      } else if (it.imageUrls.isNotEmpty ||
          (it.message.imageUrl != null && it.message.imageUrl!.isNotEmpty)) {
        estimatedOffset += 210.0;
      } else {
        final len = it.message.message.length;
        estimatedOffset += len > 100 ? 120.0 : (len > 40 ? 85.0 : 60.0);
      }
      if (_shouldShowTimeDivider(renderItems, i)) {
        estimatedOffset += 36.0;
      }
    }

    final clampedOffset = estimatedOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController
        .animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final postBox = _messageKeys[targetItem.message.id]?.currentContext
                ?.findRenderObject();
            if (postBox is RenderBox &&
                _scrollController.hasClients &&
                mounted) {
              final viewport = RenderAbstractViewport.of(postBox);
              final revealed = viewport.getOffsetToReveal(postBox, 0.5);
              _scrollController.animateTo(
                revealed.offset.clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                ),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
              );
            }
          });
        });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _typingDebounceTimer?.cancel();
    ChatRemoteDataSource().broadcastTypingStatus(
      conversationId: widget.conversation.id,
      isTyping: false,
    );

    if (_editingMessage != null) {
      final reply = ChatReplyContent.tryParse(_editingMessage!.message);
      final editedFullMessage = reply?.toMessage(newText: text) ?? text;

      context.read<ChatDetailBloc>().add(
        ChatMessageEdited(
          conversationId: widget.conversation.id,
          messageId: _editingMessage!.id,
          newMessage: editedFullMessage,
        ),
      );
      _cancelReplyOrEdit();
      return;
    }

    final String sendingText;
    if (_replyingMessage != null) {
      final isReplyingToSelf = _replyingMessage!.isMine;
      final replyTargetLabel = isReplyingToSelf
          ? 'ตัวเอง'
          : widget.conversation.name;
      sendingText = ChatReplyContent.compose(
        original: _replyingMessage!,
        target: replyTargetLabel,
        text: text,
      );
    } else {
      sendingText = text;
    }

    context.read<ChatDetailBloc>().add(
      ChatMessageSent(
        conversationId: widget.conversation.id,
        message: sendingText,
      ),
    );

    _cancelReplyOrEdit();
    _scrollToBottom(animate: true);
  }

  Future<void> _handleCameraPick() async {
    final hasPermission = await AppPermissionService.requestCameraPermission(
      context,
    );
    if (!hasPermission || !mounted) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        _sendImages([picked], '');
      }
    } catch (_) {
      if (mounted) {
        showAppPopup(context, content: Text('ไม่สามารถเปิดกล้องได้'));
      }
    }
  }

  Future<void> _handleGalleryPick() async {
    final hasPermission = await AppPermissionService.requestGalleryPermission(
      context,
    );
    if (!hasPermission || !mounted) return;

    try {
      final pickedList = await _picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (pickedList.isNotEmpty && mounted) {
        _sendImages(pickedList, '');
      }
    } catch (_) {
      if (mounted) {
        showAppPopup(context, content: Text('ไม่สามารถเลือกรูปภาพได้'));
      }
    }
  }

  Future<void> _sendImages(List<XFile> images, String caption) async {
    if (images.isEmpty || !mounted) return;

    try {
      final compressedDataList = await Future.wait(
        images.map((file) async {
          final rawBytes = await file.readAsBytes();
          final compressed = await FlutterImageCompress.compressWithList(
            rawBytes,
            minWidth: 1024,
            minHeight: 1024,
            quality: 80,
          );
          return ChatImageData(imageBytes: compressed, fileName: file.name);
        }),
      );

      if (!mounted) return;

      String? effectiveCaption = caption.trim().isEmpty ? null : caption.trim();
      if (_replyingMessage != null) {
        final isReplyingToSelf = _replyingMessage!.isMine;
        final replyTargetLabel = isReplyingToSelf
            ? 'ตัวเอง'
            : widget.conversation.name;
        effectiveCaption = ChatReplyContent.compose(
          original: _replyingMessage!,
          target: replyTargetLabel,
          text: effectiveCaption ?? '',
        );
        _cancelReplyOrEdit();
      }

      context.read<ChatDetailBloc>().add(
        ChatMultipleImagesUploadedAndSent(
          conversationId: widget.conversation.id,
          images: compressedDataList,
          caption: effectiveCaption,
        ),
      );
      _scrollToBottom(animate: true);
    } catch (_) {
      if (mounted) {
        showAppPopup(
          context,
          content: Text('เกิดข้อผิดพลาดในการประมวลผลรูปภาพ'),
        );
      }
    }
  }

  bool _canCreateOffer(ItemInquiryData inquiry) {
    final state = context.read<ChatDetailBloc>().state;
    if (!state.ownedItemIds.contains(inquiry.itemId)) return false;

    var isLatestOffer = true;
    var matchesPreviousBooking = false;
    for (final message in state.messages.reversed) {
      if (state.failedMessageIds.contains(message.id)) continue;
      final booking = BookingRequestData.fromChatMessage(message.message);
      if (booking == null || booking.item.id != inquiry.itemId) continue;

      final status = booking.status;
      final isCompleted = status == 'completed' || status == 'finished';
      final canRetry = const {
        'cancelled',
        'rejected',
        'expired',
      }.contains(status);
      if (isLatestOffer && !isCompleted && !canRetry) return false;
      isLatestOffer = false;
      if (!isCompleted && !canRetry) continue;

      final bookingId =
          booking.bookingId ??
          BookingConfirmationTracker.getCachedBookingId(message.id);
      matchesPreviousBooking =
          matchesPreviousBooking ||
          (bookingId != null && inquiry.previousBookingId == bookingId);
      // การยกเลิกรอบถัดไปไม่ควรเปิดให้ใช้คำถามก่อนรอบที่เช่าเสร็จแล้ว
      if (isCompleted) return matchesPreviousBooking;
    }
    return true;
  }

  Future<void> _openBookingRequest(ItemInquiryData inquiry) async {
    final itemId = inquiry.itemId;
    if (itemId == null || !_canCreateOffer(inquiry)) return;

    final title = inquiry.itemName.isNotEmpty
        ? inquiry.itemName
        : (_conversation.itemName?.isNotEmpty == true
              ? _conversation.itemName!
              : (_conversation.name.isNotEmpty
                    ? 'อุปกรณ์จาก ${_conversation.name}'
                    : 'อุปกรณ์เช่า'));
    final imageUrl = (inquiry.imageUrl?.isNotEmpty == true)
        ? inquiry.imageUrl!
        : (_conversation.itemImageUrl?.isNotEmpty == true
              ? _conversation.itemImageUrl!
              : 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?q=80&w=800&auto=format&fit=crop');
    final price = (inquiry.price != null && inquiry.price! > 0)
        ? inquiry.price!
        : (_conversation.itemPrice ?? 100).toDouble();
    final BookingRentalType rentalType;
    final unit = (inquiry.unitLabel ?? '').toLowerCase();
    if (unit.contains('ชั่วโมง') || unit.contains('hour')) {
      rentalType = BookingRentalType.hourly;
    } else if (unit.contains('วัน') || unit.contains('day')) {
      rentalType = BookingRentalType.daily;
    } else {
      rentalType =
          (_conversation.itemRentalType == 'hourly' ||
              _conversation.itemRentalType == 'hour' ||
              _conversation.itemRentalType == 'รายชั่วโมง')
          ? BookingRentalType.hourly
          : BookingRentalType.daily;
    }

    final itemSource = ItemDetailRemoteDataSource();
    final ItemDetail itemDetail;
    try {
      itemDetail = await itemSource.fetchById(itemId);
    } catch (_) {
      if (mounted)
        showAppPopup(
          context,
          content: Text('โหลดข้อมูลจุดนัดรับไม่สำเร็จ กรุณาลองใหม่'),
        );
      return;
    }
    if (!mounted) return;
    if (!itemDetail.isOwner) {
      showAppPopup(
        context,
        content: Text('เฉพาะเจ้าของอุปกรณ์เท่านั้นที่สร้างข้อเสนอได้'),
      );
      return;
    }
    if (itemDetail.isRentalOccupied) {
      showAppPopup(
        context,
        content: const Text(
          'อุปกรณ์นี้กำลังถูกเช่า ส่งข้อเสนอได้หลังยกเลิกการจองหรือรับคืนอุปกรณ์แล้ว',
        ),
      );
      return;
    }
    final pickup = itemDetail.pickupLocation;
    if (pickup == null) {
      showAppPopup(
        context,
        content: Text(
          'กรุณาระบุจุดนัดรับสินค้าในหน้าแก้ไขอุปกรณ์ก่อนส่งข้อเสนอ',
        ),
      );
      return;
    }
    final reviewStats = await ItemReviewService.fetchStats(itemId);
    if (!mounted || !_canCreateOffer(inquiry)) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final itemInfo = BookingItemInfo(
      id: itemId,
      title: title,
      imageUrl: imageUrl,
      rating: reviewStats.rating,
      reviewCount: reviewStats.reviewCount,
      hourlyRate: itemDetail.additionalDailyPrice != null
          ? itemDetail.price.toDouble()
          : (rentalType == BookingRentalType.hourly
                ? price
                : (price / 8).roundToDouble()),
      dailyRate:
          itemDetail.additionalDailyPrice?.toDouble() ??
          (rentalType == BookingRentalType.daily
              ? price
              : (price * 8).roundToDouble()),
      defaultLocation: pickup.name,
      latitude: pickup.latitude,
      longitude: pickup.longitude,
      ownerName: 'ฉัน',
    );

    final bookingData = BookingRequestData(
      item: itemInfo,
      rentalType: rentalType,
      startDate: today,
      endDate: rentalType == BookingRentalType.daily
          ? today.add(const Duration(days: 1))
          : today,
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 17, minute: 0),
      location: pickup.name,
      locationNote: pickup.note,
      locationAddress: pickup.address,
      latitude: pickup.latitude,
      longitude: pickup.longitude,
      conversationId: _conversation.id,
      ownerId: itemDetail.owner.userId,
    );

    final bloc = context.read<ChatDetailBloc>();
    AppRoutes.openBooking(
      context,
      initialData: bookingData,
      onSendRequest: (data) {
        if (!mounted) return;
        if (!_canCreateOffer(inquiry)) {
          showAppPopup(
            context,
            content: const Text('ไม่สามารถส่งข้อเสนอจากคำถามเช่านี้ได้'),
          );
          return;
        }
        bloc.add(
          ChatMessageSent(
            conversationId: _conversation.id,
            message: data.toChatMessagePayload(),
            imageUrl: data.item.imageUrl.isEmpty ? null : data.item.imageUrl,
          ),
        );
        _scrollToBottom();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      body: Column(
        children: [
          ChatDetailHeader(
            conversation: _conversation,
            onPhoneCallPressed: _startPhoneCall,
            isPhoneCallLoading: _isStartingPhoneCall,
          ),
          Expanded(
            child: Stack(
              children: [
                BlocConsumer<ChatDetailBloc, ChatDetailState>(
                  listener: (context, state) {
                    if (state.status == ChatDetailStatus.failure &&
                        state.errorMessage != null) {
                      showAppPopup(context, content: Text(state.errorMessage!));
                    } else if (state.status == ChatDetailStatus.success &&
                        state.messages.isNotEmpty) {
                      if (state.messages.length > _lastMessageCount) {
                        final lastMsg = state.messages.last;
                        final openingAtInquiry =
                            _lastMessageCount == 0 &&
                            widget.initialMessageId != null;
                        if (!openingAtInquiry &&
                            (lastMsg.isMine || _isNearBottom())) {
                          _scrollToBottom(animate: true);
                        }
                      }
                      _lastMessageCount = state.messages.length;
                    }
                  },
                  builder: (context, state) {
                    if (state.messages.isEmpty) {
                      if (_hasChatHistory &&
                          state.status != ChatDetailStatus.success) {
                        return const ChatSkeletonLoadingView();
                      }
                      return ChatEmptyView(conversation: _conversation);
                    }

                    final renderItems = _buildRenderItems(state.messages);
                    final messagesById = {
                      for (final message in state.messages) message.id: message,
                    };

                    int lastMyMessageIndex = -1;
                    for (int k = renderItems.length - 1; k >= 0; k--) {
                      if (renderItems[k].message.isMine) {
                        lastMyMessageIndex = k;
                        break;
                      }
                    }

                    return PackageChatList(
                      key: const ValueKey('chat-message-list'),
                      reversed: true,
                      scrollController: _scrollController,
                      initialMessageId: widget.initialMessageId,
                      entries: [
                        for (final item in renderItems)
                          PackageChatEntry(
                            id: item.message.id,
                            authorId: item.message.senderId,
                            createdAt: item.message.createdAt,
                            revision: Object.hash(
                              state,
                              _highlightedMessageId,
                              item.message,
                            ),
                          ),
                      ],
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      itemBuilder: (context, index) {
                        final actualIndex = index;
                        final item = renderItems[actualIndex];
                        final showTimeDivider = _shouldShowTimeDivider(
                          renderItems,
                          actualIndex,
                        );
                        final previousDate = actualIndex > 0
                            ? renderItems[actualIndex - 1].message.createdAt
                            : null;
                        final showAvatar = _shouldShowAvatar(
                          renderItems,
                          actualIndex,
                        );

                        final showDeliveryStatus =
                            (actualIndex == lastMyMessageIndex &&
                            item.message.isMine);
                        final String? deliveryStatusLabel;
                        if (showDeliveryStatus) {
                          if (item.message.id.startsWith('temp_')) {
                            deliveryStatusLabel =
                                state.sendingMessageIds.contains(
                                  item.message.id,
                                )
                                ? 'กำลังส่ง'
                                : 'ส่งแล้ว';
                          } else if (item.message.isRead) {
                            deliveryStatusLabel = null;
                          } else {
                            deliveryStatusLabel = 'ส่งแล้ว';
                          }
                        } else {
                          deliveryStatusLabel = null;
                        }

                        final isHighlighted =
                            _highlightedMessageId == item.message.id ||
                            item.messageIds.contains(_highlightedMessageId);
                        final itemKey = _getKeyForMessage(item.message.id);
                        for (final id in item.messageIds) {
                          _messageKeys[id] = itemKey;
                        }

                        final inquiry = ItemInquiryData.fromChatMessage(
                          item.message.message,
                          defaultItemId: _conversation.itemId,
                        );
                        final ownsInquiryItem = state.ownedItemIds.contains(
                          inquiry?.itemId,
                        );
                        // ข้อเสนอที่บันทึกแล้วมีผู้ส่งเป็นเจ้าของตามกฎฝั่งเซิร์ฟเวอร์
                        final isOwner =
                            BookingRequestData.isBookingRequest(
                              item.message.message,
                            )
                            ? item.message.isMine
                            : ownsInquiryItem;

                        return Container(
                          key: itemKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showTimeDivider)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Center(
                                    child: Text(
                                      _formatTimeDivider(
                                        item.message.createdAt,
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
                              ChatMessageBubble(
                                message: item.message,
                                quotedMessage:
                                    messagesById[ChatReplyContent.tryParse(
                                      item.message.message,
                                    )?.quotedMessageId],
                                imageUrls: item.imageUrls,
                                otherAvatarAsset: _conversation.avatarAsset,
                                otherUserName: _conversation.name,
                                showAvatar: showAvatar,
                                deliveryStatus: deliveryStatusLabel,
                                isRead: item.message.isRead,
                                showDeliveryStatus: showDeliveryStatus,
                                isHighlighted: isHighlighted,
                                isFailed: state.failedMessageIds.contains(
                                  item.message.id,
                                ),
                                isOwner: isOwner,
                                isHandoverCompleted: state.messages.any(
                                  (m) =>
                                      m.message.contains(
                                        'ยืนยันการส่งมอบอุปกรณ์เรียบร้อยแล้ว',
                                      ) ||
                                      m.message.contains(
                                        'เริ่มต้นช่วงเวลาเช่า',
                                      ) ||
                                      m.message.contains('ส่งมอบอุปกรณ์สำเร็จ'),
                                ),
                                isReturnCompleted: state.messages.any(
                                  (m) =>
                                      m.message.contains(
                                        'ส่งคืนอุปกรณ์เรียบร้อย',
                                      ) ||
                                      m.message.contains(
                                        'ตรวจรับคืนอุปกรณ์เรียบร้อย',
                                      ) ||
                                      m.message.contains('คืนของสำเร็จ'),
                                ),
                                onSendBookingRequest:
                                    inquiry != null && _canCreateOffer(inquiry)
                                    ? _openBookingRequest
                                    : null,
                                defaultItemId: _conversation.itemId,
                                onRetry: () {
                                  context.read<ChatDetailBloc>().add(
                                    ChatRetryMessageSent(
                                      conversationId: widget.conversation.id,
                                      tempMessageId: item.message.id,
                                    ),
                                  );
                                },
                                onReply: _handleReply,
                                onEdit: item.message.isMine
                                    ? _handleEdit
                                    : null,
                                onQuotedTap: _scrollToMessage,
                                onDelete: (msg) {
                                  final idsToDelete = item.messageIds.isNotEmpty
                                      ? item.messageIds
                                      : [msg.id];
                                  for (final id in idsToDelete) {
                                    context.read<ChatDetailBloc>().add(
                                      ChatMessageDeleted(
                                        conversationId: widget.conversation.id,
                                        messageId: id,
                                        imageUrl: idsToDelete.length == 1
                                            ? msg.imageUrl
                                            : null,
                                      ),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: AnimatedScale(
                    scale: _showScrollToBottom ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: _showScrollToBottom ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: !_showScrollToBottom,
                        child: Material(
                          color: Colors.transparent,
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.25),
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: const ValueKey('chat-scroll-to-bottom-button'),
                            onTap: () => _scrollToBottom(animate: true),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.primaryColor,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          BlocBuilder<ChatDetailBloc, ChatDetailState>(
            buildWhen: (prev, curr) =>
                prev.isOtherUserTyping != curr.isOtherUserTyping,
            builder: (context, state) {
              if (!state.isOtherUserTyping) return const SizedBox.shrink();
              return ChatTypingIndicatorBubble(
                avatarAsset: _conversation.avatarAsset,
              );
            },
          ),
          BlocBuilder<ChatDetailBloc, ChatDetailState>(
            buildWhen: (prev, curr) =>
                prev.isUploadingImage != curr.isUploadingImage,
            builder: (context, state) {
              if (!state.isUploadingImage) return const SizedBox.shrink();
              return Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
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
          ChatMessageComposer(
            controller: _messageController,
            onSend: _sendMessage,
            onCamera: _handleCameraPick,
            onGallery: _handleGalleryPick,
            replyingMessage: _replyingMessage,
            editingMessage: _editingMessage,
            onCancelReplyOrEdit: _cancelReplyOrEdit,
          ),
        ],
      ),
    );
  }

  List<_ChatRenderItem> _buildRenderItems(List<ChatMessage> messages) {
    final List<_ChatRenderItem> items = [];
    int i = 0;
    while (i < messages.length) {
      final msg = messages[i];
      if (msg.message.trimLeft().startsWith('📞')) {
        i++;
        continue;
      }

      final isImageOnly =
          (msg.imageUrl != null && msg.imageUrl!.isNotEmpty) &&
          (msg.message.isEmpty ||
              msg.message == '📷 ส่งรูปภาพ' ||
              msg.message == '[รูปภาพ]');

      if (isImageOnly) {
        final List<String> urls = [msg.imageUrl!];
        final List<String> msgIds = [msg.id];
        int j = i + 1;
        while (j < messages.length) {
          final next = messages[j];
          final nextIsImageOnly =
              (next.imageUrl != null && next.imageUrl!.isNotEmpty) &&
              (next.message.isEmpty ||
                  next.message == '📷 ส่งรูปภาพ' ||
                  next.message == '[รูปภาพ]');
          if (nextIsImageOnly &&
              next.isMine == msg.isMine &&
              next.createdAt
                      .difference(messages[j - 1].createdAt)
                      .inMinutes
                      .abs() <=
                  2) {
            urls.add(next.imageUrl!);
            msgIds.add(next.id);
            j++;
          } else {
            break;
          }
        }
        final representativeMsg = messages[j - 1];
        items.add(
          _ChatRenderItem(
            message: representativeMsg,
            imageUrls: urls,
            messageIds: msgIds,
            isStacked: urls.length > 1,
          ),
        );

        i = j;
      } else {
        items.add(
          _ChatRenderItem(
            message: msg,
            imageUrls: msg.imageUrl != null && msg.imageUrl!.isNotEmpty
                ? [msg.imageUrl!]
                : const [],
            messageIds: [msg.id],
            isStacked: false,
          ),
        );
        i++;
      }
    }
    return items;
  }

  bool get _hasChatHistory =>
      widget.conversation.preview.trim().isNotEmpty &&
      widget.conversation.preview.trim() != 'เริ่มการสนทนา' &&
      widget.conversation.preview.trim() != 'ยังไม่มีข้อความ';

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  bool _shouldShowTimeDivider(List<_ChatRenderItem> items, int index) {
    if (index == 0) return true;
    final prev = items[index - 1].message;
    final curr = items[index].message;
    if (_isDifferentDay(prev.createdAt, curr.createdAt)) return true;
    return curr.createdAt.difference(prev.createdAt).inMinutes.abs() >= 15;
  }

  bool _shouldShowAvatar(List<_ChatRenderItem> items, int index) {
    final curr = items[index].message;
    if (curr.isMine) return false;
    if (index == items.length - 1) return true;
    final next = items[index + 1].message;
    if (next.isMine) return true;
    if (_shouldShowTimeDivider(items, index + 1)) return true;
    return false;
  }

  static const List<String> _thaiShortMonths = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  static String _formatThaiDayMonth(DateTime date) {
    try {
      return DateFormat('d MMM', 'th').format(date);
    } catch (_) {
      final month = (date.month >= 1 && date.month <= 12)
          ? _thaiShortMonths[date.month - 1]
          : '${date.month}';
      return '${date.day} $month';
    }
  }

  String _formatTimeDivider(DateTime date, DateTime? previousDate) {
    final now = DateTime.now();
    final minuteStr = date.minute.toString().padLeft(2, '0');
    final hourStr = date.hour.toString().padLeft(2, '0');
    final timeStr = '$hourStr:$minuteStr';

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
        final dayStr = _formatThaiDayMonth(date);
        return '$dayStr $timeStr น.';
      } else {
        final fullDateStr = '${date.day}/${date.month}/${date.year % 100}';
        return '$fullDateStr $timeStr น.';
      }
    }

    return '$timeStr น.';
  }
}

class _ChatRenderItem {
  const _ChatRenderItem({
    required this.message,
    required this.imageUrls,
    this.messageIds = const [],
    this.isStacked = false,
  });

  final ChatMessage message;
  final List<String> imageUrls;
  final List<String> messageIds;
  final bool isStacked;
}

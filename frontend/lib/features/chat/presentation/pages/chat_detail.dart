import 'package:frontend/core/widgets/app_popup.dart';
import '../../../item_detail/data/datasources/item_detail_remote_data_source.dart';
import '../../../item_detail/domain/entities/item_detail.dart';
import '../../../../core/widgets/package_chat_list.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/colors.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/active_conversation_tracker.dart';
import '../../../../core/services/app_permission_service.dart';
import '../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../core/services/chat_notification_service.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/datasources/rental_queue_remote_data_source.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_reply_content.dart';
import '../../domain/entities/item_inquiry_data.dart';
import '../../domain/entities/rental_queue_card_data.dart';
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
import '../widgets/chat_rental_safety_dialog.dart';
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
    this.rentalQueueSource,
    this.fetchItemDetail,
    this.getUnavailableRentalItemIds,
    this.watchRentalAvailabilityChanges,
    this.getContactPhone,
    this.phoneCallService = const UrlPhoneCallService(),
  });

  final ChatConversation conversation;
  final String? initialMessageId;
  final ChatDetailBloc? chatDetailBloc;
  final RentalQueueRemoteDataSource? rentalQueueSource;
  final Future<ItemDetail> Function(int)? fetchItemDetail;
  final Future<Set<int>> Function(Set<int>)? getUnavailableRentalItemIds;
  final Stream<void> Function(int)? watchRentalAvailabilityChanges;
  final GetConversationContactPhoneUseCase? getContactPhone;
  final PhoneCallService phoneCallService;

  @override
  Widget build(BuildContext context) {
    final remoteDataSource = ChatRemoteDataSource();
    final repository = ChatRepositoryImpl(remoteDataSource: remoteDataSource);
    final contactPhoneUseCase =
        getContactPhone ?? GetConversationContactPhoneUseCase(repository);
    final chatDetailView = _ChatDetailView(
      conversation: conversation,
      getContactPhone: contactPhoneUseCase,
      phoneCallService: phoneCallService,
      initialMessageId: initialMessageId,
      rentalQueueSource: rentalQueueSource,
      fetchItemDetail: fetchItemDetail,
      getUnavailableRentalItemIds:
          getUnavailableRentalItemIds ??
          remoteDataSource.getUnavailableRentalItemIds,
      watchRentalAvailabilityChanges:
          watchRentalAvailabilityChanges ??
          remoteDataSource.watchRentalAvailabilityChanges,
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
    required this.getUnavailableRentalItemIds,
    required this.watchRentalAvailabilityChanges,
    this.initialMessageId,
    this.rentalQueueSource,
    this.fetchItemDetail,
  });

  final ChatConversation conversation;
  final GetConversationContactPhoneUseCase getContactPhone;
  final PhoneCallService phoneCallService;
  final String? initialMessageId;
  final RentalQueueRemoteDataSource? rentalQueueSource;
  final Future<ItemDetail> Function(int)? fetchItemDetail;
  final Future<Set<int>> Function(Set<int>) getUnavailableRentalItemIds;
  final Stream<void> Function(int) watchRentalAvailabilityChanges;

  @override
  State<_ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<_ChatDetailView>
    with WidgetsBindingObserver {
  static const _completedRentalStatuses = {
    'completed',
    'finished',
    'คืนของสำเร็จ',
  };

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
  bool _selectingRentalQueueItem = false;
  bool _loadingRentalQueueItems = false;
  bool _openingQueuedRentalRequest = false;
  bool _isCurrentRoute = false;
  bool _refreshRentalQueueItemsAgain = false;
  bool _hasLoadedRentalQueueItems = false;
  Timer? _rentalQueueRefreshTimer;
  List<({int id, String name})> _rentalQueueItems = const [];
  final _requestingRentalQueueItemIds = <int>{};
  final _rentalAvailabilitySubscriptions = <int, StreamSubscription<void>>{};
  Set<int> _rentalAvailabilityItemIds = const {};
  final _rentalAvailability = <int, bool>{};
  int _rentalAvailabilityRevision = 0;
  RentalQueueRemoteDataSource? _queueSource;

  RentalQueueRemoteDataSource get _rentalQueue =>
      widget.rentalQueueSource ??
      (_queueSource ??= RentalQueueRemoteDataSource());
  final _messageKeys = <String, GlobalKey>{};

  GlobalKey _getKeyForMessage(String id) =>
      _messageKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRentalSafetyReminder();
    });

    // ⚡ ส่งสัญญาณอ่านข้อความแบบ Direct WebSocket ทันทีเมื่อเปิดห้องแชท
    ChatRemoteDataSource().broadcastReadReceipt(
      conversationId: widget.conversation.id,
    );
    ChatNotificationService.instance.clearConversationNotifications(
      widget.conversation.id,
    );

    if (SupabaseConfig.isInitialized) {
      ChatRemoteDataSource().getConversationById(widget.conversation.id).then((
        fullConv,
      ) {
        if (fullConv != null && mounted && fullConv != _conversation) {
          setState(() {
            _conversation = fullConv;
          });
          unawaited(_refreshRentalAvailability());
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (_isCurrentRoute == isCurrent) return;
    _isCurrentRoute = isCurrent;
    _rentalQueueRefreshTimer?.cancel();
    if (!isCurrent || !AuthSession.isAuthenticated) {
      _watchRentalAvailabilityForItems(const {});
      return;
    }

    _refreshRentalState();
    // สำรองไว้เมื่อเชื่อมต่อ Realtime ไม่ได้ หรือยังไม่มีอุปกรณ์ในแชทให้ติดตาม
    _rentalQueueRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshRentalQueueItems());
      unawaited(_refreshRentalAvailability());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRentalState();
  }

  void _refreshRentalState() {
    if (!_isCurrentRoute) return;
    unawaited(_refreshRentalQueueItems(afterAction: true));
    unawaited(_refreshRentalAvailability());
  }

  Future<void> _showRentalSafetyReminder() async {
    if (_conversation.isOtherUserUnavailable) return;
    final accountId = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    if (accountId == null || accountId.isEmpty) return;

    await showChatRentalSafetyReminder(
      context,
      accountId: accountId,
      role: _conversation.currentUserRentalRole,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingDebounceTimer?.cancel();
    _highlightTimer?.cancel();
    _rentalQueueRefreshTimer?.cancel();
    _watchRentalAvailabilityForItems(const {});
    _messageController.removeListener(_onTextChanged);
    ActiveConversationTracker.instance.clearActive(widget.conversation.id);
    _scrollController.removeListener(_onScroll);
    _queueSource?.close();
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
    final state = context.read<ChatDetailBloc>().state;
    final inquiryReplacements = _inquiryReplacements(state);
    final targetMessageId = inquiryReplacements[messageId] ?? messageId;
    final renderItems = _buildRenderItems(state.messages, inquiryReplacements);
    final targetIndex = renderItems.indexWhere(
      (item) => item.containsMessage(targetMessageId),
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

  Future<void> _refreshRentalQueueItems({bool afterAction = false}) async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_conversation.isOtherUserUnavailable ||
        !AuthSession.isAuthenticated ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    if (_loadingRentalQueueItems) {
      _refreshRentalQueueItemsAgain |= afterAction;
      return;
    }
    _loadingRentalQueueItems = true;
    try {
      final items = await _rentalQueue.listItems(_conversation.id);
      if (mounted &&
          !_refreshRentalQueueItemsAgain &&
          (!_hasLoadedRentalQueueItems ||
              !listEquals(_rentalQueueItems, items))) {
        setState(() {
          _hasLoadedRentalQueueItems = true;
          _rentalQueueItems = items;
        });
      }
    } on RentalQueueRemoteException {
      // เก็บผลคิวล่าสุดไว้หากรีเฟรชไม่สำเร็จ
    } finally {
      _loadingRentalQueueItems = false;
      if (_refreshRentalQueueItemsAgain && mounted) {
        _refreshRentalQueueItemsAgain = false;
        unawaited(_refreshRentalQueueItems());
      }
    }
  }

  Future<void> _refreshRentalAvailability({
    bool onlyWhenItemsChange = false,
  }) async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_isCurrentRoute ||
        !AuthSession.isAuthenticated ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    final state = context.read<ChatDetailBloc>().state;
    final itemIds = <int>{
      for (final message in state.messages)
        if (BookingRequestData.fromChatMessage(message.message)
            case BookingRequestData(
              isCustomerRequest: true,
              rentalQueueMessageId: null,
              :final status,
              item: BookingItemInfo(:final id),
            )
            when const {
                  'pending',
                  'cancelled',
                  'expired',
                  'rejected',
                }.contains(status) &&
                !state.failedMessageIds.contains(message.id))
          id,
      for (final message in state.messages)
        if (message.isMine && !state.failedMessageIds.contains(message.id))
          if (_itemInquiry(message)?.itemId case final int id
              when !state.ownedItemIds.contains(id))
            id,
    };
    _watchRentalAvailabilityForItems({
      ...itemIds,
      if (_conversation.itemId case final int itemId) itemId,
    });
    if (onlyWhenItemsChange && setEquals(itemIds, _rentalAvailabilityItemIds)) {
      return;
    }
    _rentalAvailabilityItemIds = itemIds;
    final revision = ++_rentalAvailabilityRevision;
    try {
      final unavailable = itemIds.isEmpty
          ? const <int>{}
          : await widget.getUnavailableRentalItemIds(itemIds);
      final availability = {
        for (final id in itemIds) id: !unavailable.contains(id),
      };
      if (mounted &&
          revision == _rentalAvailabilityRevision &&
          availability.entries.any(
            (entry) => _rentalAvailability[entry.key] != entry.value,
          )) {
        setState(() => _rentalAvailability.addAll(availability));
      }
    } catch (_) {
      // เก็บสถานะล่าสุดไว้ระหว่างที่โหลดสถานะใหม่ไม่ได้
    }
  }

  void _watchRentalAvailabilityForItems(Set<int> itemIds) {
    _rentalAvailabilitySubscriptions.removeWhere((itemId, subscription) {
      if (itemIds.contains(itemId)) return false;
      unawaited(subscription.cancel());
      return true;
    });
    for (final itemId in itemIds) {
      _rentalAvailabilitySubscriptions.putIfAbsent(
        itemId,
        () => widget.watchRentalAvailabilityChanges(itemId).listen((_) {
          if (mounted) _refreshRentalState();
        }),
      );
    }
  }

  bool _canRequestRentalQueueForItem(int itemId) =>
      _rentalQueueItems.any((item) => item.id == itemId);

  bool _hasRentalAvailability(int itemId) =>
      !AuthSession.isAuthenticated ||
      (_hasLoadedRentalQueueItems && _rentalAvailability.containsKey(itemId));

  ItemInquiryData? _itemInquiry(ChatMessage message) {
    if (ChatReplyContent.tryParse(message.message) != null) return null;
    return ItemInquiryData.fromChatMessage(
      message.message,
      defaultItemId: _conversation.itemId,
    );
  }

  bool _hasOwnOpenRental(ChatDetailState state, int itemId) {
    return state.messages.any((message) {
      final booking = BookingRequestData.fromChatMessage(message.message);
      return booking != null &&
          booking.item.id == itemId &&
          message.isMine == booking.isCustomerRequest &&
          const {
            'confirmed',
            'active',
            'awaiting_return',
            'return_ready',
          }.contains(booking.status);
    });
  }

  Future<void> _requestRentalQueue() async {
    if (_selectingRentalQueueItem || _rentalQueueItems.isEmpty) return;
    _selectingRentalQueueItem = true;
    try {
      final items = _rentalQueueItems;
      final itemId = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('เลือกอุปกรณ์ที่ต้องการขอคิว')),
              for (final item in items)
                ListTile(
                  title: Text(item.name),
                  onTap: () => Navigator.pop(sheetContext, item.id),
                ),
            ],
          ),
        ),
      );
      if (!mounted || itemId == null) return;
      await _joinRentalQueueForItem(itemId);
    } finally {
      _selectingRentalQueueItem = false;
    }
  }

  Future<void> _joinRentalQueueForItem(int itemId) async {
    if (!_canRequestRentalQueueForItem(itemId) ||
        !_requestingRentalQueueItemIds.add(itemId)) {
      return;
    }
    try {
      await _rentalQueue.runAction(_conversation.id, 'request', itemId: itemId);
      if (!mounted) return;
      setState(() {
        _rentalQueueItems = _rentalQueueItems
            .where((item) => item.id != itemId)
            .toList();
      });
      _scrollToBottom();
    } on RentalQueueRemoteException catch (error) {
      if (mounted) showAppPopup(context, content: Text(error.message));
    } finally {
      _requestingRentalQueueItemIds.remove(itemId);
      if (mounted) unawaited(_refreshRentalQueueItems(afterAction: true));
    }
  }

  Future<void> _updateRentalQueue(ChatMessage message, String action) async {
    final id = int.tryParse(message.id);
    if (id == null) return;
    try {
      await _rentalQueue.runAction(_conversation.id, action, messageId: id);
    } on RentalQueueRemoteException catch (error) {
      if (mounted) showAppPopup(context, content: Text(error.message));
      return;
    } finally {
      if (mounted) unawaited(_refreshRentalQueueItems(afterAction: true));
    }

    if (!mounted || action != 'accept') return;
    final queue = RentalQueueCardData.fromMessage(message.message);
    if (queue == null) return;
    await _openQueuedRentalRequest(message.id, queue, justAccepted: true);
  }

  VoidCallback? _queuedRentalRequestAction(
    ChatMessage message,
    RentalQueueCardData? queue,
    ChatDetailState state,
  ) {
    if (_conversation.isOtherUserUnavailable ||
        queue == null ||
        queue.status != RentalQueueStatus.accepted ||
        !_canSendQueuedRentalRequest(message.id, state)) {
      return null;
    }
    return () => _openQueuedRentalRequest(message.id, queue);
  }

  Future<void> _openQueuedRentalRequest(
    String messageId,
    RentalQueueCardData queue, {
    bool justAccepted = false,
  }) async {
    if (_openingQueuedRentalRequest) return;
    _openingQueuedRentalRequest = true;
    try {
      await _openBookingRequest(
        ItemInquiryData(itemId: queue.itemId, itemName: queue.name),
        queueMessageId: messageId,
        justAcceptedQueue: justAccepted,
      );
    } finally {
      _openingQueuedRentalRequest = false;
    }
  }

  bool _canSendQueuedRentalRequest(
    String messageId,
    ChatDetailState state, {
    bool justAccepted = false,
  }) {
    final id = int.tryParse(messageId);
    if (id == null) return false;
    final card = state.messages
        .where((message) => message.id == messageId)
        .firstOrNull;
    if (card == null) return false;
    final queue = RentalQueueCardData.fromMessage(card.message);
    if (queue == null || !queue.isRenterView(isSender: card.isMine)) {
      return false;
    }
    // หลังยืนยันกับเซิร์ฟเวอร์สำเร็จ การ์ดอาจยังรออัปเดตจาก Realtime
    final isAccepted = queue.status == RentalQueueStatus.accepted;
    final awaitingUpdate =
        justAccepted && queue.status == RentalQueueStatus.ready;
    final acceptedAt = queue.acceptedAt;
    if ((!awaitingUpdate && (!isAccepted || acceptedAt == null)) ||
        queue.expiresAt?.isAfter(DateTime.now()) == false) {
      return false;
    }
    for (final message in state.messages.reversed) {
      if (state.failedMessageIds.contains(message.id)) continue;
      final request = BookingRequestData.fromChatMessage(message.message);
      if (request == null ||
          request.rentalQueueMessageId != id ||
          (acceptedAt != null && message.createdAt.isBefore(acceptedAt))) {
        continue;
      }
      return _canRetryRentalRequest(request);
    }
    return true;
  }

  bool _canRetryRentalRequest(BookingRequestData request) =>
      const {'cancelled', 'rejected', 'expired'}.contains(request.status) ||
      (request.status == 'pending' && request.hasCustomerRequestStartPassed);

  ChatMessage? _latestRentalRequestForItem(ChatDetailState state, int itemId) {
    return state.messages.reversed
        .where(
          (message) =>
              !state.failedMessageIds.contains(message.id) &&
              BookingRequestData.fromChatMessage(message.message)?.item.id ==
                  itemId,
        )
        .firstOrNull;
  }

  bool _canSendRentalRequest(ItemInquiryData inquiry) {
    final bloc = context.read<ChatDetailBloc>();
    final state = bloc.state;
    final itemId = inquiry.itemId;
    if (itemId == null ||
        !bloc.hasResolvedItemOwnership(itemId) ||
        state.ownedItemIds.contains(itemId) ||
        !_hasRentalAvailability(itemId) ||
        _canRequestRentalQueueForItem(itemId) ||
        _rentalAvailability[itemId] == false) {
      return false;
    }

    var isLatestRequest = true;
    var matchesPreviousBooking = false;
    for (final message in state.messages.reversed) {
      if (state.failedMessageIds.contains(message.id)) continue;
      final booking = BookingRequestData.fromChatMessage(message.message);
      if (booking == null || booking.item.id != inquiry.itemId) continue;

      final isCompleted = _completedRentalStatuses.contains(booking.status);
      final canRetry = _canRetryRentalRequest(booking);
      if (isLatestRequest && !isCompleted && !canRetry) return false;
      isLatestRequest = false;
      if (!isCompleted && !canRetry) continue;

      final bookingId =
          booking.bookingId ??
          BookingConfirmationTracker.getCachedBookingId(message.id);
      matchesPreviousBooking =
          matchesPreviousBooking ||
          (bookingId != null && inquiry.followsBooking(bookingId));
      // การยกเลิกรอบถัดไปไม่ควรเปิดให้ใช้คำถามก่อนรอบที่เช่าเสร็จแล้ว
      if (isCompleted) return matchesPreviousBooking;
    }
    return true;
  }

  Future<void> _openBookingRequest(
    ItemInquiryData inquiry, {
    String? queueMessageId,
    String? retryMessageId,
    bool justAcceptedQueue = false,
  }) async {
    final itemId = inquiry.itemId;
    if (itemId == null) return;
    bool canSend() {
      final state = context.read<ChatDetailBloc>().state;
      if (queueMessageId != null) {
        return _isCurrentRoute &&
            !_conversation.isOtherUserUnavailable &&
            _canSendQueuedRentalRequest(
              queueMessageId,
              state,
              justAccepted: justAcceptedQueue,
            );
      }
      if (retryMessageId != null) {
        final latest = _latestRentalRequestForItem(state, itemId);
        return latest?.id == retryMessageId && latest?.isMine == true;
      }
      return _canSendRentalRequest(inquiry);
    }

    if (!canSend()) return;

    final ItemDetail itemDetail;
    try {
      final fetchItemDetail =
          widget.fetchItemDetail ?? ItemDetailRemoteDataSource().fetchById;
      itemDetail = await fetchItemDetail(itemId);
    } catch (_) {
      if (mounted)
        showAppPopup(
          context,
          content: Text('โหลดข้อมูลจุดนัดรับไม่สำเร็จ กรุณาลองใหม่'),
        );
      return;
    }
    if (!mounted) return;
    if (itemDetail.isOwner ||
        itemDetail.owner.userId != _conversation.otherUserId) {
      showAppPopup(
        context,
        content: const Text('ส่งคำขอเช่าได้ในห้องแชทกับเจ้าของอุปกรณ์'),
      );
      return;
    }
    if (queueMessageId == null &&
        (itemDetail.isRentalOccupied || itemDetail.isRentalQueueHeld)) {
      showAppPopup(
        context,
        content: Text(
          itemDetail.isRentalOccupied
              ? 'อุปกรณ์นี้กำลังถูกเช่า กรุณารอให้อุปกรณ์พร้อมให้เช่า'
              : 'อุปกรณ์นี้มีผู้ได้สิทธิ์จากคิวเช่าต่อ ผู้ได้สิทธิ์ส่งคำขอได้จากการ์ดคิว',
        ),
      );
      return;
    }
    final pickup = itemDetail.pickupLocation;
    if (pickup == null) {
      showAppPopup(
        context,
        content: Text(
          'กรุณาให้ผู้ปล่อยเช่าระบุจุดนัดรับในประกาศก่อนส่งคำขอเช่า',
        ),
      );
      return;
    }
    if (!canSend()) return;

    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final today = DateUtils.dateOnly(now);
    final rentalType = itemDetail.hourlyPrice == null
        ? BookingRentalType.daily
        : BookingRentalType.hourly;
    final pickupDate = rentalType == BookingRentalType.hourly && now.hour >= 9
        ? DateUtils.addDaysToDate(today, 1)
        : today;

    final itemInfo = BookingItemInfo(
      id: itemId,
      title: itemDetail.name,
      imageUrl: itemDetail.imageUrls.firstOrNull ?? '',
      rating: itemDetail.averageRating,
      reviewCount: itemDetail.reviews.length,
      hourlyRate: itemDetail.hourlyPrice?.toDouble() ?? 0,
      dailyRate: itemDetail.dailyPrice?.toDouble() ?? 0,
      penaltyTerms: itemDetail.penaltyTerms,
      defaultLocation: pickup.name,
      latitude: pickup.latitude,
      longitude: pickup.longitude,
      ownerName: itemDetail.owner.displayName,
    );

    final bookingData = BookingRequestData(
      item: itemInfo,
      rentalType: rentalType,
      startDate: pickupDate,
      endDate: rentalType == BookingRentalType.daily
          ? DateUtils.addDaysToDate(pickupDate, 1)
          : pickupDate,
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 17, minute: 0),
      location: pickup.name,
      locationNote: pickup.note,
      locationAddress: pickup.address,
      latitude: pickup.latitude,
      longitude: pickup.longitude,
      conversationId: _conversation.id,
      ownerId: itemDetail.owner.userId,
      rentalQueueMessageId: int.tryParse(queueMessageId ?? ''),
      isCustomerRequest: true,
    );

    await AppRoutes.openBooking(context, initialData: bookingData);
    if (mounted) _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final currentQueueItem = _rentalQueueItems
        .where((item) => item.id == _conversation.itemId)
        .firstOrNull;
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
                    unawaited(
                      _refreshRentalAvailability(onlyWhenItemsChange: true),
                    );
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
                      return switch (state.status) {
                        ChatDetailStatus.success => ChatEmptyView(
                          conversation: _conversation,
                        ),
                        ChatDetailStatus.failure => const SizedBox.shrink(),
                        _ => const ChatSkeletonLoadingView(),
                      };
                    }

                    final inquiryReplacements = _inquiryReplacements(state);
                    final linkedRequestIds = inquiryReplacements.values.toSet();
                    final renderItems = _buildRenderItems(
                      state.messages,
                      inquiryReplacements,
                    );
                    final messagesById = {
                      for (final message in state.messages) message.id: message,
                    };
                    final initialMessageId =
                        inquiryReplacements[widget.initialMessageId] ??
                        widget.initialMessageId;

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
                      initialMessageId: initialMessageId == null
                          ? null
                          : renderItems
                                .where(
                                  (item) =>
                                      item.containsMessage(initialMessageId),
                                )
                                .firstOrNull
                                ?.message
                                .id,
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

                        final inquiry = _itemInquiry(item.message);
                        final ownsInquiryItem = state.ownedItemIds.contains(
                          inquiry?.itemId,
                        );
                        // เก็บข้อความสอบถามรอบใหม่ไว้เมื่อคิวหรือสถานะอุปกรณ์เปลี่ยน
                        if (inquiry
                            case ItemInquiryData(
                              itemId: final int itemId,
                              :final itemName,
                              previousBookingId: null,
                            )
                            when item.message.isMine &&
                                !ownsInquiryItem &&
                                context
                                    .read<ChatDetailBloc>()
                                    .hasResolvedItemOwnership(itemId) &&
                                _hasRentalAvailability(itemId) &&
                                !_conversation.isOtherUserUnavailable &&
                                !state.failedMessageIds.contains(
                                  item.message.id,
                                )) {
                          final canQueue = _canRequestRentalQueueForItem(
                            itemId,
                          );
                          if (canQueue ||
                              (_rentalAvailability[itemId] == false &&
                                  !_hasOwnOpenRental(state, itemId))) {
                            return _RentalUnavailableNotice(
                              key: itemKey,
                              itemName: itemName,
                              canQueue: canQueue,
                            );
                          }
                        }
                        final booking = BookingRequestData.fromChatMessage(
                          item.message.message,
                        );
                        final isOwner = booking == null
                            ? ownsInquiryItem
                            : item.message.isMine != booking.isCustomerRequest;
                        final isUnqueuedCustomerRequest =
                            booking != null &&
                            booking.isCustomerRequest &&
                            booking.rentalQueueMessageId == null;
                        final canRequestQueueForItem =
                            isUnqueuedCustomerRequest &&
                            item.message.isMine &&
                            _canRequestRentalQueueForItem(booking.item.id);
                        final customerRequestAvailabilityPending =
                            isUnqueuedCustomerRequest &&
                            !_hasRentalAvailability(booking.item.id);
                        final customerRequestBlockedByRental =
                            isUnqueuedCustomerRequest &&
                            (_rentalAvailability[booking.item.id] == false ||
                                canRequestQueueForItem);
                        final isLatestCustomerRequest =
                            isUnqueuedCustomerRequest &&
                            item.message.isMine &&
                            _latestRentalRequestForItem(
                                  state,
                                  booking.item.id,
                                )?.id ==
                                item.message.id;

                        final rentalQueue = RentalQueueCardData.fromMessage(
                          item.message.message,
                        );
                        final attachedQueue = item.attachedQueue;

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
                                isReadOnly:
                                    _conversation.isOtherUserUnavailable,
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
                                    !_conversation.isOtherUserUnavailable &&
                                        inquiry != null &&
                                        item.message.isMine &&
                                        _canSendRentalRequest(inquiry)
                                    ? _openBookingRequest
                                    : null,
                                onRetryCustomerRequest:
                                    !_conversation.isOtherUserUnavailable &&
                                        isLatestCustomerRequest &&
                                        linkedRequestIds.contains(
                                          item.message.id,
                                        )
                                    ? () => _openBookingRequest(
                                        ItemInquiryData(
                                          itemId: booking.item.id,
                                          itemName: booking.item.title,
                                        ),
                                        retryMessageId: item.message.id,
                                      )
                                    : null,
                                customerRequestBlockedByRental:
                                    customerRequestBlockedByRental,
                                customerRequestAvailabilityPending:
                                    customerRequestAvailabilityPending,
                                onRequestRentalQueue:
                                    !_conversation.isOtherUserUnavailable &&
                                        isLatestCustomerRequest &&
                                        canRequestQueueForItem
                                    ? () => _joinRentalQueueForItem(
                                        booking.item.id,
                                      )
                                    : null,
                                defaultItemId: _conversation.itemId,
                                onQueueAction:
                                    _conversation.isOtherUserUnavailable
                                    ? null
                                    : (action) => _updateRentalQueue(
                                        item.message,
                                        action,
                                      ),
                                onSendQueuedRequest: _queuedRentalRequestAction(
                                  item.message,
                                  rentalQueue,
                                  state,
                                ),
                                onRetry: () {
                                  context.read<ChatDetailBloc>().add(
                                    ChatRetryMessageSent(
                                      conversationId: widget.conversation.id,
                                      tempMessageId: item.message.id,
                                    ),
                                  );
                                },
                                onReply: _conversation.isOtherUserUnavailable
                                    ? null
                                    : _handleReply,
                                onEdit:
                                    !_conversation.isOtherUserUnavailable &&
                                        item.message.isMine
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
                              if (attachedQueue != null)
                                ChatMessageBubble(
                                  key: ValueKey(attachedQueue.message.id),
                                  message: attachedQueue.message,
                                  isReadOnly:
                                      _conversation.isOtherUserUnavailable,
                                  queueAlignment: item.message.isMine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  onQueueAction:
                                      _conversation.isOtherUserUnavailable
                                      ? null
                                      : (action) => _updateRentalQueue(
                                          attachedQueue.message,
                                          action,
                                        ),
                                  onSendQueuedRequest:
                                      _queuedRentalRequestAction(
                                        attachedQueue.message,
                                        attachedQueue.data,
                                        state,
                                      ),
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
              if (_conversation.isOtherUserUnavailable ||
                  !state.isOtherUserTyping) {
                return const SizedBox.shrink();
              }
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
          if (!_conversation.isOtherUserUnavailable && currentQueueItem != null)
            BlocBuilder<ChatDetailBloc, ChatDetailState>(
              builder: (context, state) {
                final rentalHistory = _rentalHistory(state);
                if (rentalHistory.completed.containsKey((
                  true,
                  currentQueueItem.id,
                ))) {
                  return const SizedBox.shrink();
                }
                final inquiryReplacements = _inquiryReplacements(
                  state,
                  rentalHistory: rentalHistory,
                );
                final hasInquiry = state.messages.any(
                  (message) =>
                      message.isMine &&
                      !state.ownedItemIds.contains(currentQueueItem.id) &&
                      !state.failedMessageIds.contains(message.id) &&
                      !inquiryReplacements.containsKey(message.id) &&
                      _itemInquiry(message)?.itemId == currentQueueItem.id,
                );
                return hasInquiry
                    ? const SizedBox.shrink()
                    : _RentalUnavailableNotice(
                        itemName: currentQueueItem.name,
                        canQueue: true,
                      );
              },
            ),
          if (!_conversation.isOtherUserUnavailable)
            ChatMessageComposer(
              controller: _messageController,
              onSend: _sendMessage,
              onCamera: _handleCameraPick,
              onGallery: _handleGalleryPick,
              onRequestRentalQueue: _rentalQueueItems.isNotEmpty
                  ? _requestRentalQueue
                  : null,
              replyingMessage: _replyingMessage,
              editingMessage: _editingMessage,
              onCancelReplyOrEdit: _cancelReplyOrEdit,
            ),
        ],
      ),
    );
  }

  _RentalHistory _rentalHistory(ChatDetailState state) {
    final completed = <(bool, int), ({String messageId, int? bookingId})>{};
    final retainedBookingIds = <int>{};
    for (final message in state.messages) {
      if (message.id.startsWith('temp_') ||
          state.failedMessageIds.contains(message.id)) {
        continue;
      }
      final booking = BookingRequestData.fromChatMessage(message.message);
      if (booking == null) continue;
      final bookingId =
          booking.bookingId ??
          BookingConfirmationTracker.getCachedBookingId(message.id);
      if (bookingId != null) retainedBookingIds.add(bookingId);
      if (!_completedRentalStatuses.contains(booking.status)) continue;

      // คำขอมาจากผู้เช่า ส่วนข้อเสนอแบบเดิมมาจากผู้ปล่อยเช่า
      final renterIsViewer = message.isMine == booking.isCustomerRequest;
      completed[(renterIsViewer, booking.item.id)] = (
        messageId: message.id,
        bookingId: bookingId,
      );
    }
    return (completed: completed, retainedBookingIds: retainedBookingIds);
  }

  Map<String, String> _inquiryReplacements(
    ChatDetailState state, {
    _RentalHistory? rentalHistory,
  }) {
    final history = rentalHistory ?? _rentalHistory(state);
    final nextRequest = <(String, int), String>{};
    final renewedInquiries = <(String, int), String>{};
    final replacements = <String, String>{};
    for (final message in state.messages.reversed) {
      if (message.id.startsWith('temp_') ||
          state.failedMessageIds.contains(message.id)) {
        continue;
      }
      final booking = BookingRequestData.fromChatMessage(message.message);
      if (booking != null && booking.isCustomerRequest) {
        nextRequest[(message.senderId, booking.item.id)] = message.id;
        continue;
      }
      final inquiry = _itemInquiry(message);
      final itemId = inquiry?.itemId;
      if (inquiry == null || itemId == null) continue;
      final key = (message.senderId, itemId);
      final requestId = nextRequest[key];
      if (requestId != null) {
        replacements[message.id] = requestId;
        continue;
      }
      final previous = history.completed[(message.isMine, itemId)];
      final previousBookingId = previous?.bookingId;
      if (previous != null &&
          (previousBookingId == null ||
              !inquiry.followsBooking(previousBookingId))) {
        replacements[message.id] = previous.messageId;
        continue;
      }

      // เมื่อคำขอหมดเวลาถูกลบ ให้การ์ดสอบถามรอบใหม่แทนการ์ดเดิมของรายการเดียวกัน
      final renewedId = renewedInquiries[key];
      if (renewedId != null) {
        replacements[message.id] = renewedId;
      } else if (inquiry.previousBookingId case final int bookingId
          when !history.retainedBookingIds.contains(bookingId)) {
        renewedInquiries[key] = message.id;
      }
    }
    return replacements;
  }

  List<_ChatRenderItem> _buildRenderItems(
    List<ChatMessage> messages,
    Map<String, String> inquiryReplacements,
  ) {
    final messageIds = {for (final message in messages) message.id};
    final queuesByNoticeId = <String, _AttachedRentalQueue>{};
    final relocatedQueueIds = <String>{};
    for (final message in messages) {
      final queue = RentalQueueCardData.fromMessage(message.message);
      final noticeId = queue?.readyMessageId;
      if (queue == null ||
          noticeId == null ||
          noticeId == message.id ||
          !messageIds.contains(noticeId)) {
        continue;
      }
      queuesByNoticeId[noticeId] = (message: message, data: queue);
      relocatedQueueIds.add(message.id);
    }

    final List<_ChatRenderItem> items = [];
    int i = 0;
    while (i < messages.length) {
      final msg = messages[i];
      if (msg.message.trimLeft().startsWith('📞') ||
          inquiryReplacements.containsKey(msg.id) ||
          relocatedQueueIds.contains(msg.id)) {
        i++;
        continue;
      }

      final queue = RentalQueueCardData.fromMessage(msg.message);
      if (queue != null &&
          queue.status == RentalQueueStatus.invited &&
          queue.isRenterView(isSender: msg.isMine) &&
          !_rentalQueueItems.any((item) => item.id == queue.itemId)) {
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
            attachedQueue: queuesByNoticeId[msg.id],
          ),
        );
        i++;
      }
    }
    return items;
  }

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

typedef _RentalHistory = ({
  Map<(bool, int), ({String messageId, int? bookingId})> completed,
  Set<int> retainedBookingIds,
});

typedef _AttachedRentalQueue = ({
  ChatMessage message,
  RentalQueueCardData data,
});

class _RentalUnavailableNotice extends StatelessWidget {
  const _RentalUnavailableNotice({
    super.key,
    required this.itemName,
    required this.canQueue,
  });

  final String itemName;
  final bool canQueue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF0E5FC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: AppColors.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (itemName.isNotEmpty)
                      Text(
                        itemName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    Text(
                      canQueue
                          ? 'อุปกรณ์นี้กำลังถูกเช่า กรุณาต่อคิวเพื่อเช่าต่อ'
                          : 'อุปกรณ์นี้ยังไม่พร้อมให้เช่า',
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

class _ChatRenderItem {
  const _ChatRenderItem({
    required this.message,
    required this.imageUrls,
    this.messageIds = const [],
    this.isStacked = false,
    this.attachedQueue,
  });

  final ChatMessage message;
  final List<String> imageUrls;
  final List<String> messageIds;
  final bool isStacked;
  final _AttachedRentalQueue? attachedQueue;

  bool containsMessage(String id) =>
      message.id == id ||
      messageIds.contains(id) ||
      attachedQueue?.message.id == id;
}

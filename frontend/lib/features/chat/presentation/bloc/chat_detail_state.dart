import 'package:equatable/equatable.dart';
import '../../domain/entities/chat_message.dart';

enum ChatDetailStatus { initial, loading, success, failure }

class ChatDetailState extends Equatable {
  const ChatDetailState({
    this.status = ChatDetailStatus.initial,
    this.messages = const [],
    this.isSending = false,
    this.isFetchingOlder = false,
    this.hasReachedMax = false,
    this.isUploadingImage = false,
    this.isOtherUserTyping = false,
    this.failedMessageIds = const {},
    this.sendingMessageIds = const {},
    this.ownedItemIds = const {},
    this.errorMessage,
  });

  final ChatDetailStatus status;
  final List<ChatMessage> messages;
  final bool isSending;
  final bool isFetchingOlder;
  final bool hasReachedMax;
  final bool isUploadingImage;
  final bool isOtherUserTyping;
  final Set<String> failedMessageIds;
  // แยกสถานะรอเครือข่ายออกจากข้อความที่บันทึกสำเร็จแล้ว
  final Set<String> sendingMessageIds;
  final Set<int> ownedItemIds;
  final String? errorMessage;

  ChatDetailState copyWith({
    ChatDetailStatus? status,
    List<ChatMessage>? messages,
    bool? isSending,
    bool? isFetchingOlder,
    bool? hasReachedMax,
    bool? isUploadingImage,
    bool? isOtherUserTyping,
    Set<String>? failedMessageIds,
    Set<String>? sendingMessageIds,
    Set<int>? ownedItemIds,
    String? errorMessage,
  }) {
    return ChatDetailState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      isFetchingOlder: isFetchingOlder ?? this.isFetchingOlder,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isUploadingImage: isUploadingImage ?? this.isUploadingImage,
      isOtherUserTyping: isOtherUserTyping ?? this.isOtherUserTyping,
      failedMessageIds: failedMessageIds ?? this.failedMessageIds,
      sendingMessageIds: sendingMessageIds ?? this.sendingMessageIds,
      ownedItemIds: ownedItemIds ?? this.ownedItemIds,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    messages,
    isSending,
    isFetchingOlder,
    hasReachedMax,
    isUploadingImage,
    isOtherUserTyping,
    failedMessageIds,
    sendingMessageIds,
    ownedItemIds,
    errorMessage,
  ];
}

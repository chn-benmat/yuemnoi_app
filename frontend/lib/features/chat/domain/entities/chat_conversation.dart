import 'package:equatable/equatable.dart';

enum ChatParticipantRole { owner, renter }

class ChatConversation extends Equatable {
  const ChatConversation({
    required this.id,
    required this.otherUserId,
    required this.name,
    required this.role,
    required this.avatarAsset,
    required this.preview,
    required this.timeLabel,
    this.lastMessageAt,
    this.itemId,
    this.itemName,
    this.itemImageUrl,
    this.itemPrice,
    this.itemRentalType,
    this.itemRentalRole,
    this.isOnline = false,
    this.hasUnreadMessage = false,
  });

  final String id;
  final String otherUserId;
  final String name;
  // บทบาทของคู่สนทนาตามข้อมูลห้องตอนสร้าง
  final ChatParticipantRole role;
  final String avatarAsset;
  final String preview;
  final String timeLabel;
  final DateTime? lastMessageAt;
  final int? itemId;
  final String? itemName;
  final String? itemImageUrl;
  final int? itemPrice;
  final String? itemRentalType;
  final ChatParticipantRole? itemRentalRole;
  final bool isOnline;
  final bool hasUnreadMessage;

  ChatParticipantRole get currentUserRentalRole =>
      itemRentalRole ??
      (role == ChatParticipantRole.owner
          ? ChatParticipantRole.renter
          : ChatParticipantRole.owner);

  ChatConversation copyWith({
    String? id,
    String? otherUserId,
    String? name,
    ChatParticipantRole? role,
    String? avatarAsset,
    String? preview,
    String? timeLabel,
    DateTime? lastMessageAt,
    int? itemId,
    String? itemName,
    String? itemImageUrl,
    int? itemPrice,
    String? itemRentalType,
    ChatParticipantRole? itemRentalRole,
    bool? isOnline,
    bool? hasUnreadMessage,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      otherUserId: otherUserId ?? this.otherUserId,
      name: name ?? this.name,
      role: role ?? this.role,
      avatarAsset: avatarAsset ?? this.avatarAsset,
      preview: preview ?? this.preview,
      timeLabel: timeLabel ?? this.timeLabel,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      itemImageUrl: itemImageUrl ?? this.itemImageUrl,
      itemPrice: itemPrice ?? this.itemPrice,
      itemRentalType: itemRentalType ?? this.itemRentalType,
      itemRentalRole: itemRentalRole ?? this.itemRentalRole,
      isOnline: isOnline ?? this.isOnline,
      hasUnreadMessage: hasUnreadMessage ?? this.hasUnreadMessage,
    );
  }

  @override
  List<Object?> get props => [
    id,
    otherUserId,
    name,
    role,
    avatarAsset,
    preview,
    timeLabel,
    lastMessageAt,
    itemId,
    itemName,
    itemImageUrl,
    itemPrice,
    itemRentalType,
    itemRentalRole,
    isOnline,
    hasUnreadMessage,
  ];
}

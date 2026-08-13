enum ChatParticipantRole { owner, renter }

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.name,
    required this.role,
    required this.avatarAsset,
    required this.preview,
    required this.timeLabel,
    this.isOnline = false,
    this.hasUnreadMessage = false,
  });

  final String id;
  final String name;
  final ChatParticipantRole role;
  final String avatarAsset;
  final String preview;
  final String timeLabel;
  final bool isOnline;
  final bool hasUnreadMessage;
}

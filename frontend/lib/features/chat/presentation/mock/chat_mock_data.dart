import '../../domain/entities/chat_conversation.dart';

abstract final class ChatMockData {
  static const conversations = <ChatConversation>[
    ChatConversation(
      id: 'sarah-jenkins',
      name: 'ซาร่า เจนกินส์',
      role: ChatParticipantRole.owner,
      avatarAsset: 'assets/images/chat_sarah.png',
      preview: 'สวัสดีฉันเห็นว่าคุณสนใจอุปกรณ์กล้องถ่ายรูป',
      timeLabel: '2 นาที',
      isOnline: true,
      hasUnreadMessage: true,
    ),
    ChatConversation(
      id: 'marcus-jane',
      name: 'มาคัส เจน',
      role: ChatParticipantRole.owner,
      avatarAsset: 'assets/images/chat_marcus.png',
      preview: 'ฉันต้องการที่จะเช่าเต็นท์นี้ขอรายละเอียดได้ไหม',
      timeLabel: '1 ชั่วโมง',
    ),
    ChatConversation(
      id: 'elena-jai',
      name: 'เอเลน่า ใจดี',
      role: ChatParticipantRole.renter,
      avatarAsset: 'assets/images/chat_elena.png',
      preview: 'ขอบคุณสำหรับเครื่องชงกาแฟนะ ใช้ดีมากเลย',
      timeLabel: '1 วัน',
    ),
  ];
}

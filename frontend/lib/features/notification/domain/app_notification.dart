class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.conversationId,
    this.updatedAt,
    this.isRead = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: '${json['notification_id'] ?? json['id'] ?? ''}',
        type: '${json['type'] ?? ''}',
        title: '${json['title'] ?? ''}',
        body: '${json['body'] ?? ''}',
        conversationId: json['conversation_id'] as String?,
        updatedAt: DateTime.tryParse('${json['updated_at']}'),
        isRead: json['is_read'] == true,
      );

  final String id;
  final String type;
  final String title;
  final String body;
  final String? conversationId;
  final DateTime? updatedAt;
  final bool isRead;

  bool get isReturnReminder =>
      type == 'rental_due_1h' || type == 'rental_due_30m';
  bool get isConversationMessage =>
      type == 'chat_message' || type == 'rental_request_received';
}

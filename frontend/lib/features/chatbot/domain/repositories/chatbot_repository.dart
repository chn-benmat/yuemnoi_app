import '../entities/chat_message.dart';

class ChatbotException implements Exception {
  const ChatbotException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ChatbotRepository {
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
  });

  void close();
}

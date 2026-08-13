import '../../../../core/network/api_client.dart';
import '../../domain/entities/chat_message.dart';
import '../models/chat_response_model.dart';

class ChatbotRemoteException implements Exception {
  const ChatbotRemoteException(this.message);

  final String message;
}

class ChatbotRemoteDataSource {
  ChatbotRemoteDataSource({ApiClient? client})
    : _client =
          client ?? DioApiClient(requestTimeout: const Duration(seconds: 70));

  static const _chatPath = '/api/v1/chat-ai';

  final ApiClient _client;

  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
  }) async {
    try {
      final response = await _client.post(
        _chatPath,
        data: {
          'query': query.trim(),
          'history': history
              .map(
                (message) => {
                  'role': message.role.apiValue,
                  'content': message.content,
                },
              )
              .toList(growable: false),
        },
      );

      if (response.statusCode == 200) {
        try {
          return ChatResponseModel.fromJson(response.data).toEntity();
        } on FormatException {
          throw const ChatbotRemoteException(
            'ข้อมูลตอบกลับจากผู้ช่วยไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง',
          );
        }
      }

      throw ChatbotRemoteException(_errorMessage(response.statusCode));
    } on ApiClientException catch (error) {
      throw ChatbotRemoteException(_requestErrorMessage(error.type));
    }
  }

  String _errorMessage(int statusCode) {
    if (statusCode == 400 || statusCode == 422) {
      return 'คำถามไม่ถูกต้องหรือยาวเกินไป กรุณาลองพิมพ์ใหม่';
    }
    if (statusCode >= 500) {
      return 'ผู้ช่วย AI ยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง';
    }
    return 'ส่งข้อความไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _requestErrorMessage(ApiClientErrorType type) {
    return switch (type) {
      ApiClientErrorType.timeout =>
        'ผู้ช่วย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง',
      ApiClientErrorType.connection =>
        'ไม่สามารถเชื่อมต่อผู้ช่วย AI ได้ กรุณาตรวจสอบอินเทอร์เน็ต',
      ApiClientErrorType.invalidResponse =>
        'ข้อมูลตอบกลับจากผู้ช่วยไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง',
    };
  }

  void close() {
    _client.close();
  }
}

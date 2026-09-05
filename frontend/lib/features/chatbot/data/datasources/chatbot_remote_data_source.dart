import 'dart:convert';

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
  static const _chatStreamPath = '/api/v1/chat-ai/stream';
  static const _feedbackPath = '/api/v1/chat-ai/feedback';

  final ApiClient _client;

  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
  }) async* {
    Stream<String> lineStream;
    try {
      lineStream = await _client.postStream(
        _chatStreamPath,
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
    } on ApiClientException catch (error) {
      throw ChatbotRemoteException(_requestErrorMessage(error.type));
    } catch (_) {
      throw const ChatbotRemoteException('ส่งข้อความไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    }

    String? currentEvent;
    await for (final line in lineStream) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        currentEvent = null;
        continue;
      }

      if (trimmed.startsWith('event:')) {
        currentEvent = trimmed.substring(6).trim();
        continue;
      }

      if (trimmed.startsWith('data:')) {
        final rawData = trimmed.substring(5).trim();
        if (rawData.isEmpty) continue;

        try {
          final decoded = jsonDecode(rawData);
          if (decoded is! Map<String, dynamic>) continue;

          switch (currentEvent) {
            case 'status':
              yield ChatStatusEvent(
                step: decoded['step'] as String? ?? '',
                message: decoded['message'] as String? ?? '',
              );
            case 'metadata':
              final rawItems = decoded['recommended_items'] as List<dynamic>? ?? const [];
              final rawQuestions = decoded['questions'] as List<dynamic>? ?? const [];
              yield ChatMetadataEvent(
                mode: decoded['mode'] as String? ?? 'recommendation',
                recommendedItems: rawItems
                    .whereType<Map>()
                    .map(
                      (item) => RecommendedItemModel.fromJson(
                        item.map((k, v) => MapEntry(k.toString(), v)),
                      ).toEntity(),
                    )
                    .toList(growable: false),
                questions: rawQuestions
                    .whereType<Map>()
                    .map(
                      (q) => ClarificationQuestionModel.fromJson(
                        q.map((k, v) => MapEntry(k.toString(), v)),
                      ).toEntity(),
                    )
                    .toList(growable: false),
              );
            case 'delta':
              final text = decoded['text'] as String? ?? '';
              if (text.isNotEmpty) {
                yield ChatDeltaEvent(text: text);
              }
            case 'done':
              final rawReplies = decoded['suggested_replies'] as List<dynamic>? ?? const [];
              final rawItems = decoded['recommended_items'] as List<dynamic>? ?? const [];
              final rawQuestions = decoded['questions'] as List<dynamic>? ?? const [];
              yield ChatDoneEvent(
                suggestedReplies: rawReplies.map((e) => e.toString()).toList(growable: false),
                recommendedItems: rawItems
                    .whereType<Map>()
                    .map(
                      (item) => RecommendedItemModel.fromJson(
                        item.map((k, v) => MapEntry(k.toString(), v)),
                      ).toEntity(),
                    )
                    .toList(growable: false),
                questions: rawQuestions
                    .whereType<Map>()
                    .map(
                      (q) => ClarificationQuestionModel.fromJson(
                        q.map((k, v) => MapEntry(k.toString(), v)),
                      ).toEntity(),
                    )
                    .toList(growable: false),
              );
            default:
              if (decoded.containsKey('text')) {
                yield ChatDeltaEvent(text: decoded['text'] as String);
              }
          }
        } catch (_) {
          // Skip malformed chunk safely
        }
      }
    }
  }

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

  Future<void> sendFeedback({
    required String messageId,
    required String userQuery,
    required String aiResponse,
    required int rating,
    String? reasonCategory,
    String? feedbackComment,
    String? resolvedMode,
  }) async {
    try {
      await _client.post(
        _feedbackPath,
        data: {
          'message_id': messageId,
          'user_query': userQuery,
          'ai_response': aiResponse,
          'rating': rating,
          if (reasonCategory != null && reasonCategory.isNotEmpty)
            'reason_category': reasonCategory,
          if (feedbackComment != null && feedbackComment.isNotEmpty)
            'feedback_comment': feedbackComment,
          if (resolvedMode != null && resolvedMode.isNotEmpty)
            'resolved_mode': resolvedMode,
        },
      );
    } catch (_) {
      // Feedback submission is optimistic/non-blocking
    }
  }

  void close() {
    _client.close();
  }
}

import 'dart:async';
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
          client ?? DioApiClient(requestTimeout: const Duration(seconds: 60));

  static const _chatPath = '/api/v1/chat-ai';
  static const _chatStreamPath = '/api/v1/chat-ai/stream';

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
              .skip(history.length > 6 ? history.length - 6 : 0)
              .map(
                (message) => {
                  'role': message.role.apiValue,
                  'content': _historyContent(message),
                },
              )
              .toList(growable: false),
        },
      );
    } on ApiClientException catch (error) {
      throw ChatbotRemoteException(_requestErrorMessage(error.type));
    } catch (_) {
      throw const ChatbotRemoteException(
        'ส่งข้อความไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
      );
    }

    String? currentEvent;
    var completed = false;
    try {
      await for (final line in lineStream.timeout(const Duration(seconds: 45))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) {
          if (trimmed.isEmpty) currentEvent = null;
          continue;
        }

      if (trimmed.startsWith('event:')) {
        currentEvent = trimmed.substring(6).trim();
        continue;
      }

      if (trimmed.startsWith('data:')) {
        final rawData = trimmed.substring(5).trim();
        if (rawData.isEmpty) continue;
        if (rawData == '[DONE]') {
          completed = true;
          break;
        }

        try {
          final decoded = jsonDecode(rawData);
          if (decoded is! Map<String, dynamic>) continue;

          if (currentEvent == 'error' || decoded['status'] == 'error') {
            throw ChatbotRemoteException(
              _modelError(decoded['error_code'] as String?),
            );
          }
          switch (currentEvent) {
            case 'status':
              yield ChatStatusEvent(
                step: decoded['step'] as String? ?? '',
                message: decoded['message'] as String? ?? '',
              );
            case 'metadata':
              final rawItems =
                  decoded['recommended_items'] as List<dynamic>? ?? const [];
              final rawQuestions =
                  decoded['questions'] as List<dynamic>? ?? const [];
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
              completed = true;
              final rawReplies =
                  decoded['suggested_replies'] as List<dynamic>? ?? const [];
              final rawItems =
                  decoded['recommended_items'] as List<dynamic>? ?? const [];
              final rawQuestions =
                  decoded['questions'] as List<dynamic>? ?? const [];
              final rawSources =
                  decoded['search_sources'] as List<dynamic>? ?? const [];
              final thought = decoded['thought'] as String?;
              final searchQuery = decoded['search_query'] as String?;
              final answer = decoded['answer'] as String?;
              final rawActivities =
                  decoded['activities'] as List<dynamic>? ?? const [];
              yield ChatDoneEvent(
                answer: answer?.trim().isNotEmpty == true
                    ? answer!.trim()
                    : null,
                suggestedReplies: rawReplies
                    .map((e) => e.toString())
                    .toList(growable: false),
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
                thought: thought?.trim().isNotEmpty == true
                    ? thought!.trim()
                    : null,
                searchSources: rawSources
                    .whereType<Map>()
                    .map(
                      (s) => SearchSourceModel.fromJson(
                        s.map((k, v) => MapEntry(k.toString(), v)),
                      ).toEntity(),
                    )
                    .toList(growable: false),
                searchQuery: searchQuery?.trim().isNotEmpty == true
                    ? searchQuery!.trim()
                    : null,
                activities: rawActivities
                    .map((e) => e.toString())
                    .toList(growable: false),
              );
            default:
              if (decoded.containsKey('text')) {
                yield ChatDeltaEvent(text: decoded['text'] as String);
              }
          }
        } on ChatbotRemoteException {
          rethrow;
        } catch (_) {
          if (completed) break;
          throw const ChatbotRemoteException(
            'ข้อมูลตอบกลับจากผู้ช่วยไม่ถูกต้อง กรุณาลองใหม่',
          );
        }
      }
    }
  } on TimeoutException {
    throw const ChatbotRemoteException(
      'ผู้ช่วย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง',
    );
  }
  if (!completed) {
    throw const ChatbotRemoteException('การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่');
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
              .skip(history.length > 6 ? history.length - 6 : 0)
              .map(
                (message) => {
                  'role': message.role.apiValue,
                  'content': _historyContent(message),
                },
              )
              .toList(growable: false),
        },
      );

      if (response.statusCode == 200) {
        if (response.data['status'] == 'error') {
          throw ChatbotRemoteException(
            _modelError(response.data['error_code'] as String?),
          );
        }
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

  // ส่งบริบทคำถามจริงให้โมเดลเข้าใจคำตอบช้อย โดยไม่เดาจากข้อความ
  String _historyContent(ChatMessage message) {
    final content = message.content.length > 1500
        ? message.content.substring(0, 1500)
        : message.content;
    if (message.questions.isEmpty && message.recommendedItems.isEmpty) {
      return content;
    }
    return jsonEncode({
      'answer': content,
      'questions': message.questions
          .map(
            (q) => {
              'title': q.title,
              'options': q.options,
              'selected': q.selectedOption,
            },
          )
          .toList(),
      'items': message.recommendedItems
          .map((i) => {'id': i.id, 'name': i.name})
          .toList(),
    });
  }

  String _modelError(String? code) {
    return code == 'timeout'
        ? 'ผู้ช่วย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง'
        : 'ยังไม่สามารถยืนยันคำตอบได้ กรุณาลองใหม่อีกครั้ง';
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

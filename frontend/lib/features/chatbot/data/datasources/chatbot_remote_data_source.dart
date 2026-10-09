import 'dart:async';
import 'dart:convert';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/chat_message.dart';
import '../models/chat_response_model.dart';
import '../models/chat_context_model.dart';
import '../models/chat_understanding_model.dart';

class ChatbotRemoteException implements Exception {
  const ChatbotRemoteException(
    this.message, {
    this.errorCode,
    this.statusCode,
    this.retryAfterSeconds,
  });

  final String message;
  final String? errorCode;
  final int? statusCode;
  final int? retryAfterSeconds;
}

class ChatbotRemoteDataSource {
  ChatbotRemoteDataSource({
    ApiClient? client,
    this.historyMaxMessages = const int.fromEnvironment(
      'AI_CHAT_HISTORY_MAX_MESSAGES',
      defaultValue: 16,
    ),
    this.historyMaxCharacters = const int.fromEnvironment(
      'AI_CHAT_HISTORY_MAX_CHARACTERS',
      defaultValue: 24000,
    ),
    this.idleTimeout = const Duration(
      seconds: int.fromEnvironment(
        'AI_CHAT_IDLE_TIMEOUT_SECONDS',
        defaultValue: 20,
      ),
    ),
  }) : _client =
           client ??
           DioApiClient(
             requestTimeout: const Duration(
               seconds: int.fromEnvironment(
                 'AI_CHAT_REQUEST_TIMEOUT_SECONDS',
                 defaultValue: 45,
               ),
             ),
           );

  static const _chatPath = '/api/chat-ai';
  static const _chatStreamPath = '/api/chat-ai/stream';

  final ApiClient _client;
  final int historyMaxMessages;
  final int historyMaxCharacters;
  final Duration idleTimeout;

  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async* {
    Stream<String> lineStream;
    try {
      lineStream = await _client.postStream(
        _chatStreamPath,
        data: {
          'query': query.trim(),
          'session_id': sessionId ?? context?.sessionId,
          'active_question_id': ?activeQuestionId,
          if (context != null) 'context': ChatContextModel.toJson(context),
          'questionnaire_answers': questionnaireAnswers
              .map(ChatContextModel.answerJson)
              .toList(),
          'questionnaire_skipped': questionnaireSkipped,
          'history': _history(history),
        },
      );
    } on ApiClientException catch (error) {
      throw _apiException(error);
    } catch (_) {
      throw const ChatbotRemoteException(
        'ส่งข้อความไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
      );
    }

    String? currentEvent;
    var completed = false;
    ChatResponse? readyResponse;
    try {
      await for (final line in lineStream.timeout(idleTimeout)) {
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
            if (!completed) {
              throw const ChatbotRemoteException(
                'การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่',
              );
            }
            break;
          }

          try {
            final decoded = jsonDecode(rawData);
            if (decoded is! Map<String, dynamic>) continue;

            if (currentEvent == 'error' || decoded['status'] == 'error') {
              throw ChatbotRemoteException(
                _modelError(
                  decoded['error_code'] as String?,
                  retryAfterSeconds: decoded['retry_after_seconds'],
                ),
                errorCode: decoded['error_code'] as String?,
                retryAfterSeconds: _retrySeconds(
                  decoded['retry_after_seconds'],
                ),
              );
            }
            switch (currentEvent) {
              case 'ready':
                if (readyResponse != null) {
                  throw const FormatException('Duplicate ready response');
                }
                readyResponse = ChatResponseModel.fromJson(decoded).toEntity();
                yield ChatReadyEvent(response: readyResponse);
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
                  understanding: ChatUnderstandingModel.fromJson(decoded),
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
                if (readyResponse != null &&
                    ChatResponseModel.fromJson(decoded).toEntity() !=
                        readyResponse) {
                  throw const FormatException(
                    'Completed response differs from ready',
                  );
                }
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
                final doneEvent = ChatDoneEvent(
                  understanding: ChatUnderstandingModel.fromJson(decoded),
                  context: ChatContextModel.fromJson(decoded['context']),
                  references: ChatContextModel.references(
                    decoded['references'],
                  ),
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
                completed = true;
                yield doneEvent;
              default:
                if (decoded.containsKey('text')) {
                  yield ChatDeltaEvent(text: decoded['text'] as String);
                }
            }
          } on ChatbotRemoteException {
            rethrow;
          } catch (_) {
            throw const ChatbotRemoteException(
              'ข้อมูลตอบกลับจากยืมหน่อย AI ไม่ถูกต้อง กรุณาลองใหม่',
            );
          }
        }
      }
    } on TimeoutException {
      throw const ChatbotRemoteException(
        'ยืมหน่อย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง',
      );
    } on ApiClientException catch (error) {
      throw _apiException(error);
    }
    if (!completed) {
      throw const ChatbotRemoteException('การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่');
    }
  }

  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async {
    try {
      final response = await _client.post(
        _chatPath,
        data: {
          'query': query.trim(),
          'session_id': sessionId ?? context?.sessionId,
          'active_question_id': ?activeQuestionId,
          if (context != null) 'context': ChatContextModel.toJson(context),
          'questionnaire_answers': questionnaireAnswers
              .map(ChatContextModel.answerJson)
              .toList(),
          'questionnaire_skipped': questionnaireSkipped,
          'history': _history(history),
        },
      );

      if (response.statusCode == 200) {
        if (response.data['status'] == 'error') {
          throw ChatbotRemoteException(
            _modelError(
              response.data['error_code'] as String?,
              retryAfterSeconds:
                  response.data['retry_after_seconds'] ??
                  response.retryAfterSeconds,
            ),
            errorCode: response.data['error_code'] as String?,
            retryAfterSeconds: _retrySeconds(
              response.data['retry_after_seconds'] ??
                  response.retryAfterSeconds,
            ),
          );
        }
        try {
          return ChatResponseModel.fromJson(response.data).toEntity();
        } on FormatException {
          throw const ChatbotRemoteException(
            'ข้อมูลตอบกลับจากยืมหน่อย AI ไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง',
          );
        }
      }

      throw ChatbotRemoteException(
        response.data is Map && response.data['error_code'] is String
            ? _modelError(
                response.data['error_code'] as String,
                retryAfterSeconds:
                    response.data['retry_after_seconds'] ??
                    response.retryAfterSeconds,
              )
            : _errorMessage(response.statusCode),
        statusCode: response.statusCode,
        errorCode: response.data is Map
            ? response.data['error_code'] as String?
            : null,
        retryAfterSeconds: _retrySeconds(
          response.data is Map
              ? response.data['retry_after_seconds'] ??
                    response.retryAfterSeconds
              : response.retryAfterSeconds,
        ),
      );
    } on ApiClientException catch (error) {
      throw _apiException(error);
    }
  }

  // ส่งข้อความและคำถามครบชุด ไม่ตัด JSON กลางประโยค
  List<Map<String, Object?>> _history(List<ChatMessage> messages) {
    final selected = <Map<String, Object?>>[];
    var characters = 0;
    for (final message in messages.reversed) {
      if (message.isFailure) continue;
      final content = _historyContent(message);
      if (selected.length >= historyMaxMessages ||
          characters + content.length > historyMaxCharacters) {
        break;
      }
      selected.add({'role': message.role.apiValue, 'content': content});
      characters += content.length;
    }
    return selected.reversed.toList();
  }

  String _historyContent(ChatMessage message) {
    if (message.questions.isEmpty && message.recommendedItems.isEmpty) {
      return message.content;
    }
    return jsonEncode({
      'answer': message.content,
      'questions': message.questions
          .map(
            (q) => {
              ...ChatContextModel.questionJson(q),
              'selected': q.selectedOption,
              'selected_option_id': q.selectedOptionId,
            },
          )
          .toList(),
      'items': message.recommendedItems
          .map((i) => {'id': i.id, 'name': i.name})
          .toList(),
    });
  }

  String _modelError(String? code, {Object? retryAfterSeconds}) {
    if (code == 'providers_rate_limited' ||
        code == 'quota_temporarily_unavailable' ||
        code == 'quota_exhausted') {
      final reason = code == 'quota_exhausted'
          ? 'โควต้ารายวันของยืมหน่อย AI ไม่เพียงพอสำหรับคำขอนี้'
          : code == 'quota_temporarily_unavailable'
          ? 'ยืมหน่อย AI ติดโควต้าชั่วคราว จึงยังตอบคำขอนี้ไม่ได้'
          : 'ยืมหน่อย AI ติดโควต้า จึงยังตอบคำขอนี้ไม่ได้';
      if (retryAfterSeconds is! num ||
          !retryAfterSeconds.isFinite ||
          retryAfterSeconds <= 0) {
        return '$reason ยังไม่สามารถระบุเวลารอได้ กรุณาลองใหม่ภายหลัง';
      }
      // ปัดขึ้นเพื่อไม่ชวนให้ส่งซ้ำก่อนเวลาที่เซิร์ฟเวอร์ประเมินไว้
      final minutes = (retryAfterSeconds / Duration.secondsPerMinute).ceil();
      final hours = minutes ~/ Duration.minutesPerHour;
      final remainingMinutes = minutes % Duration.minutesPerHour;
      final wait = hours == 0
          ? '$minutes นาที'
          : remainingMinutes == 0
          ? '$hours ชั่วโมง'
          : '$hours ชั่วโมง $remainingMinutes นาที';
      return '$reason โปรดลองอีกครั้งในประมาณ $wait ไม่จำเป็นต้องส่งซ้ำระหว่างรอ';
    }
    if (code == 'providers_busy') {
      return 'ยืมหน่อย AI กำลังประมวลผลคำขออื่น จึงรอคิวไม่ทัน กรุณาลองใหม่อีกครั้ง';
    }
    if (code == 'review_unavailable') {
      return 'ยืมหน่อย AI ยังตรวจสอบคำตอบไม่ได้ จึงยังส่งคำตอบให้ไม่ได้ กรุณาลองใหม่ภายหลัง';
    }
    if (code == 'providers_exhausted') {
      return 'ยืมหน่อย AI ยังไม่พร้อมตอบคำขอนี้ กรุณาลองใหม่ภายหลัง';
    }
    if (code == 'structured_output_invalid') {
      return 'ยืมหน่อย AI สร้างรูปแบบคำตอบไม่สมบูรณ์ กรุณาลองใหม่อีกครั้ง';
    }
    if (code == 'response_quality_rejected') {
      return 'คำตอบของยืมหน่อย AI ยังไม่ผ่านการตรวจสอบคุณภาพ จึงยังแสดงคำตอบไม่ได้ กรุณาลองใหม่อีกครั้ง';
    }
    return code == 'timeout' || code == 'deadline_exceeded'
        ? 'ยืมหน่อย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง'
        : 'ยังไม่สามารถยืนยันคำตอบได้ กรุณาลองใหม่อีกครั้ง';
  }

  String _apiErrorMessage(ApiClientException error) {
    if (error.errorCode != null) {
      return _modelError(
        error.errorCode,
        retryAfterSeconds: error.retryAfterSeconds,
      );
    }
    if (error.statusCode != null) return _errorMessage(error.statusCode!);
    return _requestErrorMessage(error.type);
  }

  ChatbotRemoteException _apiException(ApiClientException error) =>
      ChatbotRemoteException(
        _apiErrorMessage(error),
        errorCode: error.errorCode,
        statusCode: error.statusCode,
        retryAfterSeconds: _retrySeconds(error.retryAfterSeconds),
      );

  // รับเฉพาะเวลาบวกที่เซิร์ฟเวอร์ส่งมา และปัดขึ้นเพื่อไม่ส่งก่อนกำหนด
  static int? _retrySeconds(Object? value) =>
      value is num && value.isFinite && value > 0 ? value.ceil() : null;

  String _errorMessage(int statusCode) {
    if (statusCode == 400 || statusCode == 422) {
      return 'คำถามไม่ถูกต้องหรือยาวเกินไป กรุณาลองพิมพ์ใหม่';
    }
    if (statusCode >= 500) {
      return 'ยืมหน่อย AI ยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง';
    }
    return 'ส่งข้อความไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _requestErrorMessage(ApiClientErrorType type) {
    return switch (type) {
      ApiClientErrorType.timeout =>
        'ยืมหน่อย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง',
      ApiClientErrorType.connection =>
        'ไม่สามารถเชื่อมต่อยืมหน่อย AI ได้ กรุณาตรวจสอบอินเทอร์เน็ต',
      ApiClientErrorType.invalidResponse =>
        'ข้อมูลตอบกลับจากยืมหน่อย AI ไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง',
    };
  }

  void close() {
    _client.close();
  }
}

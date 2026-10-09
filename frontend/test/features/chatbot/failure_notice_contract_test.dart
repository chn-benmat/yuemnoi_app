import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/data/repositories/chatbot_repository_impl.dart';
import 'package:frontend/features/chatbot/domain/entities/chatbot_failure.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_event.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chatbot_state_card.dart';

const _cases = [
  (
    code: 'providers_rate_limited',
    seconds: 59,
    quota: true,
    title: 'ผู้ช่วย AI ติดโควต้า',
    description: 'ติดโควต้า',
    wait: '1 นาที',
  ),
  (
    code: 'quota_temporarily_unavailable',
    seconds: 37,
    quota: true,
    title: 'ผู้ช่วย AI ติดโควต้าชั่วคราว',
    description: 'โควต้าชั่วคราว',
    wait: '1 นาที',
  ),
  (
    code: 'quota_exhausted',
    seconds: 41490,
    quota: true,
    title: 'โควต้ารายวันของผู้ช่วย AI ไม่เพียงพอ',
    description: 'โควต้ารายวัน',
    wait: '11 ชั่วโมง 32 นาที',
  ),
  (
    code: 'providers_busy',
    seconds: null,
    quota: false,
    title: 'ผู้ช่วย AI ติดคิวชั่วคราว',
    description: 'รอคิวไม่ทัน',
    wait: null,
  ),
  (
    code: 'review_unavailable',
    seconds: null,
    quota: false,
    title: 'ผู้ช่วย AI ยังตรวจสอบคำตอบไม่ได้',
    description: 'ยังตรวจสอบคำตอบไม่ได้',
    wait: null,
  ),
  (
    code: 'structured_output_invalid',
    seconds: null,
    quota: false,
    title: 'ยืมหน่อย สร้างคำตอบไม่ได้',
    description: 'รูปแบบคำตอบไม่สมบูรณ์',
    wait: null,
  ),
  (
    code: 'response_quality_rejected',
    seconds: null,
    quota: false,
    title: 'คำตอบของผู้ช่วย AI ยังไม่ผ่านการตรวจสอบ',
    description: 'ไม่ผ่านการตรวจสอบคุณภาพ',
    wait: null,
  ),
  (
    code: 'providers_exhausted',
    seconds: null,
    quota: false,
    title: 'ส่งคำขอไม่สำเร็จ',
    description: 'ยังไม่พร้อมตอบคำขอนี้',
    wait: null,
  ),
];

void main() {
  testWidgets(
    'quota header aligns with its clock and retry counts down one minute',
    (tester) async {
      var now = DateTime.utc(2026, 10, 7);
      var retries = 0;
      final failure = ChatbotFailure(
        messageId: 'countdown',
        message: 'รอสักครู่แล้วลองอีกครั้ง',
        isRetryable: true,
        errorCode: 'quota_temporarily_unavailable',
        retryAvailableAt: now.add(const Duration(minutes: 1)),
      );
      Widget mount() => MaterialApp(
        home: Scaffold(
          body: ChatbotFailureCard(
            failure: failure,
            onRetry: () => retries++,
            onRevise: () {},
            now: () => now,
          ),
        ),
      );
      await tester.pumpWidget(mount());
      expect(find.text('ลองอีกครั้ง (1:00)'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      final icon = tester.getRect(find.byIcon(Icons.schedule_rounded));
      final title = tester.getRect(find.text('ผู้ช่วย AI ติดโควต้าชั่วคราว'));
      expect(title.left, greaterThan(icon.right));
      expect(title.center.dy, icon.center.dy);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('ลองอีกครั้ง (0:59)'), findsOneWidget);
      await tester.pumpWidget(mount());
      expect(find.text('ลองอีกครั้ง (0:59)'), findsOneWidget);
      now = now.add(const Duration(seconds: 58));
      await tester.pump(const Duration(seconds: 58));
      expect(find.text('ลองอีกครั้ง (0:01)'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('ลองอีกครั้ง'), findsOneWidget);
      await tester.tap(find.text('ลองอีกครั้ง'));
      expect(retries, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  for (final testCase in _cases) {
    for (final transport in _Transport.values) {
      test(
        '${testCase.code} survives $transport with an accurate notice',
        () async {
          final client = _FailureClient(
            testCase.code,
            testCase.seconds,
            transport,
          );
          final source = ChatbotRemoteDataSource(client: client);
          ChatbotRemoteException? failure;
          try {
            if (transport == _Transport.httpJson) {
              await source.sendMessage(
                query: 'ช่วยเลือกอุปกรณ์',
                history: const [],
              );
            } else {
              await source
                  .sendMessageStream(
                    query: 'ช่วยเลือกอุปกรณ์',
                    history: const [],
                  )
                  .toList();
            }
          } on ChatbotRemoteException catch (error) {
            failure = error;
          }
          expect(failure, isNotNull);
          expect(failure!.errorCode, testCase.code);
          expect(failure.retryAfterSeconds, testCase.seconds);
          expect(failure.message, contains(testCase.description));
          expect(failure.message, isNot(contains('คิวหรือโควต้า')));
          if (testCase.wait != null) {
            expect(failure.message, contains(testCase.wait!));
          } else {
            expect(failure.message, isNot(contains('1 นาที')));
            expect(failure.message, isNot(contains('โควต้า')));
          }
          expect(client.requests, 1);
          source.close();
        },
      );
    }

    testWidgets('${testCase.code} reaches its own failure card', (
      tester,
    ) async {
      final client = _FailureClient(
        testCase.code,
        testCase.seconds,
        _Transport.sse,
      );
      final state = await tester.runAsync(() async {
        final bloc = ChatbotBloc(
          sendMessage: SendChatMessageUseCase(
            ChatbotRepositoryImpl(ChatbotRemoteDataSource(client: client)),
          ),
        );
        try {
          final completed = bloc.stream.firstWhere(
            (state) => state.failure != null,
          );
          bloc.add(const ChatbotMessageSubmitted('ช่วยเลือกอุปกรณ์'));
          return await completed;
        } finally {
          await bloc.close();
        }
      });
      final failure = state!.failure!;
      expect(state.isSending, false);
      expect(state.messages.last.isStreaming, false);
      expect(failure.errorCode, testCase.code);
      expect(failure.isQuota, testCase.quota);
      expect(failure.retryAvailableAt != null, testCase.seconds != null);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatbotFailureCard(
              failure: failure,
              onRetry: () {},
              onRevise: () {},
            ),
          ),
        ),
      );
      expect(find.text(testCase.title), findsOneWidget);
      expect(find.text(failure.message), findsOneWidget);
      if (testCase.code == 'structured_output_invalid') {
        final icon = tester.getRect(find.byIcon(Icons.data_object_rounded));
        final title = tester.getRect(find.text(testCase.title));
        expect(title.left, greaterThan(icon.right));
        expect(title.center.dy, icon.center.dy);
      }
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed != null, testCase.seconds == null);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'temporary quota without a deadline does not promise a one-minute reset',
    () async {
      final source = ChatbotRemoteDataSource(
        client: _FailureClient(
          'quota_temporarily_unavailable',
          null,
          _Transport.sse,
        ),
      );
      addTearDown(source.close);
      await expectLater(
        source.sendMessageStream(query: 'ช่วยเลือกอุปกรณ์', history: const []),
        emitsError(
          isA<ChatbotRemoteException>().having(
            (error) => error.message,
            'unknown duration',
            allOf(
              contains('ยังไม่สามารถระบุเวลารอ'),
              isNot(contains('1 นาที')),
            ),
          ),
        ),
      );
    },
  );

  test('queue and reviewer errors stay distinct from a quota error', () {
    for (final code in [
      'providers_busy',
      'review_unavailable',
      'structured_output_invalid',
      'response_quality_rejected',
    ]) {
      final failure = ChatbotFailure(
        messageId: 'failed-request',
        message: 'คำขอไม่สำเร็จ',
        isRetryable: true,
        errorCode: code,
        statusCode: 503,
      );
      expect(failure.isQuota, false);
    }
  });
}

enum _Transport { sse, httpStream, httpJson }

class _FailureClient implements ApiClient {
  _FailureClient(this.code, this.seconds, this.transport);

  final String code;
  final int? seconds;
  final _Transport transport;
  int requests = 0;

  @override
  Future<Stream<String>> postStream(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    requests++;
    if (transport == _Transport.httpStream) {
      throw ApiClientException(
        ApiClientErrorType.invalidResponse,
        statusCode: 503,
        errorCode: code,
        retryAfterSeconds: seconds,
      );
    }
    return Stream.fromIterable([
      'event: error',
      'data: ${jsonEncode({'error_code': code, if (seconds != null) 'retry_after_seconds': seconds})}',
      '',
    ]);
  }

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    requests++;
    return ApiResponse(
      statusCode: 503,
      data: {'status': 'error', 'error_code': code},
      retryAfterSeconds: seconds,
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

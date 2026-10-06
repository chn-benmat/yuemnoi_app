import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/data/repositories/chatbot_repository_impl.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_event.dart';

void main() {
  test(
    'quota error releases send state and identifies a failed request',
    () async {
      final client = _QuotaClient(41490);
      final bloc = ChatbotBloc(
        sendMessage: SendChatMessageUseCase(
          ChatbotRepositoryImpl(ChatbotRemoteDataSource(client: client)),
        ),
      );
      addTearDown(bloc.close);
      final completed = bloc.stream.firstWhere(
        (state) => state.errorMessage != null,
      );
      bloc.add(const ChatbotMessageSubmitted('สวัสดี'));
      final state = await completed;
      expect(state.isSending, false);
      expect(state.messages.last.isStreaming, false);
      expect(state.messages.last.statusMessage, 'คำขอไม่สำเร็จ');
      expect(state.messages.last.content, contains('11 ชั่วโมง 32 นาที'));
      expect(client.requests, 1);
    },
  );

  for (final testCase in [(59, '1 นาที'), (41490, '11 ชั่วโมง 32 นาที')]) {
    test('SSE quota failure explains the actual wait ${testCase.$1}', () async {
      final client = _QuotaClient(testCase.$1);
      final source = ChatbotRemoteDataSource(client: client);
      await expectLater(
        source.sendMessageStream(
          query: 'หวัดดี วันนี้เป็นไงบ้าง',
          history: const [],
        ),
        emitsError(
          isA<ChatbotRemoteException>().having(
            (error) => error.message,
            'wait notice',
            contains(testCase.$2),
          ),
        ),
      );
      expect(client.requests, 1);
    });
  }

  test('unknown wait does not invent a retry time', () async {
    final source = ChatbotRemoteDataSource(client: _QuotaClient(null));
    await expectLater(
      source.sendMessageStream(query: 'สวัสดี', history: const []),
      emitsError(
        isA<ChatbotRemoteException>().having(
          (error) => error.message,
          'unknown duration',
          contains('ยังไม่สามารถระบุเวลารอ'),
        ),
      ),
    );
  });
}

class _QuotaClient implements ApiClient {
  _QuotaClient(this.seconds);
  final int? seconds;
  int requests = 0;

  @override
  Future<Stream<String>> postStream(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    requests++;
    return Stream.fromIterable([
      'event: error',
      'data: {"error_code":"providers_rate_limited"${seconds == null ? '' : ',"retry_after_seconds":$seconds'}}',
      '',
    ]);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

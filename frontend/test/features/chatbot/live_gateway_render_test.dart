import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/data/repositories/chatbot_repository_impl.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';

const enabled = bool.fromEnvironment('AI_LIVE_GATEWAY_SMOKE');

// อนุญาต HTTP จริงเฉพาะ smoke ที่ผู้รันเปิดใช้งาน ไม่ใช้ HTTP จำลองของ flutter_test
class _LiveNetworkBinding extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  if (enabled) {
    _LiveNetworkBinding();
  }
  testWidgets(
    'real Python and Go response reaches the Flutter render boundary',
    (tester) async {
      const gateway = String.fromEnvironment('AI_SMOKE_GATEWAY_URL');
      const query = String.fromEnvironment('AI_SMOKE_QUERY');
      const reportPath = String.fromEnvironment('AI_SMOKE_REPORT_PATH');
      expect(gateway, isNotEmpty);
      expect(query, isNotEmpty);
      expect(reportPath, isNotEmpty);
      final measurement = <Map<String, Object?>>[];
      final client = DioApiClient(baseUrl: gateway, appSecret: '');
      final bloc = ChatbotBloc(
        sendMessage: SendChatMessageUseCase(
          ChatbotRepositoryImpl(ChatbotRemoteDataSource(client: client)),
        ),
        onTimingMeasured: (sample) => measurement.add(sample.toJson()),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        query,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      final wait = Stopwatch()..start();
      while (measurement.isEmpty &&
          wait.elapsed < const Duration(seconds: 30)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final last = bloc.state.messages.last;
      final report = {
        'measurement_environment': 'flutter_test_live_binding',
        'physical_device': false,
        'profile_mode': false,
        'production_bootstrap': false,
        'production_gateway_middleware': false,
        'samples': measurement,
        'completed':
            measurement.isNotEmpty &&
            measurement.single['outcome'] == 'success',
        'has_error': bloc.state.errorMessage != null,
        'request_scope': last.understanding?.requestScope,
        'next_action': last.understanding?.nextAction,
        'answer': last.content,
        'item_ids': last.recommendedItems.map((i) => i.id).toList(),
        'items': last.recommendedItems
            .map(
              (i) => {
                'id': i.id,
                'name': i.name,
                'price': i.price,
                'unit': i.unit,
                'status': i.status,
              },
            )
            .toList(),
        'question_ids': last.questions.map((q) => q.id).toList(),
        'reference_ids': last.references.map((r) => r.id).toList(),
        'certificate_95_percent': false,
        'ui_latency_certified': false,
      };
      await File(
        reportPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      await tester.pumpWidget(const SizedBox.shrink());
      await bloc.close();
      expect(
        report['completed'],
        isTrue,
        reason: 'Live smoke must expose failures',
      );
    },
    skip: !enabled,
  );
}

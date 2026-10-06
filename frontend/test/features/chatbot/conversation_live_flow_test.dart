import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/data/repositories/chatbot_repository_impl.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';

const _enabled = bool.fromEnvironment('AI_CONVERSATION_LIVE');

// ใช้ HTTP จริงเฉพาะเมื่อเปิดการทดสอบนี้อย่างชัดเจน
class _LiveBinding extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  if (_enabled) _LiveBinding();
  testWidgets(
    'real generated questionnaire and conversation reaches Flutter',
    (tester) async {
      const configPath = String.fromEnvironment('AI_CONVERSATION_CONFIG');
      final config =
          jsonDecode(await File(configPath).readAsString())
              as Map<String, dynamic>;
      final requests = <Map<String, dynamic>>[];
      final turns = <Map<String, dynamic>>[];
      final checks = <String, bool>{};
      final dio = Dio(BaseOptions(baseUrl: config['gateway_url'] as String));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // บันทึกเฉพาะข้อมูลแชทสังเคราะห์ ไม่บันทึก header หรือ credentials
            if (options.data is Map<String, dynamic>) {
              requests.add(
                jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>,
              );
            }
            handler.next(options);
          },
        ),
      );
      final client = DioApiClient(dio: dio, appSecret: '');
      final bloc = ChatbotBloc(
        sendMessage: SendChatMessageUseCase(
          ChatbotRepositoryImpl(ChatbotRemoteDataSource(client: client)),
        ),
      );
      final report = <String, dynamic>{
        'flow': config['flow'],
        'surface':
            'Flutter live widget binding -> real Go handler -> Python -> providers',
        'physical_device': false,
        'production_bootstrap': false,
        'production_gateway_middleware': false,
        'certificate_95_percent': false,
        'outcome': 'running',
        'requests': requests,
        'turns': turns,
        'checks': checks,
      };
      Future<void> save() async {
        await File(
          config['result_path'] as String,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      }

      Future<void> waitForReply(int requestCount) async {
        final clock = Stopwatch()..start();
        while (clock.elapsedMilliseconds < (config['turn_timeout_ms'] as int)) {
          await tester.pump(const Duration(milliseconds: 50));
          if (requests.length > requestCount &&
              bloc.state.messages.length >= 2 &&
              !bloc.state.isSending) {
            await tester.pump(const Duration(milliseconds: 100));
            final last = bloc.state.messages.last;
            turns.add({
              'answer': last.content,
              'error': bloc.state.errorMessage,
              'next_action': last.understanding?.nextAction,
              'request_scope': last.understanding?.requestScope,
              'questions': last.questions
                  .map(
                    (q) => {
                      'id': q.id,
                      'title': q.title,
                      'choices': q.choices
                          .map(
                            (c) => {
                              'id': c.id,
                              'label': c.label,
                              'action_value': c.actionValue,
                            },
                          )
                          .toList(),
                    },
                  )
                  .toList(),
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
            });
            await save();
            if (bloc.state.errorMessage != null) {
              throw StateError('service_error');
            }
            return;
          }
        }
        throw StateError('ui_wait_timeout');
      }

      Future<void> send(String text) async {
        final count = requests.length;
        await tester.enterText(
          find.byKey(const Key('chatbot-message-field')),
          text,
        );
        await tester.tap(find.byKey(const Key('chatbot-send-button')));
        await waitForReply(count);
      }

      Future<void> pace() async {
        await tester.runAsync(
          () => Future<void>.delayed(
            Duration(milliseconds: config['between_turn_ms'] as int),
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await save();
      try {
        final flow = config['flow'] as String;
        if ([
          'choices',
          'custom',
          'skip',
          'questionnaire_interrupt',
        ].contains(flow)) {
          await send(config['broad_query'] as String);
          final questions = bloc.state.messages.last.questions;
          checks['real_generated_questions_rendered'] =
              questions.isNotEmpty &&
              find
                  .byKey(const Key('chatbot-questionnaire-card'))
                  .evaluate()
                  .isNotEmpty;
          if (!checks['real_generated_questions_rendered']!) {
            throw StateError('expected_questionnaire_missing');
          }
          await pace();
          if (flow == 'choices') {
            final before = requests.length;
            for (final question in questions) {
              final choice = question.choices.first;
              final button = find.byKey(
                Key('chatbot-questionnaire-option-${choice.label}'),
              );
              await tester.ensureVisible(button);
              await tester.tap(button);
              await tester.pump(const Duration(milliseconds: 200));
            }
            await waitForReply(before);
            final actual =
                requests.last['questionnaire_answers'] as List<dynamic>;
            checks['generated_choice_ids_sent'] =
                actual.length == questions.length &&
                List.generate(
                  questions.length,
                  (i) =>
                      actual[i]['question_id'] == questions[i].id &&
                      actual[i]['option_id'] == questions[i].choices.first.id,
                ).every((v) => v);
          } else if (flow == 'custom') {
            final text = questions.first.choices.first.label;
            await send(text);
            final actual =
                requests.last['questionnaire_answers'] as List<dynamic>;
            checks['free_text_sent_for_generated_question'] =
                requests.last['query'] == text &&
                requests.last['active_question_id'] == questions.first.id &&
                actual.isEmpty;
          } else if (flow == 'questionnaire_interrupt') {
            await pace();
            await send(config['second_query'] as String);
            checks['new_topic_sent_immediately'] =
                requests.last['query'] == config['second_query'] &&
                requests.last['active_question_id'] == questions.first.id &&
                (requests.last['questionnaire_answers'] as List).isEmpty;
            await pace();
            await send(config['pronoun_query'] as String);
          } else {
            final before = requests.length;
            await tester.tap(
              find.byKey(const Key('chatbot-questionnaire-skip')),
            );
            await waitForReply(before);
            checks['skip_flag_sent'] =
                requests.last['questionnaire_skipped'] == true;
            checks['skip_not_reasked'] =
                bloc.state.messages.last.questions.isEmpty;
          }
          checks['context_and_history_sent'] =
              requests.last['context'] != null &&
              (requests.last['history'] as List<dynamic>).isNotEmpty;
        } else if (flow == 'edit') {
          await send(config['first_query'] as String);
          await pace();
          final original = find.byKey(const ValueKey('chat-message-0'));
          await tester.ensureVisible(original);
          await tester.longPress(original);
          await tester.pump(const Duration(milliseconds: 250));
          await tester.tap(
            find.byKey(const Key('chatbot-edit-message-action')),
          );
          await tester.pump(const Duration(milliseconds: 250));
          checks['editing_banner_visible'] = find
              .byKey(const Key('chatbot-editing-banner'))
              .evaluate()
              .isNotEmpty;
          await send(config['second_query'] as String);
          checks['edited_query_sent'] =
              requests.last['query'] == config['second_query'];
          checks['discarded_history_not_sent'] =
              (requests.last['history'] as List<dynamic>).isEmpty;
        } else if (flow == 'product_switch') {
          await send(config['first_query'] as String);
          await pace();
          await send(config['small_talk_query'] as String);
          await pace();
          await send(config['second_query'] as String);
          await pace();
          await send(config['pronoun_query'] as String);
          checks['single_session_preserved'] =
              requests.map((r) => r['session_id']).toSet().length == 1;
          checks['generated_history_sent'] =
              (requests.last['history'] as List<dynamic>).length >= 6;
        } else {
          throw StateError('unknown_flow');
        }
        checks['reply_rendered'] =
            bloc.state.messages.last.content.trim().isNotEmpty &&
            find.byType(ChatBotScreen).evaluate().isNotEmpty;
        report['outcome'] = checks.values.every((v) => v)
            ? 'completed'
            : 'contract_failed';
      } catch (error) {
        report['outcome'] = 'incomplete';
        report['diagnostic'] = error is StateError
            ? error.message
            : error.runtimeType.toString();
      } finally {
        await save();
        await tester.pumpWidget(const SizedBox.shrink());
        await bloc.close();
        client.close();
      }
      expect(
        report['outcome'],
        'completed',
        reason: 'Live failures must remain visible in evidence',
      );
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

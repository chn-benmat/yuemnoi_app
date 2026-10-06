import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;
  late ChatbotRemoteDataSource dataSource;

  setUp(() {
    client = MockApiClient();
    dataSource = ChatbotRemoteDataSource(client: client);
    when(() => client.close()).thenReturn(null);
  });

  tearDown(() {
    dataSource.close();
  });

  test('sends query and history then maps the AI recommendation', () async {
    when(
      () => client.post(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {
          'status': 'success',
          'answer': 'แนะนำ Canon EOS R5 ค่ะ',
          'recommended_items': [
            {
              'id': 7,
              'item_name': 'Canon EOS R5',
              'price': 500,
              'unit': 'สัปดาห์',
              'image_url': 'https://example.com/camera.jpg',
              'status': 'available',
              'category': 'camera',
              'description': 'กล้องระดับมืออาชีพ',
            },
          ],
        },
      ),
    );

    final result = await dataSource.sendMessage(
      query: 'แนะนำกล้องให้หน่อย',
      history: const [
        ChatMessage(
          role: ChatMessageRole.assistant,
          content: 'มีอะไรให้ช่วยคะ',
        ),
      ],
    );

    final captured =
        verify(
              () => client.post(
                '/api/chat-ai',
                data: captureAny(named: 'data'),
                headers: any(named: 'headers'),
              ),
            ).captured.single
            as Map<String, dynamic>;

    expect(captured['query'], 'แนะนำกล้องให้หน่อย');
    expect(captured['history'], [
      {'role': 'assistant', 'content': 'มีอะไรให้ช่วยคะ'},
    ]);
    expect(result.answer, 'แนะนำ Canon EOS R5 ค่ะ');
    expect(result.recommendedItems.single.name, 'Canon EOS R5');
    expect(result.recommendedItems.single.price, 500);
  });

  test('translates a timeout into a user-facing error', () async {
    when(
      () => client.post(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenThrow(const ApiClientException(ApiClientErrorType.timeout));

    expect(
      () => dataSource.sendMessage(query: 'สวัสดี', history: const []),
      throwsA(
        isA<ChatbotRemoteException>().having(
          (error) => error.message,
          'message',
          'ผู้ช่วย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง',
        ),
      ),
    );
  });

  test('streams SSE events and maps metadata, delta, and done', () async {
    when(
      () => client.postStream(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => Stream.fromIterable([
        'event: status\n',
        'data: {"step": "searching", "message": "กำลังค้นหา..."}\n',
        '\n',
        'event: metadata\n',
        'data: {"mode": "recommendation", "recommended_items": [{"id": 7, "item_name": "Canon EOS R5", "price": 500, "unit": "วัน", "image_url": "", "status": "available", "category": "camera", "description": ""}], "questions": []}\n',
        '\n',
        'event: delta\n',
        'data: {"text": "แนะนำกล้อง "}\n',
        '\n',
        'event: delta\n',
        'data: {"text": "Canon ค่ะ"}\n',
        '\n',
        'event: done\n',
        'data: {"suggested_replies": ["ขอบคุณค่ะ"]}\n',
      ]),
    );

    final events = await dataSource.sendMessageStream(
      query: 'แนะนำกล้อง',
      history: const [],
    ).toList();

    expect(events.length, 5);
    expect(events[0], isA<ChatStatusEvent>());
    expect((events[0] as ChatStatusEvent).step, 'searching');
    expect(events[1], isA<ChatMetadataEvent>());
    expect((events[1] as ChatMetadataEvent).recommendedItems.single.name, 'Canon EOS R5');
    expect(events[2], isA<ChatDeltaEvent>());
    expect((events[2] as ChatDeltaEvent).text, 'แนะนำกล้อง ');
    expect(events[3], isA<ChatDeltaEvent>());
    expect((events[3] as ChatDeltaEvent).text, 'Canon ค่ะ');
    expect(events[4], isA<ChatDoneEvent>());
    expect((events[4] as ChatDoneEvent).suggestedReplies, ['ขอบคุณค่ะ']);
  });

  test('streams SSE events and maps search_sources, search_query, and activities', () async {
    when(
      () => client.postStream(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => Stream.fromIterable([
        'event: status\n',
        'data: {"step": "searching_web", "message": "กำลังค้นหา..."}\n',
        '\n',
        'event: done\n',
        'data: {"answer": "สรุปเปรียบเทียบ", "search_query": "A7 IV vs FX3", "activities": ["วิเคราะห์คำถาม", "ค้นหา Google"], "search_sources": [{"title": "Review", "url": "https://example.com", "domain": "example.com", "snippet": "Sample"}]}\n',
      ]),
    );

    final events = await dataSource.sendMessageStream(
      query: 'เปรียบเทียบ',
      history: const [],
    ).toList();

    expect(events.length, 2);
    expect(events[1], isA<ChatDoneEvent>());
    final done = events[1] as ChatDoneEvent;
    expect(done.answer, 'สรุปเปรียบเทียบ');
    expect(done.searchQuery, 'A7 IV vs FX3');
    expect(done.activities, ['วิเคราะห์คำถาม', 'ค้นหา Google']);
    expect(done.searchSources.length, 1);
    expect(done.searchSources.first.title, 'Review');
    expect(done.searchSources.first.domain, 'example.com');
  });

  test('SSE timeout error propagates and never becomes a done event', () async {
    when(() => client.postStream(any(), data: any(named: 'data'),
      headers: any(named: 'headers'))).thenAnswer((_) async => Stream.fromIterable([
        'event: error',
        'data: {"status":"error","error_code":"timeout","answer":""}',
      ]));
    await expectLater(dataSource.sendMessageStream(query: 'hello', history: []).toList(),
      throwsA(isA<ChatbotRemoteException>()));
  });

  test('non-stream error envelope is not a successful answer', () async {
    when(() => client.post(any(), data: any(named: 'data'),
      headers: any(named: 'headers'))).thenAnswer((_) async => const ApiResponse(
        statusCode: 200, data: {'status':'error','error_code':'ungrounded_response','answer':''}));
    await expectLater(dataSource.sendMessage(query: 'hello', history: []),
      throwsA(isA<ChatbotRemoteException>()));
  });

  test('incomplete SSE does not silently finish', () async {
    when(() => client.postStream(any(), data: any(named: 'data'),
      headers: any(named: 'headers'))).thenAnswer((_) async => Stream.fromIterable([
        'event: status', 'data: {"step":"processing"}',
      ]));
    await expectLater(dataSource.sendMessageStream(query: 'hello', history: []).toList(),
      throwsA(isA<ChatbotRemoteException>()));
  });
}

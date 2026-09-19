import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/presentation/widgets/interactive_questionnaire_card.dart';

void main() {
  const singleStepQuestion = ClarificationQuestion(
    id: 'activity',
    title: 'เช่าคอมไปใช้งานแบบไหน?',
    options: [
      'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)',
      'จัดอีเวนต์/บูธ (หลายเครื่อง)',
      'เล่นเกม/สเปกแรง',
      'ตัดต่อ/กราฟิก สเปกสูง',
    ],
    step: 1,
    totalSteps: 1,
  );

  const step1Question = ClarificationQuestion(
    id: 'activity',
    title: 'เช่าคอมไปใช้งานแบบไหน?',
    options: [
      'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)',
      'จัดอีเวนต์/บูธ (หลายเครื่อง)',
      'เล่นเกม/สเปกแรง',
      'ตัดต่อ/กราฟิก สเปกสูง',
    ],
    step: 1,
    totalSteps: 2,
  );

  const step2Question = ClarificationQuestion(
    id: 'specs',
    title: 'ระยะเวลาเช่าหรือรูปแบบเครื่องที่ต้องการ?',
    options: [
      'เน้นพกพา (โน้ตบุ๊ก)',
      'ตั้งโต๊ะ (PC สเปกสูง)',
      'เช่าสั้น 1-3 วัน',
      'เช่าระยะยาว (รายเดือน)',
    ],
    step: 2,
    totalSteps: 2,
  );

  const answeredQuestion = ClarificationQuestion(
    id: 'activity',
    title: 'เช่าคอมไปใช้งานแบบไหน?',
    options: [
      'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)',
      'จัดอีเวนต์/บูธ (หลายเครื่อง)',
    ],
    step: 1,
    totalSteps: 2,
    selectedOption: 'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)',
  );

  testWidgets('renders single-step questionnaire card and completes on option selection', (
    tester,
  ) async {
    String? completedSummary;
    var dismissed = false;
    var customInputTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            questions: const [singleStepQuestion],
            onCompleted: (summary) => completedSummary = summary,
            onDismiss: () => dismissed = true,
            onCustomInput: () => customInputTriggered = true,
          ),
        ),
      ),
    );

    // Header & badge check
    expect(find.text('เช่าคอมไปใช้งานแบบไหน?'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);

    // Numbered options check
    expect(find.text('ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'), findsOneWidget);
    expect(find.text('จัดอีเวนต์/บูธ (หลายเครื่อง)'), findsOneWidget);
    expect(find.text('เล่นเกม/สเปกแรง'), findsOneWidget);
    expect(find.text('ตัดต่อ/กราฟิก สเปกสูง'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    // Footer actions
    expect(find.text('ตอบเอง'), findsNothing);
    expect(find.text('Skip'), findsOneWidget);

    // Tap option 1
    await tester.tap(find.text('ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'));
    await tester.pump(const Duration(milliseconds: 250));

    // Completed callback receives chosen option text
    expect(completedSummary, 'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)');
    expect(dismissed, isFalse);
    expect(customInputTriggered, isFalse);
  });

  testWidgets('does not invent a missing second question', (tester) async {
    String? summary;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      InteractiveQuestionnaireCard(
        questions: const [step1Question],
        onCompleted: (value) => summary = value,
        onDismiss: () {}, onCustomInput: () {},
      ),
    )));
    expect(find.text('1 of 1'), findsOneWidget);
    await tester.tap(find.text('ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(summary, 'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)');
    expect(find.text('ท่องเที่ยว/ถ่ายรูปคาเฟ่'), findsNothing);
  });

  testWidgets('stepper advances locally between questions and supports back navigation', (
    tester,
  ) async {
    String? completedSummary;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            questions: const [step1Question, step2Question],
            onCompleted: (summary) => completedSummary = summary,
            onDismiss: () {},
            onCustomInput: () {},
          ),
        ),
      ),
    );

    // Initial state: Question 1 is visible
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('เช่าคอมไปใช้งานแบบไหน?'), findsOneWidget);
    expect(find.text('ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'), findsOneWidget);

    // Tap option 1 on Question 1
    await tester.tap(find.text('ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'));
    await tester.pump(const Duration(milliseconds: 250));

    // Now question 2 should be displayed immediately locally
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('ระยะเวลาเช่าหรือรูปแบบเครื่องที่ต้องการ?'), findsOneWidget);
    expect(find.text('เน้นพกพา (โน้ตบุ๊ก)'), findsOneWidget);
    expect(completedSummary, isNull);

    // Tap back button
    await tester.tap(find.byKey(const Key('chatbot-questionnaire-prev')));
    await tester.pumpAndSettle();

    // Returned to Question 1
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('เช่าคอมไปใช้งานแบบไหน?'), findsOneWidget);

    // Tap forward button
    await tester.tap(find.byKey(const Key('chatbot-questionnaire-next')));
    await tester.pumpAndSettle();

    // On Question 2 again
    expect(find.text('2 of 2'), findsOneWidget);

    // Tap option on Question 2
    await tester.tap(find.text('เน้นพกพา (โน้ตบุ๊ก)'));
    await tester.pump(const Duration(milliseconds: 250));

    // Completed with combined answers!
    expect(completedSummary, 'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC), เน้นพกพา (โน้ตบุ๊ก)');
  });

  testWidgets('supports skip and dismiss actions and does not render custom input button', (
    tester,
  ) async {
    var dismissed = false;
    String? completedSummary;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            questions: const [step1Question],
            onCompleted: (summary) => completedSummary = summary,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    // Custom input button is removed
    expect(find.byKey(const Key('chatbot-questionnaire-custom')), findsNothing);
    expect(find.text('ตอบเอง'), findsNothing);

    // Tap close button
    await tester.tap(find.byKey(const Key('chatbot-questionnaire-close')));
    expect(dismissed, isTrue);

    // Tap skip button
    await tester.tap(find.byKey(const Key('chatbot-questionnaire-skip')));
    expect(completedSummary, 'ข้ามแบบสอบถาม');
  });

  testWidgets('renders QuestionnaireRecapCard when question is already answered', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: const Scaffold(
          body: QuestionnaireRecapCard(question: answeredQuestion),
        ),
      ),
    );

    expect(find.text('เช่าคอมไปใช้งานแบบไหน?'), findsOneWidget);
    expect(find.text('1 of 2'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'), findsOneWidget);
    expect(find.byKey(const Key('chatbot-questionnaire-recap-activity')), findsOneWidget);
  });

  testWidgets('stepper handles 3 questions smoothly (< 1 of 3 > to < 3 of 3 >)', (
    tester,
  ) async {
    const q1 = ClarificationQuestion(
      id: 'q1',
      title: 'สนใจอุปกรณ์ประเภทใด?',
      options: ['กล้อง', 'เต็นท์'],
      step: 1,
      totalSteps: 3,
    );
    const q2 = ClarificationQuestion(
      id: 'q2',
      title: 'สถานที่ท่องเที่ยว?',
      options: ['ภูเขา', 'ทะเล'],
      step: 2,
      totalSteps: 3,
    );
    const q3 = ClarificationQuestion(
      id: 'q3',
      title: 'ระยะเวลาเช่า?',
      options: ['1-3 วัน', '1 สัปดาห์'],
      step: 3,
      totalSteps: 3,
    );

    String? completedSummary;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            questions: const [q1, q2, q3],
            onCompleted: (summary) => completedSummary = summary,
            onDismiss: () {},
            onCustomInput: () {},
          ),
        ),
      ),
    );

    // Step 1 of 3
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('สนใจอุปกรณ์ประเภทใด?'), findsOneWidget);

    // Tap 'เต็นท์'
    await tester.tap(find.text('เต็นท์'));
    await tester.pump(const Duration(milliseconds: 250));

    // Step 2 of 3
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('สถานที่ท่องเที่ยว?'), findsOneWidget);

    // Tap 'ภูเขา'
    await tester.tap(find.text('ภูเขา'));
    await tester.pump(const Duration(milliseconds: 250));

    // Step 3 of 3
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('ระยะเวลาเช่า?'), findsOneWidget);

    // Tap '1-3 วัน' on final question
    await tester.tap(find.text('1-3 วัน'));
    await tester.pump(const Duration(milliseconds: 250));

    // Complete with all 3 answers combined!
    expect(completedSummary, 'เต็นท์, ภูเขา, 1-3 วัน');
  });

  testWidgets('dynamically branches Question 2 title and options based on Question 1 selection', (
    tester,
  ) async {
    const q1 = ClarificationQuestion(
      id: 'step_cat',
      title: 'สนใจเช่าอุปกรณ์ประเภทไหนคะ?',
      options: ['กล้องและอุปกรณ์ถ่ายภาพ', 'แคมป์ปิ้งและกิจกรรมกลางแจ้ง'],
      step: 1,
      totalSteps: 2,
    );
    const q2 = ClarificationQuestion(
      id: 'step_act',
      title: 'ลักษณะการใช้งานหลัก?',
      options: ['ทั่วไป'],
      step: 2,
      totalSteps: 2,
      branchTitles: {
        'กล้องและอุปกรณ์ถ่ายภาพ': 'ต้องการนำกล้องไปใช้งานลักษณะใดคะ?',
        'แคมป์ปิ้งและกิจกรรมกลางแจ้ง': 'ลักษณะทริปหรือกิจกรรมแคมป์ปิ้งเป็นแบบไหนคะ?',
      },
      branchOptions: {
        'กล้องและอุปกรณ์ถ่ายภาพ': ['ถ่ายภาพท่องเที่ยว/คาเฟ่', 'ถ่ายคอนเสิร์ต/แสงน้อย'],
        'แคมป์ปิ้งและกิจกรรมกลางแจ้ง': ['กางเต็นท์พักผ่อน', 'เดินป่า/ขึ้นดอย'],
      },
    );

    String? completedSummary;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            questions: const [q1, q2],
            onCompleted: (summary) => completedSummary = summary,
            onDismiss: () {},
            onCustomInput: () {},
          ),
        ),
      ),
    );

    // Step 1: Select 'กล้องและอุปกรณ์ถ่ายภาพ'
    expect(find.text('สนใจเช่าอุปกรณ์ประเภทไหนคะ?'), findsOneWidget);
    await tester.tap(find.text('กล้องและอุปกรณ์ถ่ายภาพ'));
    await tester.pump(const Duration(milliseconds: 250));

    // Step 2: Title and options should dynamically match 'กล้อง' branch!
    expect(find.text('ต้องการนำกล้องไปใช้งานลักษณะใดคะ?'), findsOneWidget);
    expect(find.text('ถ่ายภาพท่องเที่ยว/คาเฟ่'), findsOneWidget);
    expect(find.text('ถ่ายคอนเสิร์ต/แสงน้อย'), findsOneWidget);

    // Go back to Step 1 and change to 'แคมป์ปิ้งและกิจกรรมกลางแจ้ง'
    await tester.tap(find.byKey(const Key('chatbot-questionnaire-prev')));
    await tester.pumpAndSettle();

    expect(find.text('สนใจเช่าอุปกรณ์ประเภทไหนคะ?'), findsOneWidget);
    await tester.tap(find.text('แคมป์ปิ้งและกิจกรรมกลางแจ้ง'));
    await tester.pump(const Duration(milliseconds: 250));

    // Step 2: Title and options should now dynamically match 'แคมป์ปิ้ง' branch!
    expect(find.text('ลักษณะทริปหรือกิจกรรมแคมป์ปิ้งเป็นแบบไหนคะ?'), findsOneWidget);
    expect(find.text('กางเต็นท์พักผ่อน'), findsOneWidget);
    expect(find.text('เดินป่า/ขึ้นดอย'), findsOneWidget);

    // Select 'กางเต็นท์พักผ่อน' and complete
    await tester.tap(find.text('กางเต็นท์พักผ่อน'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(completedSummary, 'แคมป์ปิ้งและกิจกรรมกลางแจ้ง, กางเต็นท์พักผ่อน');
  });

  testWidgets('allows submitting custom answer via submitCustomAnswer', (
    tester,
  ) async {
    String? completedSummary;
    final cardKey = GlobalKey<InteractiveQuestionnaireCardState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            key: cardKey,
            questions: const [singleStepQuestion],
            onCompleted: (summary) => completedSummary = summary,
            onDismiss: () {},
            onCustomInput: () {},
          ),
        ),
      ),
    );

    // Call submitCustomAnswer
    cardKey.currentState!.submitCustomAnswer('สตรีมมิงเกม 4K');
    await tester.pump(const Duration(milliseconds: 250));

    expect(completedSummary, 'สตรีมมิงเกม 4K');
  });
}



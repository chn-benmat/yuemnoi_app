import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/features/profile/presentation/pages/profile/profile.dart';
import 'package:frontend/features/rental_return/domain/entities/rental_return_session.dart';
import 'package:frontend/features/rental_return/domain/repositories/rental_return_repository.dart';
import 'package:frontend/features/rental_return/presentation/pages/rental_return_page.dart';
import 'package:frontend/features/rental_return/presentation/widgets/lender_inspection_view.dart';
import 'package:frontend/features/rental_return/presentation/widgets/role_switcher_bar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRentalReturnRepository extends Mock
    implements RentalReturnRepository {}

class _MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('th', null);
    await (FontLoader('Prompt')
          ..addFont(rootBundle.load('assets/fonts/Prompt-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Prompt-Bold.ttf')))
        .load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Rental Return Role Separation & Safety Section Test', () {
    late _MockRentalReturnRepository mockRepository;
    late _MockAuthBloc mockAuthBloc;

    setUp(() {
      mockRepository = _MockRentalReturnRepository();
      when(
        () => mockRepository.getReturnSession(any()),
      ).thenAnswer((_) async => RentalReturnSession.createMockSession());

      mockAuthBloc = _MockAuthBloc();
      when(() => mockAuthBloc.state).thenReturn(const AuthInitial());
      when(() => mockAuthBloc.stream).thenAnswer((_) => const Stream.empty());
    });

    testWidgets(
      'RentalReturnPage renders only Renter UI and DOES NOT render RoleSwitcherBar or Test actions',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: RentalReturnPage(isLender: false, repository: mockRepository),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // 1. Role switcher tab bar MUST NOT be present
        expect(find.byType(RoleSwitcherBar), findsNothing);
        expect(find.text('ผู้เช่า (Customer)'), findsNothing);
        expect(find.text('ร้านค้า (Lender)'), findsNothing);

        expect(find.text('คืนสินค้า'), findsOneWidget);

        // 3. ผู้เช่ารอให้ร้านค้าตรวจรับ
        expect(find.text('ส่งภาพยืนยันให้ร้านค้า'), findsNothing);
        expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('นำสินค้าไปส่งที่จุดคืนตามนัด'), findsOneWidget);
        expect(find.byType(LenderInspectionView), findsNothing);

        // 4. Test popup actions should not exist
        expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      },
    );

    testWidgets(
      'RentalReturnPage renders only Lender UI when isLender is true and DOES NOT render RoleSwitcherBar',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: RentalReturnPage(isLender: true, repository: mockRepository),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // 1. Role switcher tab bar MUST NOT be present
        expect(find.byType(RoleSwitcherBar), findsNothing);

        expect(find.text('คืนสินค้า'), findsOneWidget);
        expect(find.text('ส่งคืนสินค้า'), findsNothing);

        // 3. Should display LenderInspectionView for Lender
        expect(find.byType(LenderInspectionView), findsOneWidget);
        expect(find.text('ส่งภาพยืนยันให้ร้านค้า'), findsNothing);
        expect(find.text('ยืนยันการตรวจสภาพด้านบนก่อน'), findsNothing);
      },
    );

    testWidgets('renter sees completion after the lender confirms receipt', (
      tester,
    ) async {
      var session = RentalReturnSession.createMockSession();
      when(
        () => mockRepository.getReturnSession(any()),
      ).thenAnswer((_) async => session);
      await tester.pumpWidget(
        MaterialApp(
          home: RentalReturnPage(isLender: false, repository: mockRepository),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('นำสินค้าไปส่งที่จุดคืนตามนัด'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      session = session.copyWith(step: RentalReturnStep.completed);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('คืนอุปกรณ์สำเร็จ!'), findsOneWidget);
    });

    testWidgets('lender completes the return directly after checking receipt', (
      tester,
    ) async {
      final rental = RentalReturnSession.createMockSession();
      when(
        () => mockRepository.getReturnSession(any()),
      ).thenAnswer((_) async => rental);
      when(
        () => mockRepository.confirmMerchantReceipt(rentalId: rental.rentalId),
      ).thenAnswer((_) async {});
      await tester.pumpWidget(
        MaterialApp(
          home: RentalReturnPage(isLender: true, repository: mockRepository),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final inspectionButton = find.widgetWithText(
        ElevatedButton,
        'ยืนยันรับคืนสินค้า',
      );
      expect(tester.widget<ElevatedButton>(inspectionButton).onPressed, isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(inspectionButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('คืนอุปกรณ์สำเร็จ!'), findsOneWidget);
      expect(find.text('รหัสยืนยันการคืน'), findsNothing);
    });

    testWidgets(
      'ProfileScreen safety section does NOT contain test return item',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 3200);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: mockAuthBloc,
            child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
          ),
        );
        await tester.pumpAndSettle();

        // Should NOT contain the old test item
        expect(find.text('การคืนอุปกรณ์ (ระบบป้องกันการโกง)'), findsNothing);

        // Still contains the real security items
        expect(find.text('หมวดหมู่ความปลอดภัย'), findsOneWidget);
        expect(find.text('การยืนยันตัวตน'), findsOneWidget);
      },
    );
  });
}

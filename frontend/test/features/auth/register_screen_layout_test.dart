import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/auth/domain/repositories/auth_repository.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/pages/register.dart';
import 'package:mocktail/mocktail.dart';

class _AuthRepository extends Mock implements AuthRepository {}

void main() {
  setUpAll(() async {
    final font = FontLoader('Prompt');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = await File('assets/fonts/Prompt-$weight.ttf').readAsBytes();
      font.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await font.load();
  });

  for (final size in const [Size(360, 740), Size(390, 844), Size(427, 952)]) {
    testWidgets('registration shows the original scrollable form at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        BlocProvider(
          create: (_) => AuthBloc(authRepository: _AuthRepository()),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const RegisterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      final submit = find.widgetWithText(ElevatedButton, 'สร้างบัญชี');
      final appBar = find.widgetWithText(AppBar, 'สมัครสมาชิก');
      expect(appBar, findsOneWidget);
      expect(
        tester.widget<AppBar>(appBar).backgroundColor,
        AppColors.primaryColor,
      );
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      expect(fields, findsNWidgets(5));

      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(submit.hitTestable(), findsOneWidget);

      final login = find.text('เข้าสู่ระบบ');
      await tester.ensureVisible(login);
      await tester.pumpAndSettle();
      expect(login.hitTestable(), findsOneWidget);
    });
  }

  testWidgets('keyboard Done brings the first invalid field into view', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider(
        create: (_) => AuthBloc(authRepository: _AuthRepository()),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const RegisterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.ensureVisible(fields.last);
    await tester.enterText(fields.last, 'abc123!def');
    await tester.pumpAndSettle();
    expect(fields.first.hitTestable(), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('กรุณากรอกชื่อโปรไฟล์').hitTestable(), findsOneWidget);
    expect(fields.first.hitTestable(), findsOneWidget);
  });
}

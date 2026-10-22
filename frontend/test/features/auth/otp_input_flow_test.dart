import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/domain/repositories/auth_repository.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/pages/one_time_verification.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pinput/pinput.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets('pasting a complete OTP waits for the confirm button', (
    tester,
  ) async {
    final repository = _MockAuthRepository();
    when(
      () => repository.verifyOtp(email: 'test@example.com', otpCode: '123456'),
    ).thenThrow(Exception('test rejection'));
    final bloc = AuthBloc(authRepository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(
          home: OneTimeVerificationScreen(email: 'test@example.com'),
        ),
      ),
    );
    await tester.pump();
    final input = find.descendant(
      of: find.byType(Pinput),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '123456');
    await tester.pump();

    verifyNever(
      () => repository.verifyOtp(email: 'test@example.com', otpCode: '123456'),
    );
    final confirm = find.text('ยืนยัน');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();

    verify(
      () => repository.verifyOtp(email: 'test@example.com', otpCode: '123456'),
    ).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('incomplete OTP stays on the form and resend clears input', (
    tester,
  ) async {
    final repository = _MockAuthRepository();
    when(
      () => repository.sendOtp(email: 'test@example.com'),
    ).thenAnswer((_) async {});
    final bloc = AuthBloc(authRepository: repository);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(
          home: OneTimeVerificationScreen(email: 'test@example.com'),
        ),
      ),
    );
    await tester.pump();
    final input = find.descendant(
      of: find.byType(Pinput),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '12a3');
    expect(tester.widget<Pinput>(find.byType(Pinput)).controller!.text, '123');
    final confirm = find.text('ยืนยัน');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('กรุณากรอกรหัส OTP ให้ครบ 6 หลัก'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('ตกลง'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    verifyNever(
      () => repository.verifyOtp(
        email: any(named: 'email'),
        otpCode: any(named: 'otpCode'),
      ),
    );

    await tester.pump(const Duration(seconds: 61));
    final resend = find.text('ส่งรหัสอีกครั้ง');
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pump();
    verify(() => repository.sendOtp(email: 'test@example.com')).called(1);
    expect(
      tester.widget<Pinput>(find.byType(Pinput)).controller!.text,
      isEmpty,
    );
    expect(find.text('ส่งรหัส OTP ใหม่ในอีก 60s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

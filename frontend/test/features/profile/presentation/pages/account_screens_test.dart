import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:frontend/features/profile/data/models/user_profile_model.dart';
import 'package:frontend/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:frontend/features/profile/domain/entities/user_profile.dart';
import 'package:frontend/features/profile/domain/usecases/get_user_profile_usecase.dart';
import 'package:frontend/features/profile/presentation/bloc/profile_cubit.dart';
import 'package:frontend/features/profile/presentation/pages/account/edit_profile_screen.dart';
import 'package:frontend/features/profile/presentation/pages/account/setting_account_screen.dart';
import 'package:frontend/features/profile/presentation/pages/legal/privacy_policy_screen.dart';
import 'package:frontend/features/profile/presentation/pages/legal/terms_of_service_screen.dart';
import 'package:frontend/features/profile/presentation/pages/account/edit_contact_screen.dart';
import 'package:frontend/features/profile/presentation/pages/account/change_password_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../domain/usecases/profile_usecases_test.dart';

class _DelayedProfileRepository extends FakeProfileRepository {
  final response = Completer<UserProfile>();

  @override
  Future<UserProfile> getProfile({
    required String userId,
    String? accessToken,
  }) {
    return response.future;
  }
}

class _DelayedProfileDataSource extends ProfileRemoteDataSource {
  var response = Completer<UserProfileModel>();

  @override
  Future<UserProfileModel> getProfile({
    required String userId,
    String? accessToken,
  }) {
    return response.future;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('th'));
  testWidgets('account settings has no location permission entry', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingAccountScreen()));
    expect(find.text('แก้ไขข้อมูล'), findsOneWidget);
    expect(find.text('ข้อมูลติดต่อ'), findsOneWidget);
    expect(find.text('ข้อมูลบัตรประชาชน'), findsOneWidget);
    expect(find.text('แก้ไขพร้อมเพย์'), findsOneWidget);
    expect(find.text('สิทธิ์ตำแหน่ง'), findsNothing);
  });

  testWidgets('edit profile has no location permission section', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditProfileScreen()));
    expect(find.text('สิทธิ์ตำแหน่ง'), findsNothing);
  });

  testWidgets('username stays read-only during loading and its cooldown', (
    tester,
  ) async {
    final repository = _DelayedProfileRepository();
    final cubit = ProfileCubit(
      getUserProfile: GetUserProfileUseCase(repository),
    );
    addTearDown(cubit.close);
    final loading = cubit.loadProfile(userId: 'u1');
    await tester.pumpWidget(MaterialApp(home: EditProfileScreen(cubit: cubit)));
    TextField usernameField() =>
        tester.widget<TextField>(find.byType(TextField).at(1));

    expect(usernameField().readOnly, isTrue);
    repository.response.complete(
      UserProfile(
        userId: 'u1',
        username: 'elle.com_',
        usernameChangedAt: DateTime.now().toUtc(),
      ),
    );
    await loading;
    await tester.pump();

    expect(usernameField().controller!.text, 'elle.com_');
    expect(usernameField().readOnly, isTrue);
    expect(find.textContaining('เปลี่ยนชื่อผู้ใช้ได้อีกครั้ง'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).readOnly,
      isFalse,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'cached username appears on the first frame and unlocks after 30 days',
    (tester) async {
      final source = _DelayedProfileDataSource();
      final repository = ProfileRepositoryImpl(remoteDataSource: source);
      final profile = UserProfileModel(
        userId: 'cached-profile-user',
        username: 'elle.com_',
        usernameChangedAt: DateTime.now().toUtc().subtract(
          const Duration(days: 30),
        ),
      );
      source.response.complete(profile);
      await repository.getProfile(userId: profile.userId, accessToken: 'token');
      source.response = Completer<UserProfileModel>();
      final cubit = ProfileCubit(
        getUserProfile: GetUserProfileUseCase(repository),
      );
      addTearDown(cubit.close);
      final loading = cubit.loadProfile(
        userId: profile.userId,
        accessToken: 'token',
      );
      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(cubit: cubit)),
      );

      TextField usernameField() =>
          tester.widget<TextField>(find.byType(TextField).at(1));
      expect(usernameField().controller!.text, 'elle.com_');
      expect(usernameField().readOnly, isTrue);
      source.response.complete(profile);
      await loading;
      await tester.pump();
      expect(usernameField().readOnly, isFalse);
    },
  );

  testWidgets('contact email cannot accept edits that the API cannot save', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditContactScreen()));
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.readOnly, isTrue);
    expect(fields.last.readOnly, isFalse);
  });

  testWidgets('password form asks only for values used by the session API', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ProfileChangePasswordScreen()),
    );
    expect(find.text('รหัสผ่านเดิม'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  for (final entry in <String, Widget>{
    'profile': const EditProfileScreen(),
    'contact': const EditContactScreen(),
    'password': const ProfileChangePasswordScreen(),
    'privacy': const PrivacyPolicyScreen(),
    'terms': const TermsOfServiceScreen(),
  }.entries) {
    testWidgets(
      '${entry.key} scrolls without overflow at narrow width and large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: entry.value,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -800),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'password visibility toggle preserves validation and typed value',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ProfileChangePasswordScreen()),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'example-password',
      );
      await tester.tap(find.byTooltip('แสดงรหัสผ่าน').first);
      await tester.pump();
      final input = tester.widget<TextField>(find.byType(TextField).first);
      expect(input.obscureText, isFalse);
      expect(input.controller!.text, 'example-password');
    },
  );

  testWidgets('bio icon aligns with the first line of its hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const EditProfileScreen()),
    );
    final icon = find.byIcon(Icons.info_outline_rounded);
    final hint = find.text('เขียนอะไรสักอย่างเกี่ยวกับตัวคุณ...');
    expect(
      (tester.getCenter(icon).dy - tester.getCenter(hint).dy).abs(),
      lessThan(1),
    );
  });
}

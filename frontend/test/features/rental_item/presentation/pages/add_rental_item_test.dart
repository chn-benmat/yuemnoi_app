import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/rental_item/domain/entities/rental_item.dart';
import 'package:frontend/features/rental_item/domain/repositories/rental_item_repository.dart';
import 'package:frontend/features/rental_item/domain/usecases/create_rental_item_usecase.dart';
import 'package:frontend/features/rental_item/presentation/bloc/rental_item_bloc.dart';
import 'package:frontend/features/rental_item/presentation/pages/add_rental_item.dart';

class NoopRentalItemRepository implements RentalItemRepository {
  @override
  Future<RentalItem> create(RentalItemDraft draft) async =>
      const RentalItem(id: 1, imageUrls: []);

  @override
  void close() {}
}

void main() {
  setUp(() => AuthSession.saveAccessToken('test-token'));
  tearDown(AuthSession.clear);

  testWidgets('searches categories and accepts hourly and daily prices', (
    tester,
  ) async {
    final bloc = RentalItemBloc(
      createItem: CreateRentalItemUseCase(NoopRentalItemRepository()),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const AddRentalItemScreen(),
        ),
      ),
    );

    expect(find.text('เพิ่มอุปกรณ์ให้เช่า'), findsOneWidget);
    expect(find.byKey(const Key('add-rental-images')), findsOneWidget);
    expect(find.text('0 / 5'), findsOneWidget);
    expect(find.text('ชื่ออุปกรณ์'), findsOneWidget);
    expect(find.text('หมวดหมู่'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('rental-item-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rental-item-category')));
    await tester.pumpAndSettle();
    expect(find.text('กล้องและอุปกรณ์ถ่ายภาพ'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('rental-category-search')),
      'ดนตรี',
    );
    await tester.pumpAndSettle();
    expect(find.text('กล้องและอุปกรณ์ถ่ายภาพ'), findsNothing);
    await tester.tap(find.text('ดนตรีและเครื่องดนตรี'));
    await tester.pumpAndSettle();
    expect(find.text('ดนตรีและเครื่องดนตรี'), findsOneWidget);
    expect(find.text('ราคาต่อชั่วโมง'), findsOneWidget);
    expect(find.text('ราคาต่อวัน'), findsOneWidget);
    final priceFields = {'hourly-price': '45', 'daily-price': '350'};
    for (final entry in priceFields.entries) {
      final section = find.byKey(ValueKey('rental-item-${entry.key}'));
      final field = find.descendant(
        of: section,
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: section, matching: find.text('บาท')),
        findsOneWidget,
      );
    }
    for (final value in priceFields.values) {
      expect(find.text(value), findsOneWidget);
    }
  });

  testWidgets('shows an error when submitting without an image', (
    tester,
  ) async {
    final bloc = RentalItemBloc(
      createItem: CreateRentalItemUseCase(NoopRentalItemRepository()),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const AddRentalItemScreen(),
        ),
      ),
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-rental-submit')));
    await tester.pump();

    await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
    await tester.pumpAndSettle();

    expect(find.text('กรุณาเพิ่มรูปภาพอย่างน้อย 1 รูป'), findsOneWidget);
  });

  testWidgets('keeps the add button fixed while the form scrolls', (
    tester,
  ) async {
    final bloc = RentalItemBloc(
      createItem: CreateRentalItemUseCase(NoopRentalItemRepository()),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const AddRentalItemScreen(),
        ),
      ),
    );

    final button = find.byKey(const Key('add-rental-submit'));
    final preview = find.byKey(const Key('add-rental-preview'));
    expect(preview, findsOneWidget);
    expect(tester.getCenter(preview).dx, lessThan(tester.getCenter(button).dx));
    final imagePicker = find.byKey(const Key('add-rental-images'));
    final buttonPositionBeforeScroll = tester.getCenter(button);
    final imagePickerPositionBeforeScroll = tester.getCenter(imagePicker);

    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(tester.getCenter(button), buttonPositionBeforeScroll);
    expect(
      tester.getCenter(imagePicker).dy,
      lessThan(imagePickerPositionBeforeScroll.dy),
    );
  });
}

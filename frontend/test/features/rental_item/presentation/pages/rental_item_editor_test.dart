import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';
import 'package:frontend/features/rental_item/domain/entities/rental_item.dart';
import 'package:frontend/features/rental_item/presentation/widgets/rental_item_editor.dart';
import 'package:frontend/features/rental_item/presentation/widgets/rental_item_form_value.dart';

final _first = RentalItemPhoto.local(
  RentalItemImage(
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a11sAAAAASUVORK5CYII=',
    ),
    fileName: 'first.png',
  ),
);
final _second = RentalItemPhoto.local(
  RentalItemImage(bytes: _first.localImage!.bytes, fileName: 'second.png'),
);
final _initial = RentalItemFormValue(
  name: 'Canon EOS R50',
  category: 'กล้องและอุปกรณ์ถ่ายภาพ',
  description: 'กล้องพร้อมเลนส์และแบตเตอรี่',
  dailyPrice: '350',
  photos: [_first, _second],
  pickupLocation: const PickupLocation(
    name: 'จุดนัดรับ',
    address: 'กรุงเทพมหานคร',
    latitude: 13.7,
    longitude: 100.5,
  ),
);

void main() {
  Future<void> phoneSize(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(414, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> confirmAdd(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('add-rental-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rental-confirm-submit')));
    await tester.pump();
  }

  testWidgets('edit form shows a heading above the two penalty inputs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1280, 2856);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: RentalItemEditor(
          initialValue: _initial,
          isEditing: true,
          onSubmit: (_) {},
        ),
      ),
    );

    final damageFee = find.descendant(
      of: find.byKey(const Key('edit-item-damage-fee')),
      matching: find.byType(TextFormField),
    );
    final lateFee = find.descendant(
      of: find.byKey(const Key('edit-item-late-return-fee')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(damageFee);
    await tester.pumpAndSettle();

    final heading = find.text('ค่าปรับ');
    final subtitle = find.text('เว้นว่างได้หากไม่มีค่าปรับ');
    expect(heading.hitTestable(), findsOneWidget);
    expect(subtitle.hitTestable(), findsOneWidget);
    expect(damageFee.hitTestable(), findsOneWidget);
    expect(lateFee.hitTestable(), findsOneWidget);
    final damageBounds = tester.getRect(damageFee);
    final lateBounds = tester.getRect(lateFee);

    expect(
      tester.getRect(heading).bottom,
      lessThan(tester.getRect(subtitle).top),
    );
    expect(tester.getRect(subtitle).bottom, lessThan(damageBounds.top));
    expect(damageBounds.top, lateBounds.top);
    expect(damageBounds.right, lessThan(lateBounds.left));
    expect(damageBounds.width, closeTo(lateBounds.width, 0.01));
    expect(
      tester.getTopLeft(find.text('เงื่อนไขกรณีชำรุด')).dy,
      greaterThan(damageBounds.bottom),
    );
  });

  testWidgets('submits a separate hourly and daily rental price', (
    tester,
  ) async {
    await phoneSize(tester);
    final submitted = <RentalItemFormValue>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RentalItemEditor(initialValue: _initial, onSubmit: submitted.add),
      ),
    );

    final hourlyPrice = find.byKey(const Key('rental-item-hourly-price'));
    final dailyPrice = find.byKey(const Key('rental-item-daily-price'));
    expect(hourlyPrice, findsOneWidget);
    expect(dailyPrice, findsOneWidget);
    expect(tester.getTopLeft(hourlyPrice).dy, tester.getTopLeft(dailyPrice).dy);
    expect(
      tester.getTopLeft(hourlyPrice).dx,
      lessThan(tester.getTopLeft(dailyPrice).dx),
    );
    await tester.ensureVisible(hourlyPrice);
    await tester.enterText(hourlyPrice, '75');
    await tester.ensureVisible(dailyPrice);
    await tester.enterText(dailyPrice, '410');
    final damageFee = find.byKey(const Key('rental-item-damage-fee'));
    await tester.ensureVisible(damageFee);
    await tester.enterText(damageFee, '125');
    final damageTerms = find.widgetWithText(
      TextFormField,
      'เช่น อุปกรณ์ตกแตกหรือมีชิ้นส่วนเสียหาย',
    );
    await tester.ensureVisible(damageTerms);
    await tester.enterText(damageTerms, 'เลนส์แตกร้าว');
    final lateFee = find.byKey(const Key('rental-item-late-return-fee'));
    await tester.ensureVisible(lateFee);
    await tester.enterText(lateFee, '50');
    await confirmAdd(tester);

    expect(submitted.single.rentalType, 'hourly');
    expect(submitted.single.price, 75);
    expect(submitted.single.additionalDailyPrice, 410);
    expect(submitted.single.penaltyTerms.damageFee, 125);
    expect(submitted.single.penaltyTerms.lateReturnFee, 50);
    expect(submitted.single.penaltyTerms.damageTerms, 'เลนส์แตกร้าว');
  });

  for (final unit in ['hourly', 'daily']) {
    testWidgets('$unit rental price rejects leading zeros', (tester) async {
      await phoneSize(tester);
      await tester.pumpWidget(
        MaterialApp(home: RentalItemEditor(onSubmit: (_) {})),
      );

      final price = find.byKey(ValueKey('rental-item-$unit-price'));
      final editable = find.descendant(
        of: price,
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(price);
      await tester.enterText(price, '0');
      expect(tester.widget<EditableText>(editable).controller.text, isEmpty);

      await tester.enterText(price, '00500');
      expect(tester.widget<EditableText>(editable).controller.text, isEmpty);

      await tester.enterText(price, '500');
      expect(tester.widget<EditableText>(editable).controller.text, '500');

      await tester.enterText(price, '0750');
      expect(tester.widget<EditableText>(editable).controller.text, '500');
    });
  }

  testWidgets('adding requires confirmation and cancel keeps the draft', (
    tester,
  ) async {
    await phoneSize(tester);
    final submitted = <RentalItemFormValue>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RentalItemEditor(initialValue: _initial, onSubmit: submitted.add),
      ),
    );
    expect(find.text('เพิ่มอุปกรณ์'), findsOneWidget);
    expect(find.text('ตรวจทานประกาศ'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('rental-item-name')));
    await tester.enterText(
      find.byKey(const Key('rental-item-name')),
      'Canon R50 พร้อมใช้งาน',
    );
    await tester.tap(find.byKey(const Key('add-rental-submit')));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.text('ยืนยันการเพิ่มอุปกรณ์?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rental-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Canon R50 พร้อมใช้งาน'), findsOneWidget);
    expect(submitted, isEmpty);
    await tester.tap(find.byKey(const Key('add-rental-submit')));
    await tester.pumpAndSettle();
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('rental-confirm-submit')),
    );
    confirm.onPressed!();
    confirm.onPressed!();
    await tester.pump();
    expect(submitted, hasLength(1));
    expect(submitted.single.name, 'Canon R50 พร้อมใช้งาน');
    expect(submitted.single.pickupLocation, _initial.pickupLocation);
    expect(find.byType(RentalItemEditor), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-rental-submit')));
    await tester.pump();
    expect(submitted, hasLength(1));
  });

  testWidgets(
    'swiping and tapping thumbnails browse without changing cover order',
    (tester) async {
      await phoneSize(tester);
      RentalItemFormValue? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: RentalItemEditor(
            initialValue: _initial,
            onSubmit: (value) => submitted = value,
          ),
        ),
      );
      await tester.drag(
        find.byKey(const Key('rental-photo-pages')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('รูปที่ 2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rental-photo-thumbnail-0')));
      await tester.pumpAndSettle();
      expect(find.text('รูปที่ 1 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rental-photo-thumbnail-1')));
      await tester.pumpAndSettle();
      expect(find.text('รูปที่ 2 / 2'), findsOneWidget);
      await confirmAdd(tester);
      expect(submitted!.photos, [_first, _second]);
    },
  );

  testWidgets('selected photo can be made the cover with one button', (
    tester,
  ) async {
    await phoneSize(tester);
    RentalItemFormValue? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: RentalItemEditor(
          initialValue: _initial,
          onSubmit: (value) => submitted = value,
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('rental-photo-pages')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rental-photo-set-cover')));
    await tester.pumpAndSettle();
    expect(find.text('รูปที่ 1 / 2'), findsOneWidget);
    expect(find.text('รูปปก'), findsOneWidget);
    await confirmAdd(tester);
    expect(submitted!.photos, [_second, _first]);
  });

  testWidgets(
    'direct delete keeps the current photo and clamps the page after removal',
    (tester) async {
      await phoneSize(tester);
      final third = RentalItemPhoto.local(
        RentalItemImage(bytes: _first.localImage!.bytes, fileName: 'third.png'),
      );
      final initial = RentalItemFormValue(
        name: _initial.name,
        category: _initial.category,
        description: _initial.description,
        dailyPrice: _initial.dailyPrice,
        pickupLocation: _initial.pickupLocation,
        photos: [_first, _second, third],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RentalItemEditor(initialValue: initial, onSubmit: (_) {}),
        ),
      );
      await tester.tap(find.byKey(const Key('rental-photo-thumbnail-2')));
      await tester.pumpAndSettle();
      expect(find.text('รูปที่ 3 / 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rental-photo-remove-0')));
      await tester.pumpAndSettle();
      expect(find.text('รูปที่ 2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rental-photo-remove-1')));
      await tester.pumpAndSettle();
      expect(find.text('รูปที่ 1 / 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rental-photo-remove-0')));
      await tester.pumpAndSettle();
      expect(find.text('0 / 5'), findsOneWidget);
      expect(find.byKey(const Key('rental-photo-add')), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-rental-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('กรุณาเพิ่มรูปภาพอย่างน้อย 1 รูป'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('full photo preview opens at the selected image and can swipe', (
    tester,
  ) async {
    await phoneSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: RentalItemEditor(initialValue: _initial, onSubmit: (_) {}),
      ),
    );
    await tester.tap(find.byKey(const Key('rental-photo-thumbnail-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rental-photo-pages')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    final previewPages = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(PageView),
    );
    await tester.drag(previewPages, const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('ปิดรูปภาพ'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'editing confirms before saving and preserves the form on failure',
    (tester) async {
      await phoneSize(tester);
      late StateSetter update;
      var saving = false;
      String? error;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return RentalItemEditor(
                initialValue: _initial,
                isEditing: true,
                isSaving: saving,
                errorMessage: error,
                onSubmit: (_) {
                  calls++;
                  update(() => saving = true);
                },
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('edit-item-submit')));
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันการบันทึกการแก้ไข?'), findsOneWidget);
      expect(calls, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('edit-item-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rental-confirm-submit')));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, 1);
      update(() {
        saving = false;
        error = 'เครือข่ายขัดข้อง กรุณาลองใหม่';
      });
      await tester.pumpAndSettle();
      expect(find.text(error!), findsOneWidget);
      expect(find.text('Canon EOS R50'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-item-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rental-confirm-submit')));
      await tester.pump();
      expect(calls, 2);
    },
  );

  testWidgets('photos can be reordered by a long press drag', (tester) async {
    await phoneSize(tester);
    RentalItemFormValue? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: RentalItemEditor(
          initialValue: _initial,
          onSubmit: (value) => submitted = value,
        ),
      ),
    );
    final thumbnails = find.byType(ReorderableDelayedDragStartListener);
    final start = tester.getCenter(thumbnails.first) - const Offset(20, 0);
    final end = tester.getCenter(thumbnails.last) + const Offset(35, 0);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(Offset.lerp(start, end, step / 12)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    await confirmAdd(tester);
    expect(submitted!.photos, [_second, _first]);
  });

  testWidgets('system back asks before losing changes and discard exits', (
    tester,
  ) async {
    await phoneSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RentalItemEditor(onSubmit: (_) {}),
                ),
              ),
              child: const Text('เปิดฟอร์ม'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดฟอร์ม'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('rental-item-name')));
    await tester.enterText(
      find.byKey(const Key('rental-item-name')),
      'ข้อมูลที่ยังไม่บันทึก',
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ออกโดยไม่บันทึก?'), findsOneWidget);
    await tester.tap(find.text('กรอกต่อ'));
    await tester.pumpAndSettle();
    expect(find.text('ข้อมูลที่ยังไม่บันทึก'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('ทิ้งการแก้ไข'));
    await tester.pumpAndSettle();
    expect(find.text('เปิดฟอร์ม'), findsOneWidget);
    expect(find.byType(RentalItemEditor), findsNothing);
  });

  testWidgets(
    'currency and rental unit stay visible when an empty price loses focus',
    (tester) async {
      await phoneSize(tester);
      await tester.pumpWidget(
        MaterialApp(home: RentalItemEditor(onSubmit: (_) {})),
      );
      for (final entry in {
        'hourly-price': 'ชั่วโมง',
        'daily-price': 'วัน',
      }.entries) {
        final price = find.byKey(ValueKey('rental-item-${entry.key}'));
        final currency = find.descendant(of: price, matching: find.text('฿'));
        final baht = find.descendant(of: price, matching: find.text('บาท'));
        final label = find.text('ราคาต่อ${entry.value}');
        await tester.ensureVisible(price);
        await tester.pumpAndSettle();
        expect(currency.hitTestable(), findsOneWidget);
        expect(baht.hitTestable(), findsOneWidget);
        expect(label.hitTestable(), findsOneWidget);
        await tester.enterText(price, '250');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.enterText(price, '');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(currency.hitTestable(), findsOneWidget);
        expect(baht.hitTestable(), findsOneWidget);
        expect(label.hitTestable(), findsOneWidget);
      }
    },
  );

  testWidgets('photo navigation also works with animations disabled', (
    tester,
  ) async {
    await phoneSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: RentalItemEditor(initialValue: _initial, onSubmit: (_) {}),
      ),
    );
    await tester.tap(find.byKey(const Key('rental-photo-thumbnail-1')));
    await tester.pumpAndSettle();
    expect(find.text('รูปที่ 2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form and confirmation fit mobile widths and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 375.0, 414.0, 768.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
            child: child!,
          ),
          home: RentalItemEditor(
            key: ValueKey(width),
            initialValue: _initial,
            onSubmit: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'form width $width');
      await tester.tap(find.byKey(const Key('add-rental-submit')));
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันการเพิ่มอุปกรณ์?'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'confirmation width $width',
      );
      await tester.tap(find.byKey(const Key('rental-confirm-cancel')));
      await tester.pumpAndSettle();
    }
  });
}

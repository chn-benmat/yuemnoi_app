import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/presentation/pages/location_picker_map_page.dart';

void main() {
  testWidgets('one tap on pickup search immediately shows the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LocationPickerMapPage()));
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
    );
    await tester.tap(search);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'one tap opens the keyboard and keeps the blinking cursor after keyboard resize',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(const MaterialApp(home: LocationPickerMapPage()));
      await tester.pump(const Duration(milliseconds: 500));
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
      );
      final editable = find.descendant(
        of: search,
        matching: find.byType(EditableText),
      );

      await tester.tap(search);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(
        tester.state<EditableTextState>(editable).cursorCurrentlyVisible,
        isTrue,
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<EditableText>(editable).focusNode.hasFocus,
        isTrue,
        reason:
            'Opening the keyboard must not remove focus from the search field.',
      );
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.state<EditableTextState>(editable).cursorCurrentlyVisible,
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.state<EditableTextState>(editable).cursorCurrentlyVisible,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/presentation/widgets/owner_item_controls.dart';

void main() {
  testWidgets('switch explains hidden state and disables while saving', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerItemVisibility(
            hidden: true,
            busy: true,
            onChanged: (_) => fail('busy switch fired'),
          ),
        ),
      ),
    );
    expect(find.text('คุณสามารถเปิดเพื่อแสดงสินค้า'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      false,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });

  testWidgets('delete uses the explicit item name and requires confirmation', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => OwnerItemDeleteButton(
              busy: false,
              deleting: false,
              onPressed: () async {
                result = await confirmItemDeletion(context, 'กล้องของฉัน');
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ลบอุปกรณ์'));
    await tester.pumpAndSettle();
    expect(find.textContaining('กล้องของฉัน'), findsOneWidget);
    expect(find.textContaining('กู้คืนไม่ได้'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(result, false);
    await tester.tap(find.text('ลบอุปกรณ์'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-item')));
    await tester.pumpAndSettle();
    expect(result, true);
    expect(find.textContaining('ถังขยะ'), findsNothing);
  });
}

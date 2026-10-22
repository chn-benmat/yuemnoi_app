import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/domain/entities/item_auto_reply.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/repositories/item_auto_reply_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/manage_item_auto_reply_usecase.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_auto_reply_cubit.dart';
import 'package:frontend/features/item_detail/presentation/pages/item_auto_reply_settings.dart';

class _Repository implements ItemAutoReplyRepository {
  ItemAutoReply stored = const ItemAutoReply();
  int saves = 0;
  bool fail = false;
  Completer<ItemAutoReply>? pending;
  @override
  Future<ItemAutoReply> load(int itemId) async => stored;
  @override
  Future<ItemAutoReply> save(int itemId, ItemAutoReply settings) async {
    saves++;
    if (fail) throw const ItemAutoReplyException('บันทึกไม่สำเร็จ');
    stored = pending == null ? settings : await pending!.future;
    return stored;
  }
}

const _item = ItemDetail(
  id: 7,
  owner: ItemOwner(userId: 'owner', displayName: 'Owner', imageUrl: ''),
  name: 'Canon EOS R50',
  imageUrls: [],
  description: '',
  category: 'กล้อง',
  price: 540,
  status: 'available',
  rentalType: 'รายวัน',
  reviews: [],
  isOwner: true,
);

void main() {
  test('draft only takes effect after save and settings reload', () async {
    final repository = _Repository();
    final cubit = ItemAutoReplyCubit(
      itemId: 7,
      manage: ManageItemAutoReplyUseCase(repository),
    );
    addTearDown(cubit.close);
    await cubit.load();
    cubit.change(enabled: true, message: '  สวัสดีครับ  ');
    expect(repository.saves, 0);
    expect(repository.stored.enabled, false);
    await cubit.save();
    expect(cubit.state.dirty, false);
    expect(
      repository.stored,
      const ItemAutoReply(enabled: true, message: 'สวัสดีครับ'),
    );
    await cubit.load();
    expect(cubit.state.draft, repository.stored);
    cubit.change(enabled: false);
    await cubit.save();
    expect(
      repository.stored,
      const ItemAutoReply(enabled: false, message: 'สวัสดีครับ'),
    );
  });

  test('failed save retains draft and allows retry', () async {
    final repository = _Repository()..fail = true;
    final cubit = ItemAutoReplyCubit(
      itemId: 7,
      manage: ManageItemAutoReplyUseCase(repository),
    );
    addTearDown(cubit.close);
    await cubit.load();
    cubit.change(enabled: true, message: 'ตอบกลับ');
    await cubit.save();
    expect(cubit.state.error, 'บันทึกไม่สำเร็จ');
    expect(cubit.state.dirty, true);
    expect(cubit.state.draft.message, 'ตอบกลับ');
    repository.fail = false;
    await cubit.save();
    expect(cubit.state.justSaved, true);
  });

  test('repeated save while pending sends one request', () async {
    final repository = _Repository()..pending = Completer<ItemAutoReply>();
    final cubit = ItemAutoReplyCubit(
      itemId: 7,
      manage: ManageItemAutoReplyUseCase(repository),
    );
    addTearDown(cubit.close);
    await cubit.load();
    cubit.change(message: 'draft');
    final first = cubit.save();
    await cubit.save();
    expect(repository.saves, 1);
    repository.pending!.complete(const ItemAutoReply(message: 'draft'));
    await first;
    expect(cubit.state.saving, false);
  });

  test(
    'validation blocks blank enabled and overlength Unicode messages',
    () async {
      final repository = _Repository();
      final cubit = ItemAutoReplyCubit(
        itemId: 7,
        manage: ManageItemAutoReplyUseCase(repository),
      );
      addTearDown(cubit.close);
      await cubit.load();
      cubit.change(enabled: true, message: ' \n ');
      await cubit.save();
      expect(cubit.state.error, contains('พิมพ์ข้อความ'));
      cubit.change(message: 'ก' * 501);
      await cubit.save();
      expect(cubit.state.error, contains('500'));
      expect(repository.saves, 0);
    },
  );

  testWidgets('settings remove prototype banner and save through repository', (
    tester,
  ) async {
    final repository = _Repository()
      ..stored = const ItemAutoReply(enabled: true, message: 'ข้อความเดิม');
    await tester.pumpWidget(
      MaterialApp(
        home: ItemAutoReplyScreen(
          item: _item,
          manage: ManageItemAutoReplyUseCase(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ตัวอย่างหน้าตั้งค่า'), findsNothing);
    expect(find.text('ข้อความที่พิมพ์ใช้เฉพาะตัวอย่างในหน้านี้'), findsNothing);
    expect(find.text('ข้อความเดิม'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('auto-reply-message')),
      'จะตอบกลับในไม่ช้า',
    );
    await tester.pump();
    expect(repository.saves, 0);
    await tester.ensureVisible(find.byKey(const ValueKey('save-auto-reply')));
    await tester.tap(find.byKey(const ValueKey('save-auto-reply')));
    await tester.pumpAndSettle();
    expect(repository.stored.message, 'จะตอบกลับในไม่ช้า');
    expect(find.text('บันทึกการตอบกลับอัตโนมัติแล้ว'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final message in [
    'สวัสดี',
    'ยินดีให้บริการ ติดต่อสอบถามรายละเอียดเพิ่มเติมได้เลยครับ ' * 7,
  ]) {
    testWidgets('preview sizes to content at 320px: ${message.length}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository()
        ..stored = ItemAutoReply(enabled: true, message: message);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ItemAutoReplyScreen(
            item: _item,
            manage: ManageItemAutoReplyUseCase(repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preview = find.text('ดูตัวอย่างในแชท');
      await tester.scrollUntilVisible(
        preview,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      await tester.tap(preview);
      await tester.pumpAndSettle();
      final size = tester.getSize(
        find.byKey(const ValueKey('auto-reply-preview-bubble')),
      );
      expect(size.width, lessThanOrEqualTo(246.4));
      if (message.length < 10)
        expect(size.width, lessThan(246.4));
      else
        expect(size.height, greaterThan(150));
      expect(tester.takeException(), isNull);
    });
  }
}

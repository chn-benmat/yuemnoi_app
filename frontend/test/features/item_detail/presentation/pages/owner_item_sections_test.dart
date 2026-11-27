import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/repositories/item_detail_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/update_item_usecase.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_bloc.dart';
import 'package:frontend/features/item_detail/presentation/pages/edit_item.dart';
import 'package:frontend/features/item_detail/presentation/widgets/owner_item_detail_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Repository extends Mock implements ItemDetailRepository {}

const _item = ItemDetail(
  id: 7,
  owner: ItemOwner(userId: 'owner', displayName: 'Owner', imageUrl: ''),
  name: 'Canon EOS R50',
  imageUrls: [],
  description: 'กล้องถ่ายภาพ',
  category: 'กล้องและอุปกรณ์ถ่ายภาพ',
  price: 540,
  status: 'available',
  rentalType: 'รายวัน',
  reviews: [],
  isOwner: true,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const appLinksChannels = [
    MethodChannel('com.llfbandit.app_links/events'),
    MethodChannel('com.llfbandit.app_links/messages'),
  ];
  final previewRequests = <Uri>[];

  setUpAll(() async {
    dotenv.loadFromString(
      envString:
          'SUPABASE_URL=https://preview.example.invalid\n'
          'SUPABASE_PUBLISHABLE_KEY=test-key',
    );
    SharedPreferences.setMockInitialValues({});
    for (final channel in appLinksChannels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
    }
    await http.runWithClient(
      SupabaseConfig.initialize,
      () => MockClient((request) async {
        previewRequests.add(request.url);
        throw StateError('Unexpected preview request: ${request.url.path}');
      }),
    );
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    for (final channel in appLinksChannels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
    dotenv.clean();
  });

  testWidgets('preview uses unsaved edits and returns without saving', (
    tester,
  ) async {
    final repo = _Repository();
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(repo),
      updateItem: UpdateItemUseCase(repo),
      initialItem: _item,
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: EditItemScreen(item: _item),
        ),
      ),
    );
    final name = find.descendant(
      of: find.byKey(const Key('edit-item-name')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(name);
    await tester.enterText(name, 'ชื่อใหม่ที่ยังไม่บันทึก');
    await tester.tap(find.byKey(const Key('edit-item-preview')));
    await tester.pumpAndSettle();
    expect(find.text('ชื่อใหม่ที่ยังไม่บันทึก'), findsOneWidget);
    expect(find.text('รายละเอียดสินค้า'), findsOneWidget);
    expect(bloc.state.item, _item);
    await tester.tap(find.byTooltip('ย้อนกลับ'));
    await tester.pumpAndSettle();
    expect(find.text('แก้ไขอุปกรณ์'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(name).controller!.text,
      'ชื่อใหม่ที่ยังไม่บันทึก',
    );
    expect(find.text('ออกโดยไม่บันทึก?'), findsNothing);
    verifyZeroInteractions(repo);
    expect(previewRequests, isEmpty);
  });

  testWidgets(
    'hidden owner detail keeps visibility controls without a status badge',
    (tester) async {
      final item = _item.withVisibility(hidden: true);
      final visibilityChanges = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OwnerItemDetailView(
              item: item,
              busy: false,
              deleting: false,
              onRefresh: () async {},
              onVisibilityChanged: visibilityChanges.add,
              onEditBasic: () {},
              onAutoReply: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('กำลังซ่อน'), findsNothing);
      expect(find.text('แสดงในหน้าร้าน'), findsOneWidget);
      expect(find.text('เปิดให้เช่า'), findsNothing);
      expect(item.status, 'available');
      final visibility = find.byKey(const ValueKey('owner-item-visibility'));
      expect(tester.widget<SwitchListTile>(visibility).value, isFalse);
      await tester.ensureVisible(visibility);
      await tester.tap(visibility);
      expect(visibilityChanges, [true]);
    },
  );
  testWidgets('basic info includes all equipment fields and save', (
    tester,
  ) async {
    final repo = _Repository();
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(repo),
      updateItem: UpdateItemUseCase(repo),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: EditItemScreen(item: _item),
        ),
      ),
    );
    expect(find.text('รูปภาพอุปกรณ์'), findsOneWidget);
    expect(find.byKey(const Key('edit-item-name')), findsOneWidget);
    expect(find.byKey(const Key('edit-item-category')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('edit-item-hourly-price')),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('edit-item-hourly-price')), findsOneWidget);
    expect(find.byKey(const Key('edit-item-daily-price')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('บันทึกการแก้ไข'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('บันทึกการแก้ไข'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'option A fits a narrow screen with large text and each row works',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: OwnerItemDetailView(
                item: _item,
                busy: false,
                deleting: false,
                onRefresh: () async {},
                onVisibilityChanged: (_) {},
                onEditBasic: () => calls.add('basic'),
                onAutoReply: () => calls.add('auto-reply'),
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      for (final section in ['basic', 'auto-reply']) {
        final row = find.byKey(ValueKey('owner-edit-$section'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pump();
      }
      expect(calls, ['basic', 'auto-reply']);
      expect(find.text('ตั้งค่าการเช่า'), findsNothing);
      expect(find.text('รูปภาพ'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

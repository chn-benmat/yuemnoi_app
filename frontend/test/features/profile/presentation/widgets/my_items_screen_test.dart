import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/models/user_item_model.dart';
import 'package:frontend/features/profile/domain/entities/user_item.dart';
import 'package:frontend/features/profile/domain/usecases/get_my_items_usecase.dart';
import 'package:frontend/features/profile/presentation/pages/items/my_items_screen.dart';
import 'package:frontend/features/profile/presentation/widgets/items/my_items_widgets.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/core/navigation/item_detail_route_args.dart';

import '../../domain/usecases/user_items_usecases_test.dart';

const _camera = UserItem(
  id: 2,
  title: 'Sony Camera รุ่นสำหรับถ่ายภาพและวิดีโอที่มีชื่อยาว',
  subtitle: 'รายละเอียดที่ควรอยู่ในหน้ารายละเอียด',
  category: 'กล้อง',
  price: 125.5,
  status: 'available',
  isRentalOccupied: true,
  rentalType: 'รายชั่วโมง',
);
const _laptop = UserItem(
  id: 1,
  title: 'MacBook Pro',
  subtitle: '',
  category: 'คอมพิวเตอร์',
  price: 1000,
  status: 'available',
  rentalType: 'รายวัน',
);

class _Repository extends FakeUserItemsRepository {
  _Repository() {
    items = [_camera, _laptop];
  }
  var fail = false;
  var requests = 0;
  Future<List<UserItem>>? pending;
  Stream<void> changes = const Stream.empty();

  @override
  Stream<void> watchMyItemChanges(String userId) => changes;

  @override
  Future<List<UserItem>> getMyItems(String userId) async {
    requests++;
    if (fail) throw StateError('offline');
    if (pending != null) return await pending!;
    return items;
  }
}

Widget _app(_Repository repository, {double scale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: MyItemsScreen(
    userId: 'owner',
    getMyItems: GetMyItemsUseCase(repository),
  ),
);

Future<void> _selectStatus(WidgetTester tester, String status) async {
  await tester.tap(find.byKey(const ValueKey('my-items-filter-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('my-items-filter-$status')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('updates a review badge and filter counts on a live change', (
    tester,
  ) async {
    const pendingReview = UserItem(
      id: 1,
      title: 'MacBook Pro',
      subtitle: '',
      status: 'pending_review',
    );
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final repository = _Repository()
      ..items = [pendingReview]
      ..changes = changes.stream;
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'MacBook');
    expect(find.text('รอแอดมินตรวจสอบ'), findsOneWidget);

    final updatedItems = Completer<List<UserItem>>();
    repository.pending = updatedItems.future;
    changes.add(null);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    updatedItems.complete([_laptop]);
    await tester.pumpAndSettle();

    expect(find.text('รอแอดมินตรวจสอบ'), findsNothing);
    expect(find.text('เปิดให้เช่า'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'MacBook',
    );
    await tester.tap(find.byKey(const ValueKey('my-items-filter-button')));
    await tester.pumpAndSettle();
    for (final entry in {'pendingReview': '0', 'available': '1'}.entries) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('my-items-filter-${entry.key}')),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(changes.hasListener, isFalse);
  });

  testWidgets('a moderated listing appears as removed from public view', (
    tester,
  ) async {
    final moderated = UserItemModel.fromJson({
      'id': 20,
      'item_name': 'โต๊ะที่ถูกซ่อน',
      'status': 'available',
      'moderation_hidden': true,
    }).toEntity();
    final repository = _Repository()..items = [_laptop, moderated];
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _selectStatus(tester, 'hidden');
    expect(find.text('โต๊ะที่ถูกซ่อน'), findsOneWidget);
    expect(find.text('ถูกซ่อนโดยผู้ดูแล'), findsOneWidget);
    expect(find.text('เปิดให้เช่า'), findsNothing);
  });

  testWidgets(
    'hidden cards show one badge and the filter uses visibility counts',
    (tester) async {
      const hidden = UserItem(
        id: 9,
        title: 'Hidden Camera',
        subtitle: '',
        status: 'available',
        ownerHidden: true,
      );
      final repository = _Repository()..items = [_camera, _laptop, hidden];
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('my-item-9'));
      await tester.scrollUntilVisible(
        card,
        180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.descendant(of: card, matching: find.text('กำลังซ่อน')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('เปิดให้เช่า')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('my-items-filter-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('my-items-filter-maintenance')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('my-items-filter-unavailable')),
        findsNothing,
      );
      expect(find.text('อยู่ระหว่างดูแล'), findsNothing);
      expect(find.text('ยังไม่พร้อม'), findsNothing);
      for (final filter in ['available', 'rented', 'hidden']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('my-items-filter-$filter')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const ValueKey('my-items-filter-hidden')));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(find.byKey(const ValueKey('my-item-1')), findsNothing);
      expect(find.byKey(const ValueKey('my-item-2')), findsNothing);
    },
  );
  testWidgets(
    'only equipment shimmers; search and filter work during loading',
    (tester) async {
      final pending = Completer<List<UserItem>>();
      final repository = _Repository()..pending = pending.future;
      await tester.pumpWidget(_app(repository));
      await tester.pump(const Duration(milliseconds: 100));
      final search = find.byType(TextField);
      final filter = find.byKey(const ValueKey('my-items-filter-button'));
      final searchPosition = tester.getTopLeft(search);
      expect(find.byType(SkeletonShimmer), findsOneWidget);
      expect(
        find.ancestor(of: search, matching: find.byType(SkeletonShimmer)),
        findsNothing,
      );
      expect(
        find.ancestor(of: filter, matching: find.byType(SkeletonShimmer)),
        findsNothing,
      );
      expect(
        tester.getRect(search).right,
        lessThan(tester.getRect(filter).left),
      );
      expect(
        tester.getCenter(search).dy,
        closeTo(tester.getCenter(filter).dy, 1),
      );
      expect(
        tester.getTopLeft(find.byType(MyItemsLoadingSkeleton)).dy,
        greaterThan(tester.getRect(search).bottom),
      );
      await tester.enterText(search, 'sony');
      await tester.tap(filter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(MyItemsFilterSheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my-items-filter-rented')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<IconButton>(filter).isSelected, isTrue);
      pending.complete([_camera, _laptop]);
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonShimmer), findsNothing);
      expect(find.byKey(const ValueKey('my-item-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('my-item-1')), findsNothing);
      expect(tester.getTopLeft(search), searchPosition);
      expect(tester.widget<TextField>(search).controller!.text, 'sony');
    },
  );

  testWidgets('search and status combine; reset restores the inventory', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Repository()));
    await tester.pumpAndSettle();
    expect(find.text('อุปกรณ์ 2 รายการ'), findsOneWidget);
    expect(find.text('฿125.5 / ชั่วโมง'), findsOneWidget);
    expect(find.text(_camera.subtitle), findsNothing);
    await _selectStatus(tester, 'available');
    expect(find.byKey(const ValueKey('my-item-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-item-2')), findsNothing);
    await tester.enterText(find.byType(TextField), 'กล้อง');
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบอุปกรณ์ที่ตรงกัน'), findsOneWidget);
    expect(find.text('เปิดให้เช่า 0 รายการ'), findsOneWidget);
    await tester.tap(find.text('ล้างการค้นหาและตัวกรอง'));
    await tester.pumpAndSettle();
    expect(find.byType(MyItemCard), findsNWidgets(2));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'query error offers retry instead of claiming the owner has no items',
    (tester) async {
      final repository = _Repository()..fail = true;
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      expect(find.text('โหลดอุปกรณ์ไม่สำเร็จ'), findsOneWidget);
      expect(find.text('เริ่มปล่อยเช่าอุปกรณ์ชิ้นแรก'), findsNothing);
      repository.fail = false;
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.byType(MyItemCard), findsNWidgets(2));
    },
  );

  testWidgets(
    'pull refresh waits for the request while retaining visible items',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      final pending = Completer<List<UserItem>>();
      repository.pending = pending.future;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.requests, 2);
      expect(find.byType(MyItemCard), findsNWidgets(2));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete([_camera]);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(MyItemCard), findsOneWidget);
      expect(find.text('อุปกรณ์ 1 รายการ'), findsOneWidget);
    },
  );

  testWidgets('an empty inventory still supports pull refresh', (tester) async {
    final repository = _Repository()..items = [];
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(find.text('เริ่มปล่อยเช่าอุปกรณ์ชิ้นแรก'), findsOneWidget);
    repository.items = [_camera];
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.byType(MyItemCard), findsOneWidget);
  });

  testWidgets(
    'returning from details reloads data and keeps the search/filter',
    (tester) async {
      final repository = _Repository();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, route) => MyItemsScreen(
              userId: 'owner',
              getMyItems: GetMyItemsUseCase(repository),
            ),
          ),
          GoRoute(
            path: '/items/:id',
            builder: (_, route) {
              expect(
                route.extra,
                isA<ItemDetailRouteArgs>().having(
                  (args) => args.ownerLoadingLayout,
                  'owner loading layout',
                  isTrue,
                ),
              );
              return Scaffold(
                appBar: AppBar(title: const Text('รายละเอียดเดิม')),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sony');
      await _selectStatus(tester, 'rented');
      await tester.tap(find.byKey(const ValueKey('my-item-2')));
      await tester.pumpAndSettle();
      expect(find.text('รายละเอียดเดิม'), findsOneWidget);
      repository.items = [
        const UserItem(
          id: 2,
          title: 'Sony Camera อัปเดตแล้ว',
          subtitle: '',
          price: 250,
          status: 'available',
          isRentalOccupied: true,
          rentalType: 'รายชั่วโมง',
        ),
      ];
      router.pop();
      await tester.pumpAndSettle();
      expect(repository.requests, 2);
      expect(find.text('฿250 / ชั่วโมง'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'sony',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('my-items-filter-button')),
            )
            .isSelected,
        isTrue,
      );
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('cards and controls fit 320px with text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(_Repository(), scale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('เพิ่มอุปกรณ์'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my-items-filter-button')));
      await tester.pumpAndSettle();
      expect(find.byType(MyItemsFilterSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('my-items-filter-all')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('my-items-filter-hidden')),
        100,
        scrollable: find.descendant(
          of: find.byType(MyItemsFilterSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('my-items-filter-hidden')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _selectStatus(tester, 'all');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('my-item-1')),
        180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

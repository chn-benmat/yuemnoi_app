import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/favorite_service.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/entities/related_item.dart';
import 'package:frontend/features/item_detail/domain/repositories/item_detail_repository.dart';
import 'package:frontend/features/item_detail/domain/repositories/related_items_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_related_items_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/update_item_usecase.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_bloc.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_event.dart';
import 'package:frontend/features/item_detail/presentation/pages/item_detail.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DetailRepository extends Mock implements ItemDetailRepository {}

class _RelatedRepository implements RelatedItemsRepository {
  _RelatedRepository(this.load);
  final Future<List<RelatedItem>> Function() load;
  @override
  Future<List<RelatedItem>> fetchByCategory(String category) => load();
}

void main() {
  const related = [
    RelatedItem(
      id: 8,
      name: 'Canon EOS R10 พร้อมเลนส์สำหรับถ่ายภาพ',
      category: 'กล้อง',
      price: 1200,
      rentalType: 'รายวัน',
    ),
    RelatedItem(
      id: 9,
      name: 'Sony Alpha',
      category: 'กล้อง',
      price: 1500,
      rentalType: 'รายชั่วโมง',
    ),
  ];
  const item = ItemDetail(
    id: 7,
    owner: ItemOwner(
      userId: 'owner',
      displayName: 'Owner',
      imageUrl: '',
      isVerified: true,
    ),
    name: 'Canon EOS R50',
    imageUrls: [],
    description: 'รายละเอียดกล้องสำหรับถ่ายภาพ',
    category: 'กล้อง',
    price: 1000,
    status: 'available',
    rentalType: 'รายวัน',
    reviews: [],
    isOwner: false,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FavoriteService.instance.init();
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    RelatedItemsRepository repository, {
    double textScale = 1,
    bool requestItem = false,
  }) async {
    final details = _DetailRepository();
    when(() => details.fetchById(7)).thenAnswer((_) async => item);
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(details),
      updateItem: UpdateItemUseCase(details),
      getRelatedItems: GetRelatedItemsUseCase(repository),
      initialItem: requestItem ? null : item,
    );
    if (requestItem) bloc.add(const ItemDetailRequested(7));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BlocProvider.value(
            value: bloc,
            child: const ItemDetailScreen(itemId: 7),
          ),
        ),
        GoRoute(
          path: '/items/:id',
          builder: (_, state) =>
              Scaffold(body: Text('สินค้า ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(bloc.close);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'places owner after description, then reviews, then related items',
    (tester) async {
      await pumpDetail(tester, _RelatedRepository(() async => related));
      await tester.pumpAndSettle();
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('รายละเอียดสินค้า'), lessThan(top('ปล่อยเช่าโดย')));
      expect(top('ปล่อยเช่าโดย'), lessThan(top('รีวิวล่าสุด')));
      expect(top('รีวิวล่าสุด'), lessThan(top('สินค้าใกล้เคียง')));
      await tester.ensureVisible(find.byKey(const ValueKey('related-item-8')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('related-item-8')));
      await tester.pumpAndSettle();
      expect(find.text('สินค้า 8'), findsOneWidget);
    },
  );

  testWidgets('keeps details and chat available while recommendations load', (
    tester,
  ) async {
    final result = Completer<List<RelatedItem>>();
    await pumpDetail(
      tester,
      _RelatedRepository(() => result.future),
      requestItem: true,
    );
    expect(find.text('Canon EOS R50'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('แชทสอบถาม'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
    result.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีสินค้าอื่นในหมวดนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retries a failed related request without replacing product details',
    (tester) async {
      var calls = 0;
      await pumpDetail(
        tester,
        _RelatedRepository(() async {
          if (++calls == 1) throw const RelatedItemsException('offline');
          return related;
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Canon EOS R50'), findsOneWidget);
      await tester.ensureVisible(find.text('ลองอีกครั้ง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลองอีกครั้ง'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byKey(const ValueKey('related-item-8')), findsOneWidget);
      expect(find.text('โหลดสินค้าใกล้เคียงไม่สำเร็จ'), findsNothing);
    },
  );

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('related cards fit ${width.toInt()}px at 130% text size', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDetail(
        tester,
        _RelatedRepository(() async => related),
        textScale: 1.3,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('related-items-list')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('related-item-8')), findsOneWidget);
      expect(find.text('แชทสอบถาม').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/repositories/item_detail_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/update_item_usecase.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_bloc.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_event.dart';
import 'package:frontend/features/item_detail/presentation/pages/item_detail.dart';

class _PendingItemDetailRepository implements ItemDetailRepository {
  final result = Completer<ItemDetail>();
  @override
  Future<ItemDetail> setVisibility(int itemId, {required bool hidden}) =>
      Completer<ItemDetail>().future;
  @override
  Future<void> delete(int itemId) => Completer<void>().future;
  @override
  Future<ItemDetail> fetchById(int itemId) => result.future;

  @override
  Future<ItemDetail> update(ItemEditDraft draft) =>
      Completer<ItemDetail>().future;
}

void main() {
  for (final requested in [false, true]) {
    testWidgets(
      'owner entry uses the owner layout ${requested ? 'while loading' : 'before the request starts'}',
      (tester) async {
        final repository = _PendingItemDetailRepository();
        final bloc = ItemDetailBloc(
          getItem: GetItemDetailUseCase(repository),
          updateItem: UpdateItemUseCase(repository),
        );
        addTearDown(bloc.close);
        if (requested) bloc.add(const ItemDetailRequested(7));
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(
              value: bloc,
              child: const ItemDetailScreen(
                itemId: 7,
                ownerLoadingLayout: true,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('owner-item-detail-skeleton')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('item-detail-skeleton')),
          findsNothing,
        );
        expect(find.text('รายละเอียดอุปกรณ์'), findsOneWidget);
        expect(find.byIcon(Icons.share_outlined), findsNothing);
        expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
        expect(find.byIcon(Icons.flag_outlined), findsNothing);
        expect(find.text('แชทสอบถาม'), findsNothing);
        expect(find.byKey(const ValueKey('owner-delete-item')), findsNothing);
        final photo = tester.getSize(
          find.byKey(const ValueKey('owner-photo-skeleton')),
        );
        expect(photo.width / photo.height, closeTo(1.5, .001));
        expect(tester.takeException(), isNull);
        if (requested) {
          repository.result.completeError(
            const ItemDetailException('โหลดไม่สำเร็จ'),
          );
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('loaded non-owner data overrides the appearance hint', (
    tester,
  ) async {
    final repository = _PendingItemDetailRepository();
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(repository),
      updateItem: UpdateItemUseCase(repository),
    );
    addTearDown(bloc.close);
    bloc.add(const ItemDetailRequested(7));
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const ItemDetailScreen(itemId: 7, ownerLoadingLayout: true),
        ),
      ),
    );
    await tester.pump();
    repository.result.complete(
      const ItemDetail(
        id: 7,
        owner: ItemOwner(
          userId: 'someone-else',
          displayName: 'Owner',
          imageUrl: '',
        ),
        name: 'Camera',
        imageUrls: [],
        description: '',
        category: 'กล้อง',
        price: 540,
        status: 'available',
        rentalType: 'รายวัน',
        reviews: [],
        isOwner: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('owner-item-detail-skeleton')),
      findsNothing,
    );
    expect(find.text('แชทสอบถาม'), findsOneWidget);
    expect(find.text('การแสดงผล'), findsNothing);
    expect(find.byKey(const ValueKey('owner-delete-item')), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
  });

  testWidgets('owner loading errors retain the owner header and retry action', (
    tester,
  ) async {
    final repository = _PendingItemDetailRepository();
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(repository),
      updateItem: UpdateItemUseCase(repository),
    );
    addTearDown(bloc.close);
    bloc.add(const ItemDetailRequested(7));
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const ItemDetailScreen(itemId: 7, ownerLoadingLayout: true),
        ),
      ),
    );
    await tester.pump();
    repository.result.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดอุปกรณ์'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(find.byType(SkeletonShimmer), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
  });

  testWidgets('shows a detail skeleton while item data is loading', (
    tester,
  ) async {
    final repository = _PendingItemDetailRepository();
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(repository),
      updateItem: UpdateItemUseCase(repository),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const ItemDetailScreen(itemId: 7),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('item-detail-skeleton')), findsOneWidget);
    expect(find.byType(SkeletonShimmer), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

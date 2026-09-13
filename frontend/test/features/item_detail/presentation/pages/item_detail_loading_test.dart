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
import 'package:frontend/features/item_detail/presentation/pages/item_detail.dart';

class _PendingItemDetailRepository implements ItemDetailRepository {
  @override
  Future<ItemDetail> fetchById(int itemId) => Completer<ItemDetail>().future;

  @override
  Future<ItemDetail> update(ItemEditDraft draft) =>
      Completer<ItemDetail>().future;
}

void main() {
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

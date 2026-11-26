import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/usecases/get_my_items_usecase.dart';
import 'package:frontend/features/profile/domain/entities/user_item.dart';
import 'package:frontend/features/profile/presentation/bloc/my_items_cubit.dart';
import 'package:frontend/features/profile/presentation/bloc/my_items_state.dart';

import '../../domain/usecases/user_items_usecases_test.dart';

void main() {
  group('MyItemsCubit', () {
    test(
      'hidden filters follow visibility, exclude rental totals, and survive refresh',
      () async {
        const hiddenAvailable = UserItem(
          id: 10,
          title: 'Hidden Camera',
          subtitle: '',
          status: 'available',
          ownerHidden: true,
        );
        const hiddenRented = UserItem(
          id: 11,
          title: 'Hidden Laptop',
          subtitle: '',
          status: 'available',
          isRentalOccupied: true,
          ownerHidden: true,
        );
        const unavailable = UserItem(
          id: 12,
          title: 'Unavailable',
          subtitle: '',
          status: 'unavailable',
        );
        const maintenance = UserItem(
          id: 13,
          title: 'Maintenance',
          subtitle: '',
          status: 'maintenance',
        );
        final repository = FakeUserItemsRepository()
          ..items = [
            ..._items,
            hiddenAvailable,
            hiddenRented,
            unavailable,
            maintenance,
          ];
        final cubit = MyItemsCubit(getMyItems: GetMyItemsUseCase(repository));
        addTearDown(cubit.close);
        await cubit.loadMyItems('owner');
        var state = cubit.state as MyItemsLoaded;
        expect(state.countFor(null), 7);
        expect(state.countFor(MyItemsFilter.available), 2);
        expect(state.countFor(MyItemsFilter.rented), 1);
        expect(state.countFor(MyItemsFilter.hidden), 2);
        cubit.filterByStatus(MyItemsFilter.hidden);
        expect((cubit.state as MyItemsLoaded).visibleItems.map((i) => i.id), [
          10,
          11,
        ]);
        cubit.search('camera');
        expect((cubit.state as MyItemsLoaded).visibleItems.single.id, 10);
        repository.items = [..._items, hiddenRented, unavailable, maintenance];
        await cubit.loadMyItems('owner');
        state = cubit.state as MyItemsLoaded;
        expect(state.statusFilter, MyItemsFilter.hidden);
        expect(state.countFor(MyItemsFilter.hidden), 1);
        expect(state.visibleItems, isEmpty);
        cubit.search('');
        expect((cubit.state as MyItemsLoaded).visibleItems.single.id, 11);
        expect(hiddenAvailable.listingStatus, UserItemStatus.available);
        expect(hiddenRented.listingStatus, UserItemStatus.rented);
        cubit.clearFilters();
        expect(
          (cubit.state as MyItemsLoaded).visibleItems,
          containsAll([unavailable, maintenance]),
        );
      },
    );
    test(
      'combines name/category search with status without changing totals',
      () async {
        final repository = FakeUserItemsRepository()..items = _items;
        final cubit = MyItemsCubit(getMyItems: GetMyItemsUseCase(repository));
        addTearDown(cubit.close);
        await cubit.loadMyItems('owner');
        cubit.search('  SONY  ');
        cubit.filterByStatus(MyItemsFilter.rented);
        var state = cubit.state as MyItemsLoaded;
        expect(state.visibleItems.map((item) => item.id), [2]);
        expect(state.countFor(null), 3);
        expect(state.countFor(MyItemsFilter.available), 2);
        cubit.search('กล้อง');
        expect((cubit.state as MyItemsLoaded).visibleItems.single.id, 2);
        cubit.clearFilters();
        state = cubit.state as MyItemsLoaded;
        expect(state.visibleItems, _items);
        expect(state.hasActiveFilters, isFalse);
      },
    );

    test(
      'refresh keeps data and current filters until completion or error',
      () async {
        final repository = _ControlledRepository()..items = _items;
        final cubit = MyItemsCubit(getMyItems: GetMyItemsUseCase(repository));
        addTearDown(cubit.close);
        await cubit.loadMyItems('owner');
        cubit.filterByStatus(MyItemsFilter.rented);
        final pending = Completer<List<UserItem>>();
        repository.next = pending.future;
        final refresh = cubit.loadMyItems('owner');
        expect((cubit.state as MyItemsLoaded).isRefreshing, isTrue);
        expect((cubit.state as MyItemsLoaded).items, _items);
        cubit.search('sony');
        pending.completeError(StateError('offline'));
        await refresh;
        var state = cubit.state as MyItemsLoaded;
        expect(state.isRefreshing, isFalse);
        expect(state.refreshError, isNotNull);
        expect(state.visibleItems.single.id, 2);
        repository.next = Future.value(_items.take(2).toList());
        await cubit.loadMyItems('owner');
        state = cubit.state as MyItemsLoaded;
        expect(state.refreshError, isNull);
        expect(state.query, 'sony');
        expect(state.statusFilter, MyItemsFilter.rented);
      },
    );

    test('an initial request error is not an empty inventory', () async {
      final repository = _ControlledRepository()
        ..next = Future.error(StateError('offline'));
      final cubit = MyItemsCubit(getMyItems: GetMyItemsUseCase(repository));
      addTearDown(cubit.close);
      await cubit.loadMyItems('owner');
      expect(cubit.state, isA<MyItemsError>());
    });

    test('ignores stale responses and completion after disposal', () async {
      final repository = _ControlledRepository();
      final first = Completer<List<UserItem>>();
      final second = Completer<List<UserItem>>();
      repository.next = first.future;
      final cubit = MyItemsCubit(getMyItems: GetMyItemsUseCase(repository));
      final oldLoad = cubit.loadMyItems('owner');
      repository.next = second.future;
      final newLoad = cubit.loadMyItems('owner');
      second.complete(_items);
      await newLoad;
      first.complete([]);
      await oldLoad;
      expect((cubit.state as MyItemsLoaded).items, _items);
      final last = Completer<List<UserItem>>();
      repository.next = last.future;
      final lastLoad = cubit.loadMyItems('owner');
      await cubit.close();
      last.complete(_items);
      await lastLoad;
    });

    test('initial state is MyItemsInitial', () {
      final cubit = MyItemsCubit(
        getMyItems: GetMyItemsUseCase(FakeUserItemsRepository()),
      );
      expect(cubit.state, isA<MyItemsInitial>());
      cubit.close();
    });

    blocTest<MyItemsCubit, MyItemsState>(
      'loadMyItems emits [MyItemsLoading, MyItemsLoaded]',
      build: () => MyItemsCubit(
        getMyItems: GetMyItemsUseCase(FakeUserItemsRepository()),
      ),
      act: (cubit) => cubit.loadMyItems('u1'),
      expect: () => [
        isA<MyItemsLoading>(),
        isA<MyItemsLoaded>().having((s) => s.items.length, 'items.length', 1),
      ],
    );
  });
}

const _items = [
  UserItem(
    id: 3,
    title: 'Sony A7',
    subtitle: '',
    category: 'กล้อง',
    status: 'available',
  ),
  UserItem(
    id: 2,
    title: 'Sony FX3',
    subtitle: '',
    category: 'กล้อง',
    status: 'available',
    isRentalOccupied: true,
  ),
  UserItem(
    id: 1,
    title: 'MacBook',
    subtitle: '',
    category: 'คอมพิวเตอร์',
    status: 'available',
  ),
];

class _ControlledRepository extends FakeUserItemsRepository {
  Future<List<UserItem>>? next;

  @override
  Future<List<UserItem>> getMyItems(String userId) =>
      next ?? super.getMyItems(userId);
}

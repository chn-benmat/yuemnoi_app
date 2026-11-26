import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/entities/profile_storefront.dart';
import 'package:frontend/features/profile/domain/entities/user_item.dart';
import 'package:frontend/features/profile/domain/repositories/profile_storefront_repository.dart';
import 'package:frontend/features/profile/domain/usecases/get_profile_storefront_usecase.dart';
import 'package:frontend/features/profile/presentation/bloc/profile_storefront_cubit.dart';

class FakeStorefrontRepository implements ProfileStorefrontRepository {
  bool failIdentity = false;
  bool failItems = false;
  bool failReviews = false;
  int itemCalls = 0;
  Completer<void>? waitForItems;
  StorefrontIdentity identity = const StorefrontIdentity(
    displayName: 'เจ้าของอุปกรณ์',
    isVerified: true,
  );
  List<StorefrontItem> items = [
    const StorefrontItem(
      item: UserItem(
        id: 1,
        title: 'กล้องตัวแรก',
        subtitle: '',
        price: 100,
        status: 'available',
      ),
      status: 'available',
      rentalType: 'รายวัน',
    ),
    const StorefrontItem(
      item: UserItem(
        id: 2,
        title: 'กล้องตัวที่สอง',
        subtitle: '',
        price: 50,
        status: 'rented',
        isRentalOccupied: true,
      ),
      status: 'rented',
      rentalType: 'รายชั่วโมง',
    ),
  ];
  List<StorefrontReview> reviews = [];

  @override
  Future<StorefrontIdentity> getIdentity(String userId) async {
    if (failIdentity) throw StateError('identity unavailable');
    return identity;
  }

  @override
  Future<List<StorefrontItem>> getItems(String userId) async {
    itemCalls++;
    await waitForItems?.future;
    if (failItems) throw StateError('items unavailable');
    return items;
  }

  @override
  Future<List<StorefrontReview>> getReviews(List<int> itemIds) async {
    if (failReviews) throw StateError('reviews unavailable');
    return reviews;
  }
}

void main() {
  test(
    'owner average weights every valid review, independent of item averages',
    () async {
      final repository = FakeStorefrontRepository()
        ..reviews = [
          const StorefrontReview(itemId: 1, rating: 5),
          ...List.generate(
            3,
            (_) => const StorefrontReview(itemId: 2, rating: 1),
          ),
          const StorefrontReview(itemId: 999, rating: 5),
          const StorefrontReview(itemId: 1, rating: 0),
          const StorefrontReview(itemId: 1, rating: 6),
          const StorefrontReview(itemId: 1, rating: double.nan),
          const StorefrontReview(itemId: 1, rating: double.infinity),
        ];
      final data = await GetProfileStorefrontUseCase(
        repository,
      ).execute('owner');
      expect(data.reviews!.average, 2);
      expect(data.reviews!.count, 4);
      expect(data.items[0].reviews!.average, 5);
      expect(data.items[1].reviews!.average, 1);
      expect(data.items[1].status, 'rented');
      expect(data.items[1].rentalType, 'รายชั่วโมง');
    },
  );

  test('zero reviews and failed review requests remain distinct', () async {
    final repository = FakeStorefrontRepository();
    final usecase = GetProfileStorefrontUseCase(repository);
    final empty = await usecase.execute('owner');
    expect(empty.reviews!.count, 0);
    expect(empty.items.first.reviews!.count, 0);
    repository.failReviews = true;
    final failed = await usecase.execute('owner');
    expect(failed.reviews, isNull);
    expect(failed.items.first.reviews, isNull);
    expect(failed.items.length, 2);
  });

  test('public identity failure keeps inventory usable', () async {
    final repository = FakeStorefrontRepository()..failIdentity = true;
    final data = await GetProfileStorefrontUseCase(repository).execute('owner');
    expect(data.identityUnavailable, isTrue);
    expect(data.items.length, 2);
  });

  test('item failure does not become a successful empty inventory', () async {
    final repository = FakeStorefrontRepository()..failItems = true;
    await expectLater(
      GetProfileStorefrontUseCase(repository).execute('owner'),
      throwsStateError,
    );
  });

  test('empty inventory does not require a reviews request', () async {
    final repository = FakeStorefrontRepository()
      ..items = []
      ..failReviews = true;
    final data = await GetProfileStorefrontUseCase(repository).execute('owner');
    expect(data.items, isEmpty);
    expect(data.reviews!.count, 0);
  });

  test('refresh failure retains last successful storefront', () async {
    final repository = FakeStorefrontRepository();
    final cubit = ProfileStorefrontCubit(
      userId: 'owner',
      getStorefront: GetProfileStorefrontUseCase(repository),
    );
    addTearDown(cubit.close);
    await cubit.load();
    final loaded = cubit.state.data;
    repository.failItems = true;
    await cubit.load();
    expect(cubit.state.hasError, isTrue);
    expect(cubit.state.data, same(loaded));
    repository.failItems = false;
    await cubit.load();
    expect(cubit.state.hasError, isFalse);
  });

  test(
    'concurrent refreshes share a request and closing during load is safe',
    () async {
      final repository = FakeStorefrontRepository()
        ..waitForItems = Completer<void>();
      final cubit = ProfileStorefrontCubit(
        userId: 'owner',
        getStorefront: GetProfileStorefrontUseCase(repository),
      );
      final first = cubit.load();
      final second = cubit.load();
      expect(repository.itemCalls, 1);
      await cubit.close();
      repository.waitForItems!.complete();
      await Future.wait([first, second]);
    },
  );
}

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/repositories/item_detail_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/update_item_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/manage_owner_item_usecase.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_bloc.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_event.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockItemDetailRepository extends Mock implements ItemDetailRepository {}

void main() {
  late _MockItemDetailRepository repository;

  const owner = ItemOwner(
    userId: 'owner-id',
    displayName: 'Jessica',
    imageUrl: '',
  );
  const item = ItemDetail(
    id: 7,
    owner: owner,
    name: 'ชุดรวมเลนส์รวม',
    imageUrls: [],
    description: 'รายละเอียด',
    category: 'กล้องและอุปกรณ์ถ่ายภาพ',
    price: 1000,
    status: 'verified',
    rentalType: 'รายวัน',
    reviews: [],
    isOwner: true,
  );
  const draft = ItemEditDraft(
    itemId: 7,
    name: 'ชุดรวมเลนส์รวม',
    category: 'กล้องและอุปกรณ์ถ่ายภาพ',
    description: 'รายละเอียดใหม่',
    rentalType: 'รายวัน',
    price: 1200,
    retainedImageUrls: ['https://example.com/lens.jpg'],
    newImages: [],
  );
  const updatedItem = ItemDetail(
    id: 7,
    owner: owner,
    name: 'ชุดรวมเลนส์รวม',
    imageUrls: ['https://example.com/lens.jpg'],
    description: 'รายละเอียดใหม่',
    category: 'กล้องและอุปกรณ์ถ่ายภาพ',
    price: 1200,
    status: 'verified',
    rentalType: 'รายวัน',
    reviews: [],
    isOwner: true,
  );

  ItemDetailBloc buildBloc({ItemDetail? initialItem}) => ItemDetailBloc(
    getItem: GetItemDetailUseCase(repository),
    updateItem: UpdateItemUseCase(repository),
    manageItem: ManageOwnerItemUseCase(repository),
    initialItem: initialItem,
  );

  setUp(() => repository = _MockItemDetailRepository());

  blocTest<ItemDetailBloc, ItemDetailState>(
    'hides only after persistence and preserves the rental state and details',
    setUp: () => when(
      () => repository.setVisibility(7, hidden: true),
    ).thenAnswer((_) async => item.withVisibility(hidden: true)),
    build: () => buildBloc(initialItem: item),
    act: (bloc) => bloc.add(const ItemVisibilityChanged(hidden: true)),
    expect: () => [
      const ItemDetailState(
        status: ItemDetailStatus.changingVisibility,
        item: item,
      ),
      ItemDetailState(
        status: ItemDetailStatus.loaded,
        item: item.withVisibility(hidden: true),
      ),
    ],
  );

  blocTest<ItemDetailBloc, ItemDetailState>(
    'restores the visibility switch when saving fails',
    setUp: () => when(
      () => repository.setVisibility(7, hidden: true),
    ).thenThrow(const ItemDetailException('บันทึกไม่สำเร็จ')),
    build: () => buildBloc(initialItem: item),
    act: (bloc) => bloc.add(const ItemVisibilityChanged(hidden: true)),
    expect: () => const [
      ItemDetailState(status: ItemDetailStatus.changingVisibility, item: item),
      ItemDetailState(
        status: ItemDetailStatus.failure,
        item: item,
        errorMessage: 'บันทึกไม่สำเร็จ',
      ),
    ],
  );

  blocTest<ItemDetailBloc, ItemDetailState>(
    'permanently deletes once despite repeated taps',
    setUp: () => when(() => repository.delete(7)).thenAnswer((_) async {}),
    build: () => buildBloc(initialItem: item),
    act: (bloc) {
      bloc.add(const ItemDeleteSubmitted());
      bloc.add(const ItemDeleteSubmitted());
    },
    expect: () => const [
      ItemDetailState(status: ItemDetailStatus.deleting, item: item),
      ItemDetailState(status: ItemDetailStatus.deleted, item: item),
    ],
    verify: (_) => verify(() => repository.delete(7)).called(1),
  );

  blocTest<ItemDetailBloc, ItemDetailState>(
    'retains a referenced item and exposes the server reason',
    setUp: () => when(
      () => repository.delete(7),
    ).thenThrow(const ItemDetailException('อุปกรณ์มีประวัติการจอง')),
    build: () => buildBloc(initialItem: item),
    act: (bloc) => bloc.add(const ItemDeleteSubmitted()),
    expect: () => const [
      ItemDetailState(status: ItemDetailStatus.deleting, item: item),
      ItemDetailState(
        status: ItemDetailStatus.failure,
        item: item,
        errorMessage: 'อุปกรณ์มีประวัติการจอง',
      ),
    ],
  );

  blocTest<ItemDetailBloc, ItemDetailState>(
    'loads a real item detail',
    setUp: () =>
        when(() => repository.fetchById(7)).thenAnswer((_) async => item),
    build: buildBloc,
    act: (bloc) => bloc.add(const ItemDetailRequested(7)),
    expect: () => const [
      ItemDetailState(status: ItemDetailStatus.loading),
      ItemDetailState(status: ItemDetailStatus.loaded, item: item),
    ],
    verify: (_) => verify(() => repository.fetchById(7)).called(1),
  );

  blocTest<ItemDetailBloc, ItemDetailState>(
    'updates an owner item and publishes the refreshed detail',
    setUp: () => when(
      () => repository.update(draft),
    ).thenAnswer((_) async => updatedItem),
    build: () => buildBloc(initialItem: item),
    act: (bloc) => bloc.add(const ItemDetailUpdateSubmitted(draft)),
    expect: () => const [
      ItemDetailState(status: ItemDetailStatus.updating, item: item),
      ItemDetailState(status: ItemDetailStatus.loaded, item: updatedItem),
    ],
    verify: (_) => verify(() => repository.update(draft)).called(1),
  );

  blocTest<ItemDetailBloc, ItemDetailState>(
    'surfaces repository failures without discarding the loaded item',
    setUp: () => when(
      () => repository.update(draft),
    ).thenThrow(const ItemDetailException('ไม่มีสิทธิ์แก้ไข')),
    build: () => buildBloc(initialItem: item),
    act: (bloc) => bloc.add(const ItemDetailUpdateSubmitted(draft)),
    expect: () => const [
      ItemDetailState(status: ItemDetailStatus.updating, item: item),
      ItemDetailState(
        status: ItemDetailStatus.failure,
        item: item,
        errorMessage: 'ไม่มีสิทธิ์แก้ไข',
      ),
    ],
  );
}

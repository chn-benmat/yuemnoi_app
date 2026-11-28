import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/rental_item/domain/entities/rental_item.dart';
import 'package:frontend/features/rental_item/domain/repositories/rental_item_repository.dart';
import 'package:frontend/features/rental_item/domain/usecases/create_rental_item_usecase.dart';
import 'package:frontend/features/rental_item/presentation/bloc/rental_item_bloc.dart';
import 'package:frontend/features/rental_item/presentation/bloc/rental_item_event.dart';
import 'package:frontend/features/rental_item/presentation/bloc/rental_item_state.dart';

class FakeRentalItemRepository implements RentalItemRepository {
  RentalItemDraft? submittedDraft;

  @override
  Future<RentalItem> create(RentalItemDraft draft) async {
    submittedDraft = draft;
    return const RentalItem(
      id: 42,
      imageUrls: ['https://example.test/42/image.png'],
    );
  }

  @override
  void close() {}
}

void main() {
  RentalItemImage image(int index) => RentalItemImage(
    bytes: Uint8List.fromList([index]),
    fileName: '$index.png',
  );

  RentalItemDraft draftWithImages(List<RentalItemImage> images) =>
      RentalItemDraft(
        name: 'Camera',
        category: 'Photography',
        description: 'Camera with lens',
        dailyRate: 200,
        images: images,
      );

  blocTest<RentalItemBloc, RentalItemState>(
    'keeps no more than five selected images',
    build: () => RentalItemBloc(
      createItem: CreateRentalItemUseCase(FakeRentalItemRepository()),
    ),
    act: (bloc) => bloc.add(RentalItemImagesAdded(List.generate(6, image))),
    verify: (bloc) => expect(bloc.state.images, hasLength(5)),
  );

  blocTest<RentalItemBloc, RentalItemState>(
    'rejects submission without an image',
    build: () => RentalItemBloc(
      createItem: CreateRentalItemUseCase(FakeRentalItemRepository()),
    ),
    act: (bloc) => bloc.add(RentalItemSubmitted(draftWithImages(const []))),
    expect: () => [
      isA<RentalItemState>()
          .having(
            (state) => state.status,
            'status',
            RentalItemSubmissionStatus.failure,
          )
          .having(
            (state) => state.errorMessage,
            'errorMessage',
            'กรุณาเพิ่มรูปภาพอย่างน้อย 1 รูป',
          ),
    ],
  );

  blocTest<RentalItemBloc, RentalItemState>(
    'rejects submission with more than five images',
    build: () => RentalItemBloc(
      createItem: CreateRentalItemUseCase(FakeRentalItemRepository()),
    ),
    act: (bloc) =>
        bloc.add(RentalItemSubmitted(draftWithImages(List.generate(6, image)))),
    expect: () => [
      isA<RentalItemState>()
          .having(
            (state) => state.status,
            'status',
            RentalItemSubmissionStatus.failure,
          )
          .having(
            (state) => state.errorMessage,
            'errorMessage',
            'เพิ่มรูปภาพได้ไม่เกิน 5 รูป',
          ),
    ],
  );

  test('submits the selected rental type and images', () async {
    final repository = FakeRentalItemRepository();
    final bloc = RentalItemBloc(
      createItem: CreateRentalItemUseCase(repository),
    );
    addTearDown(bloc.close);
    final draft = RentalItemDraft(
      name: 'กล้อง',
      category: 'ถ่ายภาพ',
      description: 'กล้องพร้อมเลนส์',
      hourlyRate: 200,
      images: [image(1)],
    );

    bloc.add(RentalItemSubmitted(draft));
    await expectLater(
      bloc.stream,
      emitsThrough(
        isA<RentalItemState>().having(
          (state) => state.status,
          'status',
          RentalItemSubmissionStatus.success,
        ),
      ),
    );

    expect(repository.submittedDraft?.hourlyRate, 200);
    expect(repository.submittedDraft?.images, hasLength(1));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/item_detail/data/datasources/related_items_remote_data_source.dart';
import 'package:frontend/features/item_detail/data/repositories/related_items_repository_impl.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/repositories/related_items_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_related_items_usecase.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements ApiClient {}

void main() {
  late _Api api;
  late GetRelatedItemsUseCase useCase;
  const item = ItemDetail(
    id: 7,
    owner: ItemOwner(userId: 'owner', displayName: 'Owner', imageUrl: ''),
    name: 'Camera',
    imageUrls: [],
    description: '',
    category: 'กล้อง',
    price: 1000,
    status: 'available',
    rentalType: 'รายวัน',
    reviews: [],
    isOwner: false,
  );

  Map<String, dynamic> row(int id, {String category = 'กล้อง'}) => {
    'id': id,
    'item_name': 'Camera $id',
    'category': category,
    'price': 800,
    'type': 'hourly',
    'item_image_url': ['https://example.com/$id.jpg'],
  };

  setUp(() {
    api = _Api();
    useCase = GetRelatedItemsUseCase(
      RelatedItemsRepositoryImpl(RelatedItemsRemoteDataSource(apiClient: api)),
    );
  });

  void respond(Object? data, {int status = 200}) => when(
    () => api.get('/api/items', queryParameters: {'category': 'กล้อง'}),
  ).thenAnswer((_) async => ApiResponse(statusCode: status, data: data));

  test(
    'queries the public category and excludes current, duplicate, hidden and unrelated rows',
    () async {
      respond([
        row(7),
        row(8),
        row(8),
        row(9, category: 'อุปกรณ์เสริมกล้อง'),
        {...row(10), 'owner_hidden': true},
        {'id': 11, 'item_name': 'Missing price', 'category': 'กล้อง'},
        for (var id = 12; id < 21; id++) row(id),
      ]);
      final related = await useCase.execute(item);
      expect(related.map((candidate) => candidate.id), [8, 12, 13, 14, 15, 16]);
      expect(related.first.unitLabel, 'ชั่วโมง');
      expect(related.first.imageUrl, 'https://example.com/8.jpg');
      verify(
        () => api.get('/api/items', queryParameters: {'category': 'กล้อง'}),
      ).called(1);
    },
  );

  test(
    'an empty category response produces no invented recommendations',
    () async {
      respond([]);
      expect(await useCase.execute(item), isEmpty);
    },
  );

  test(
    'reads the real location, rental count, and occupancy from the feed',
    () async {
      respond([
        {
          ...row(8),
          'pickup_location': '  สยาม  ',
          'paid_booking_count': 4,
          'is_rental_occupied': true,
        },
        row(9),
      ]);

      final related = await useCase.execute(item);
      expect(related.first.locationName, 'สยาม');
      expect(related.first.paidBookingCount, 4);
      expect(related.first.isRentalOccupied, isTrue);
      expect(related.last.locationName, 'ไม่ระบุตำแหน่ง');
      expect(related.last.paidBookingCount, 0);
      expect(related.last.isRentalOccupied, isFalse);
    },
  );

  test(
    'missing images retain the real listing with an empty image URL',
    () async {
      respond([
        {...row(8), 'item_image_url': null},
      ]);
      expect((await useCase.execute(item)).single.imageUrl, isEmpty);
    },
  );

  test('missing rental units are not assigned a daily rate', () async {
    respond([
      {...row(8), 'type': null},
    ]);
    expect(await useCase.execute(item), isEmpty);
  });

  test(
    'server failure is exposed for retry rather than mock inventory',
    () async {
      respond({'error': 'unavailable'}, status: 503);
      await expectLater(
        useCase.execute(item),
        throwsA(isA<RelatedItemsException>()),
      );
    },
  );

  test(
    'malformed success responses are not presented as an empty catalog',
    () async {
      respond({'unexpected': true});
      await expectLater(
        useCase.execute(item),
        throwsA(isA<RelatedItemsException>()),
      );
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/domain/entities/feed_item.dart';
import 'package:frontend/features/home/domain/repositories/home_repository.dart';
import 'package:frontend/features/home/domain/usecases/get_home_feed_usecase.dart';
import 'package:frontend/features/home/presentation/bloc/home_bloc.dart';
import 'package:frontend/features/home/presentation/bloc/home_event.dart';
import 'package:frontend/features/home/presentation/bloc/home_state.dart';

class _MockFailingHomeRepository implements HomeRepository {
  @override
  Future<List<FeedCategory>> getCategories() async {
    throw Exception('Connection failed');
  }

  @override
  Future<List<FeedItem>> getCuratedItems() async {
    throw Exception('Connection failed');
  }

  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async {
    throw Exception('Connection failed');
  }

  @override
  Future<bool> toggleFavorite(String itemId) async => false;

  @override
  void clearCache() {}
}

void main() {
  group('HomeBloc Fallback Error handling', () {
    test(
      'emits HomeError with connection error message when server is down',
      () async {
        final repo = _MockFailingHomeRepository();
        final bloc = HomeBloc(
          homeRepository: repo,
          getHomeFeed: GetHomeFeedUseCase(repo),
        );

        bloc.add(const LoadHomeFeedStarted());

        await expectLater(
          bloc.stream,
          emitsInOrder([
            const HomeLoading(),
            const HomeError('ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาลองใหม่'),
          ]),
        );

        bloc.close();
      },
    );
  });
}

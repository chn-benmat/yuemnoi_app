import '../entities/profile_storefront.dart';
import '../repositories/profile_storefront_repository.dart';

class GetProfileStorefrontUseCase {
  const GetProfileStorefrontUseCase(this.repository);
  final ProfileStorefrontRepository repository;

  Future<ProfileStorefront> execute(String userId) async {
    if (userId.trim().isEmpty || userId == 'unknown') {
      throw ArgumentError('ไม่พบเจ้าของโปรไฟล์');
    }
    var identityUnavailable = false;
    final identityFuture = repository
        .getIdentity(userId)
        .then<StorefrontIdentity?>(
          (value) => value,
          onError: (Object error, StackTrace stack) {
            identityUnavailable = true;
            return null;
          },
        );
    final items = await repository.getItems(userId);
    final identity = await identityFuture;
    final ids = items.map((value) => value.item.id).whereType<int>().toSet();
    List<StorefrontReview>? reviews;
    try {
      reviews = ids.isEmpty ? [] : await repository.getReviews(ids.toList());
      reviews = reviews
          .where(
            (review) =>
                ids.contains(review.itemId) &&
                review.rating.isFinite &&
                review.rating >= 1 &&
                review.rating <= 5,
          )
          .toList();
    } catch (_) {
      reviews = null;
    }
    final byItem = <int, List<StorefrontReview>>{};
    for (final review in reviews ?? <StorefrontReview>[]) {
      byItem.putIfAbsent(review.itemId, () => []).add(review);
    }
    return ProfileStorefront(
      identity: identity,
      reviewDetails: reviews ?? const [],
      identityUnavailable: identityUnavailable,
      items: items
          .map(
            (item) => item.withReviews(
              reviews == null
                  ? null
                  : ReviewSummary.fromReviews(byItem[item.item.id] ?? []),
            ),
          )
          .toList(growable: false),
      // รวมรีวิวทุกแถวโดยตรง เพื่อไม่ให้สินค้าที่มีรีวิวน้อยมีน้ำหนักเกินจริง
      reviews: reviews == null ? null : ReviewSummary.fromReviews(reviews),
    );
  }
}

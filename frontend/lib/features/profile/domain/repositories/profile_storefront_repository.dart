import '../entities/profile_storefront.dart';

abstract class ProfileStorefrontRepository {
  Future<StorefrontIdentity> getIdentity(String userId);
  Future<List<StorefrontItem>> getItems(String userId);
  Future<List<StorefrontReview>> getReviews(List<int> itemIds);
}

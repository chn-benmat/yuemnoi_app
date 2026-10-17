import '../../domain/entities/profile_storefront.dart';
import '../../domain/repositories/profile_storefront_repository.dart';
import '../datasources/profile_storefront_remote_data_source.dart';
import '../models/user_item_model.dart';

class ProfileStorefrontRepositoryImpl implements ProfileStorefrontRepository {
  ProfileStorefrontRepositoryImpl({
    ProfileStorefrontRemoteDataSource? dataSource,
  }) : _dataSource = dataSource ?? ProfileStorefrontRemoteDataSource();

  final ProfileStorefrontRemoteDataSource _dataSource;

  @override
  Future<StorefrontIdentity> getIdentity(String userId) async {
    final json = await _dataSource.getIdentity(userId);
    return StorefrontIdentity(
      displayName: json['display_name']?.toString().trim() ?? '',
      avatarUrl: json['user_image_url']?.toString(),
      bio: json['bio']?.toString(),
      isVerified: json['is_verified'] == true,
    );
  }

  @override
  Future<List<StorefrontItem>> getItems(String userId) async {
    final rows = await _dataSource.getItems(userId);
    return rows
        .map(
          (row) => StorefrontItem(
            item: UserItemModel.fromJson(row).toEntity(),
            status: row['status']?.toString().trim() ?? '',
            rentalType: row['type']?.toString().trim() ?? '',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<StorefrontReview>> getReviews(List<int> itemIds) async {
    final rows = await _dataSource.getReviews(itemIds);
    return rows
        .map(
          (row) => StorefrontReview(
            itemId: int.tryParse('${row['item_id']}') ?? -1,
            rating: double.tryParse('${row['rating']}') ?? double.nan,
          ),
        )
        .toList(growable: false);
  }
}

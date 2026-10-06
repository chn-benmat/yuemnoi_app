import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/item_detail.dart';
import '../models/item_detail_model.dart';

class ItemDetailRemoteException implements Exception {
  const ItemDetailRemoteException(this.message);

  final String message;
}

class ItemDetailRemoteDataSource {
  ItemDetailRemoteDataSource({
    SupabaseClient? client,
    ApiClient? apiClient,
  })  : _client = client ?? SupabaseConfig.client,
        _apiClient = apiClient ?? DioApiClient();

  static const _bucket = 'item_bk';
  final SupabaseClient _client;
  final ApiClient _apiClient;

  Future<ItemDetail> fetchById(int itemId) async {
    try {
      final response = await _apiClient.get('/api/items/$itemId');
      if (response.statusCode == 200 && response.data is Map) {
        return ItemDetailModel.fromApiResponse(
          item: Map<String, dynamic>.from(response.data as Map),
          currentUserId: _client.auth.currentUser?.id,
        );
      }
      if (response.statusCode == 404) {
        throw const ItemDetailRemoteException('ไม่พบอุปกรณ์นี้');
      }
    } on ItemDetailRemoteException {
      rethrow;
    } catch (_) {
      // Fallback to direct supabase query if API is not reachable
    }

    try {
      final item = await _client
          .from('item_tb')
          .select(
            'id,user_id,item_name,item_image_url,description,category,price,status,type',
          )
          .eq('id', itemId)
          .maybeSingle();
      if (item == null) {
        throw const ItemDetailRemoteException('ไม่พบอุปกรณ์นี้');
      }

      final rawReviews = await _client
          .from('review_tb')
          .select('id,user_id,item_id,rating,description,created_at')
          .eq('item_id', itemId)
          .order('created_at', ascending: false)
          .limit(10);
      final reviews = rawReviews.cast<Map<String, dynamic>>();

      final userIds = <String>{
        if (item['user_id'] case final String ownerId) ownerId,
        for (final review in reviews)
          if (review['user_id'] case final String reviewerId) reviewerId,
      };
      final profilesByUserId = <String, Map<String, dynamic>>{};
      if (userIds.isNotEmpty) {
        final rawProfiles = await _client
            .from('public_profile_v')
            .select('user_id,user_image_url,display_name,email')
            .inFilter('user_id', userIds.toList(growable: false));
        for (final profile in rawProfiles.cast<Map<String, dynamic>>()) {
          final userId = profile['user_id'];
          if (userId is String) profilesByUserId[userId] = profile;
        }
      }

      return ItemDetailModel.fromRecords(
        item: item,
        profilesByUserId: profilesByUserId,
        reviews: reviews,
        currentUserId: _client.auth.currentUser?.id,
      );
    } on ItemDetailRemoteException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ItemDetailRemoteException(_databaseMessage(error));
    } on FormatException {
      throw const ItemDetailRemoteException('ข้อมูลอุปกรณ์ไม่ถูกต้อง');
    } catch (_) {
      throw const ItemDetailRemoteException(
        'โหลดรายละเอียดอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่',
      );
    }
  }

  Future<ItemDetail> update(ItemEditDraft draft) async {
    final user = _client.auth.currentUser;
    final session = _client.auth.currentSession;
    if (user == null || session == null) {
      throw const ItemDetailRemoteException('กรุณาเข้าสู่ระบบก่อนแก้ไขอุปกรณ์');
    }

    final uploadedPaths = <String>[];
    try {
      final uploadedUrls = <String>[];
      for (var index = 0; index < draft.newImages.length; index++) {
        final image = draft.newImages[index];
        final extension = _extension(image.fileName);
        final path =
            '${user.id}/${draft.itemId}/${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
        await _client.storage
            .from(_bucket)
            .uploadBinary(
              path,
              Uint8List.fromList(image.bytes),
              fileOptions: FileOptions(contentType: _contentType(extension)),
            );
        uploadedPaths.add(path);
        uploadedUrls.add(_client.storage.from(_bucket).getPublicUrl(path));
      }

      final imageUrls = [...draft.retainedImageUrls, ...uploadedUrls];
      if (imageUrls.isEmpty) {
        throw const ItemDetailRemoteException(
          'กรุณาเพิ่มรูปภาพอย่างน้อย 1 รูป',
        );
      }

      final response = await _apiClient.put(
        '/api/items/${draft.itemId}',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        data: {
          'item_name': draft.name.trim(),
          'category': draft.category.trim(),
          'description': draft.description.trim(),
          'type': draft.rentalType,
          'price': draft.price,
          'item_image_url': imageUrls,
        },
      );

      if (response.statusCode != 200) {
        final errorMsg = response.data is Map
            ? (response.data as Map)['error']?.toString()
            : null;
        throw ItemDetailRemoteException(
          errorMsg ?? 'แก้ไขอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่',
        );
      }

      return await fetchById(draft.itemId);
    } on ItemDetailRemoteException {
      await _removeNewUploads(uploadedPaths);
      rethrow;
    } on StorageException catch (error) {
      await _removeNewUploads(uploadedPaths);
      throw ItemDetailRemoteException(
        error.message.isEmpty ? 'อัปโหลดรูปภาพไม่สำเร็จ' : error.message,
      );
    } catch (_) {
      await _removeNewUploads(uploadedPaths);
      throw const ItemDetailRemoteException(
        'แก้ไขอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่',
      );
    }
  }

  Future<void> _removeNewUploads(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(_bucket).remove(paths);
    } catch (_) {
      // Best-effort rollback: the database row remains unchanged.
    }
  }

  static String _databaseMessage(PostgrestException error) {
    if (error.code == 'PGRST116') return 'ไม่พบอุปกรณ์นี้';
    return 'ไม่สามารถอ่านหรือบันทึกข้อมูลจาก Supabase ได้';
  }

  static String _extension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return 'jpg';
    final value = fileName.substring(index + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(value) ? value : 'jpg';
  }

  static String _contentType(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

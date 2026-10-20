import '../network/supabase_client.dart';

String networkImageCacheKey(String url, {String? ownerId}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.path.startsWith('/storage/v1/object/sign/chat_bk/')) {
    return url;
  }
  final userId =
      ownerId ??
      (SupabaseConfig.isInitialized
          ? SupabaseConfig.client.auth.currentUser?.id ?? 'guest'
          : 'guest');
  final query = Map<String, String>.from(uri.queryParameters)..remove('token');
  return 'chat:$userId:${uri.replace(queryParameters: query)}';
}

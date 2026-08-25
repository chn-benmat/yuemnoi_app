abstract final class ItemDeepLink {
  static const scheme = 'yuemnoi';
  static const host = 'items';

  static Uri build(int itemId) {
    return Uri(scheme: scheme, host: host, path: '/$itemId');
  }

  static int? parseItemId(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;
    if (uri.pathSegments.length != 1) return null;

    final itemId = int.tryParse(uri.pathSegments.single);
    return itemId != null && itemId > 0 ? itemId : null;
  }
}

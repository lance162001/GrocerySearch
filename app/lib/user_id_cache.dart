import 'user_id_cache_fallback.dart'
    if (dart.library.html) 'user_id_cache_web.dart' as impl;

Future<int?> readCachedUserId() => impl.readCachedUserId();
Future<void> writeCachedUserId(int userId) => impl.writeCachedUserId(userId);

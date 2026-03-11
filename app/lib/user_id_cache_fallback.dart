int? _cachedUserId;

Future<int?> readCachedUserId() async {
  if (_cachedUserId == null || _cachedUserId! <= 0) return null;
  return _cachedUserId;
}

Future<void> writeCachedUserId(int userId) async {
  if (userId <= 0) return;
  _cachedUserId = userId;
}

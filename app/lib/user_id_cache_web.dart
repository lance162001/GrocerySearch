import 'dart:html' as html;

const String _cacheKey = 'cached_user_id';

Future<int?> readCachedUserId() async {
  final raw = html.window.localStorage[_cacheKey];
  if (raw == null || raw.isEmpty) return null;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

Future<void> writeCachedUserId(int userId) async {
  if (userId <= 0) return;
  html.window.localStorage[_cacheKey] = '$userId';
}

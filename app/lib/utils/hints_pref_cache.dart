import 'hints_pref_cache_fallback.dart'
    if (dart.library.html) 'hints_pref_cache_web.dart' as impl;

Future<bool> readHideHints() => impl.readHideHints();
Future<void> writeHideHints(bool value) => impl.writeHideHints(value);

import 'package:flutter/foundation.dart' show kIsWeb;

class AppEnvironment {
  const AppEnvironment._({required this.useLocalBackend});

  static const String _remoteHostname = 'asktheinter.net';
  static const String _remotePort = '23451';
  static const String _defaultLocalPort = '8000';
  static const bool _webUseSameOriginApi = bool.fromEnvironment(
    'WEB_USE_SAME_ORIGIN_API',
  );
  static const String _webApiPathPrefix = String.fromEnvironment(
    'WEB_API_PATH_PREFIX',
    defaultValue: '',
  );
  static const String _localHostnameOverride =
      String.fromEnvironment('LOCAL_BACKEND_HOST', defaultValue: '');
  static const String _localPortOverride =
      String.fromEnvironment('LOCAL_BACKEND_PORT', defaultValue: _defaultLocalPort);

  static const AppEnvironment current =
      AppEnvironment._(useLocalBackend: bool.fromEnvironment('USE_LOCAL_BACKEND'));
  static const AppEnvironment local = AppEnvironment._(useLocalBackend: true);
  static const AppEnvironment remote = AppEnvironment._(useLocalBackend: false);

  final bool useLocalBackend;

  bool get _useSameOriginWebApi => useLocalBackend && kIsWeb && _webUseSameOriginApi;

  String get _normalizedWebApiPrefix {
    final trimmed = _webApiPathPrefix.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '';
    }
    var prefix = trimmed;
    if (!prefix.startsWith('/')) {
      prefix = '/$prefix';
    }
    while (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return prefix;
  }

  String _joinPath(String basePrefix, String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    if (basePrefix.isEmpty) {
      return normalizedPath;
    }
    return '$basePrefix$normalizedPath';
  }

  String get hostname {
    if (!useLocalBackend) {
      return _remoteHostname;
    }
    if (_localHostnameOverride.isNotEmpty) {
      return _localHostnameOverride;
    }

    // When the web app is opened from a LAN URL, reuse that host for API calls.
    final webHost = kIsWeb ? Uri.base.host.trim() : '';
    if (webHost.isNotEmpty) {
      return webHost;
    }

    return 'localhost';
  }

  String get port => useLocalBackend ? _localPortOverride : _remotePort;

  Uri uri(String path, [Map<String, String>? queryParameters]) {
    if (!useLocalBackend) {
      return Uri.https('$hostname:$port', path, queryParameters);
    }
    if (_useSameOriginWebApi) {
      return Uri(
        path: _joinPath(_normalizedWebApiPrefix, path),
        queryParameters: queryParameters,
      );
    }
    return Uri.http('$hostname:$port', path, queryParameters);
  }

  String resolveAssetUrl(String rawUrl) {
    if (rawUrl.startsWith('http')) {
      return rawUrl;
    }
    if (_useSameOriginWebApi) {
      return _joinPath(_normalizedWebApiPrefix, rawUrl);
    }
    final scheme = useLocalBackend ? 'http' : 'https';
    if (rawUrl.startsWith('/')) {
      return '$scheme://$hostname:$port$rawUrl';
    }
    return '$scheme://$hostname:$port/$rawUrl';
  }
}
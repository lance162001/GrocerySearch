import 'package:flutter/foundation.dart' show kIsWeb;

class AppEnvironment {
  const AppEnvironment._({required this.useLocalBackend});

  static const String _remoteHostname = 'asktheinter.net';
  static const String _remotePort = '23451';
  static const String _defaultLocalPort = '8000';
  static const String _localHostnameOverride =
      String.fromEnvironment('LOCAL_BACKEND_HOST', defaultValue: '');
  static const String _localPortOverride =
      String.fromEnvironment('LOCAL_BACKEND_PORT', defaultValue: _defaultLocalPort);

  static const AppEnvironment current =
      AppEnvironment._(useLocalBackend: bool.fromEnvironment('USE_LOCAL_BACKEND', defaultValue: true));
  static const AppEnvironment local = AppEnvironment._(useLocalBackend: true);
  static const AppEnvironment remote = AppEnvironment._(useLocalBackend: false);

  final bool useLocalBackend;

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
    return Uri.http('$hostname:$port', path, queryParameters);
  }

  String resolveAssetUrl(String rawUrl) {
    if (rawUrl.startsWith('http')) {
      return rawUrl;
    }
    if (rawUrl.startsWith('/')) {
      return 'http://$hostname:$port$rawUrl';
    }
    return 'http://$hostname:$port/$rawUrl';
  }
}
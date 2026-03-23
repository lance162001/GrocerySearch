// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

const String _key = 'hide_hints';

Future<bool> readHideHints() async {
  return html.window.localStorage[_key] == 'true';
}

Future<void> writeHideHints(bool value) async {
  html.window.localStorage[_key] = value ? 'true' : 'false';
}

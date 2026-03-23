bool _hideHints = false;

Future<bool> readHideHints() async => _hideHints;

Future<void> writeHideHints(bool value) async {
  _hideHints = value;
}

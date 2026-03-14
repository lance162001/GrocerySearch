double? parsePriceString(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty) {
    return null;
  }
  return double.tryParse(cleaned);
}

String formatPriceString(String raw) {
  final parsed = parsePriceString(raw);
  if (parsed == null) {
    return raw.startsWith(r'$') ? raw : '\$$raw';
  }
  return '\$${parsed.toStringAsFixed(2)}';
}
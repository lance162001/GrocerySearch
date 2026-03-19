import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/utils/price_utils.dart';

const double productPriceEpsilon = 0.01;

double? productEffectivePrice(Product product) {
  return parsePriceString(product.memberPrice) ??
      parsePriceString(product.salePrice) ??
      parsePriceString(product.basePrice);
}

bool productPricesMatch(double left, double right) {
  return (left - right).abs() < productPriceEpsilon;
}

int compareProductsByPrice(Product left, Product right) {
  final leftPrice = productEffectivePrice(left);
  final rightPrice = productEffectivePrice(right);
  if (leftPrice == null && rightPrice == null) {
    final nameComparison =
        left.name.toLowerCase().compareTo(right.name.toLowerCase());
    if (nameComparison != 0) {
      return nameComparison;
    }
    return left.storeId.compareTo(right.storeId);
  }
  if (leftPrice == null) {
    return 1;
  }
  if (rightPrice == null) {
    return -1;
  }

  final priceComparison = leftPrice.compareTo(rightPrice);
  if (priceComparison != 0) {
    return priceComparison;
  }

  final nameComparison =
      left.name.toLowerCase().compareTo(right.name.toLowerCase());
  if (nameComparison != 0) {
    return nameComparison;
  }
  return left.storeId.compareTo(right.storeId);
}

String _singularize(String word) {
  if (word.endsWith('ies') && word.length > 3) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.endsWith('oes') && word.length > 3) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('es') && word.length > 2) {
    final stem = word.substring(0, word.length - 2);
    if (stem.endsWith('ch') ||
        stem.endsWith('sh') ||
        stem.endsWith('s') ||
        stem.endsWith('x') ||
        stem.endsWith('z')) {
      return stem;
    }
  }
  if (word.endsWith('s') && !word.endsWith('ss') && word.length > 1) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

String _mergeKeyName(String name) {
  return name
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .map(_singularize)
      .join(' ');
}

String _normalizeSizeKey(String size) {
  final lower = size.toLowerCase().trim();
  if (lower.isEmpty || lower == 'n/a' || lower == '1 each' || lower == 'none') {
    return '';
  }
  return lower
      .replaceAll('ounce', 'oz')
      .replaceAll('pound', 'lb')
      .replaceAll(RegExp(r'\s+'), ' ');
}

List<ProductGroup> mergeSimilarProductGroups(
  List<ProductGroup> groups, {
  Set<(int, int)> confirmedPairs = const {},
  Set<(int, int)> deniedPairs = const {},
}) {
  final mergeMap = <String, List<ProductGroup>>{};
  for (final group in groups) {
    final product = group.primaryProduct;
    final nameKey = _mergeKeyName(product.name);
    final sizeKey = _normalizeSizeKey(product.size);
    final key = '$nameKey\x00$sizeKey';
    mergeMap.putIfAbsent(key, () => <ProductGroup>[]).add(group);
  }

  // Build a map from product id to its group for force-merge lookups.
  final idToGroup = <int, String>{};
  for (final entry in mergeMap.entries) {
    for (final group in entry.value) {
      for (final option in group.options) {
        idToGroup[option.id] = entry.key;
      }
    }
  }

  // Force-merge confirmed pairs into the same merge key.
  for (final (a, b) in confirmedPairs) {
    final keyA = idToGroup[a];
    final keyB = idToGroup[b];
    if (keyA != null && keyB != null && keyA != keyB) {
      // Move all groups from keyB into keyA.
      final groupsB = mergeMap.remove(keyB);
      if (groupsB != null) {
        mergeMap[keyA]!.addAll(groupsB);
        for (final g in groupsB) {
          for (final o in g.options) {
            idToGroup[o.id] = keyA;
          }
        }
      }
    }
  }

  final result = <ProductGroup>[];
  for (final entry in mergeMap.values) {
    if (entry.length == 1) {
      result.add(entry.first);
      continue;
    }

    // Check if any product pair in this merge group was denied.
    final allProductIds = <int>{};
    for (final group in entry) {
      for (final option in group.options) {
        allProductIds.add(option.id);
      }
    }

    // Split denied product ids into separate groups.
    final orderedProductIds = allProductIds.toList(growable: false);
    final deniedIds = <int>{};
    for (var i = 0; i < orderedProductIds.length; i++) {
      for (var j = i + 1; j < orderedProductIds.length; j++) {
        final pair = (orderedProductIds[i], orderedProductIds[j]);
        final reversePair = (orderedProductIds[j], orderedProductIds[i]);
        if (deniedPairs.contains(pair) || deniedPairs.contains(reversePair)) {
          deniedIds.add(orderedProductIds[j]);
        }
      }
    }

    if (deniedIds.isEmpty) {
      // No denials — merge everything as before.
      final byStore = <int, Product>{};
      for (final group in entry) {
        for (final option in group.options) {
          final existing = byStore[option.storeId];
          if (existing == null ||
              compareProductsByPrice(option, existing) < 0) {
            byStore[option.storeId] = option;
          }
        }
      }
      final merged = byStore.values.toList()..sort(compareProductsByPrice);
      result.add(ProductGroup(options: merged));
    } else {
      // Split: merge non-denied products, keep denied ones separate.
      final mainByStore = <int, Product>{};
      final deniedGroups = <int, Map<int, Product>>{};
      for (final group in entry) {
        for (final option in group.options) {
          if (deniedIds.contains(option.id)) {
            deniedGroups
                .putIfAbsent(option.id, () => <int, Product>{})
                [option.storeId] = option;
          } else {
            final existing = mainByStore[option.storeId];
            if (existing == null ||
                compareProductsByPrice(option, existing) < 0) {
              mainByStore[option.storeId] = option;
            }
          }
        }
      }
      if (mainByStore.isNotEmpty) {
        final merged = mainByStore.values.toList()..sort(compareProductsByPrice);
        result.add(ProductGroup(options: merged));
      }
      for (final byStore in deniedGroups.values) {
        final options = byStore.values.toList()..sort(compareProductsByPrice);
        result.add(ProductGroup(options: options));
      }
    }
  }
  return result;
}

/// Groups [products] by product identity, deduplicating per store and merging
/// similarly-named products. Returns one [ProductGroup] per unique product,
/// with all its per-store options sorted cheapest-first.
///
/// [confirmedPairs] and [deniedPairs] come from grouping judgements and
/// force-merge or force-separate product IDs respectively.
List<ProductGroup> groupProductsById(
  List<Product> products, {
  Set<(int, int)> confirmedPairs = const {},
  Set<(int, int)> deniedPairs = const {},
}) {
  final groupedByProductId = <int, Map<int, Product>>{};
  for (final product in products) {
    final byStore =
        groupedByProductId.putIfAbsent(product.id, () => <int, Product>{});
    final existing = byStore[product.storeId];
    if (existing == null || compareProductsByPrice(product, existing) < 0) {
      byStore[product.storeId] = product;
    }
  }
  final idGroups = groupedByProductId.values
      .map((byStore) {
        final options = byStore.values.toList()..sort(compareProductsByPrice);
        return ProductGroup(options: options);
      })
      .toList(growable: false);
  return mergeSimilarProductGroups(
    idGroups,
    confirmedPairs: confirmedPairs,
    deniedPairs: deniedPairs,
  );
}

class ProductGroup {
  ProductGroup({required List<Product> options})
      : options = List<Product>.unmodifiable(options);

  final List<Product> options;

  Product get primaryProduct => options.first;

  int get storeCount => options.length;

  int get otherStoreCount => storeCount > 0 ? storeCount - 1 : 0;

  double? get minPrice => productEffectivePrice(primaryProduct);

  double? get maxPrice {
    double? currentMax;
    for (final option in options) {
      final optionPrice = productEffectivePrice(option);
      if (optionPrice == null) {
        continue;
      }
      if (currentMax == null || optionPrice > currentMax) {
        currentMax = optionPrice;
      }
    }
    return currentMax;
  }

  double? get priceSpread {
    final lowestPrice = minPrice;
    final highestPrice = maxPrice;
    if (lowestPrice == null || highestPrice == null) {
      return null;
    }
    final spread = highestPrice - lowestPrice;
    return spread >= productPriceEpsilon ? spread : null;
  }

  bool get hasPriceSpread => priceSpread != null;

  double? get lowestAlternatePrice {
    for (final option in options.skip(1)) {
      final optionPrice = productEffectivePrice(option);
      if (optionPrice != null) {
        return optionPrice;
      }
    }
    return null;
  }

  int get equalPriceStoreCount {
    final lowestPrice = minPrice;
    if (lowestPrice == null) {
      return 0;
    }
    var count = 0;
    for (final option in options.skip(1)) {
      final optionPrice = productEffectivePrice(option);
      if (optionPrice != null && productPricesMatch(optionPrice, lowestPrice)) {
        count++;
      }
    }
    return count;
  }

  int get higherPricedStoreCount {
    final lowestPrice = minPrice;
    if (lowestPrice == null) {
      return 0;
    }
    var count = 0;
    for (final option in options.skip(1)) {
      final optionPrice = productEffectivePrice(option);
      if (optionPrice != null && !productPricesMatch(optionPrice, lowestPrice)) {
        count++;
      }
    }
    return count;
  }
}

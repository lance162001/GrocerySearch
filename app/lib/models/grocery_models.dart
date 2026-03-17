import 'package:flutter_front_end/utils/price_utils.dart';

class Tag {
  const Tag({required this.id, required this.name});

  final int id;
  final String name;

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Tag && other.id == id;
  }

  @override
  int get hashCode => id;
}

class Company {
  const Company({required this.id, required this.name, required this.logoUrl});

  final int id;
  final String name;
  final String logoUrl;

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      logoUrl: json['logo_url']?.toString() ?? '',
    );
  }
}

class PricePoint {
  const PricePoint({
    required this.memberPrice,
    required this.salePrice,
    required this.basePrice,
    required this.size,
    required this.timestamp,
  });

  final String memberPrice;
  final String salePrice;
  final String basePrice;
  final String size;
  final DateTime timestamp;

  double lowestPrice() {
    return parsePriceString(memberPrice) ??
        parsePriceString(salePrice) ??
        parsePriceString(basePrice) ??
        0.0;
  }

  Map<String, Object> toObject() {
    return {
      'timestamp': '${timestamp.year}/${timestamp.month}/${timestamp.day}',
      'lowestPrice': lowestPrice(),
    };
  }

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(
      salePrice: json['sale_price']?.toString() ?? '',
      basePrice: json['base_price']?.toString() ?? '0',
      size: json['size']?.toString() ?? '',
      memberPrice: json['member_price']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class Product {
  Product({
    required this.id,
    required this.instanceId,
    required this.lastUpdated,
    required this.brand,
    required this.memberPrice,
    required this.salePrice,
    required this.basePrice,
    required this.size,
    required this.pictureUrl,
    required this.name,
    required this.priceHistory,
    required this.companyId,
    required this.storeId,
    this.variationGroup,
    this.inCart = false,
  });

  final int id;
  final int instanceId;
  final DateTime lastUpdated;
  final String brand;
  final String memberPrice;
  final String salePrice;
  final String basePrice;
  final String size;
  final String pictureUrl;
  final String name;
  final List<PricePoint> priceHistory;
  final int companyId;
  final int storeId;
  final String? variationGroup;
  final bool inCart;

  PricePoint toPricePoint() {
    return PricePoint(
      memberPrice: memberPrice,
      salePrice: salePrice,
      basePrice: basePrice,
      size: size,
      timestamp: lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Product && other.instanceId == instanceId;
  }

  @override
  int get hashCode => instanceId;

  factory Product.fromJson(Map<String, dynamic> json) {
    final productJson = Map<String, dynamic>.from(json['Product'] as Map<dynamic, dynamic>);
    final instanceJson = Map<String, dynamic>.from(json['Product_Instance'] as Map<dynamic, dynamic>);
    final rawInstanceId = instanceJson['id'];
    final safeInstanceId = rawInstanceId is int
        ? rawInstanceId
        : Object.hash(productJson['id'], instanceJson['store_id']) & 0x3fffffff;

    final priceHistory = (instanceJson['price_points'] as List<dynamic>? ?? const [])
        .map((pricePoint) => PricePoint.fromJson(Map<String, dynamic>.from(pricePoint as Map<dynamic, dynamic>)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    var latest = priceHistory.isNotEmpty
        ? priceHistory.first
        : PricePoint(
            memberPrice: '',
            salePrice: '',
            basePrice: '0',
            size: '',
            timestamp: DateTime.now(),
          );
    for (final pricePoint in priceHistory) {
      final isNewer = pricePoint.timestamp.isAfter(latest.timestamp);
      final isSameTimeButBetter =
          pricePoint.timestamp.isAtSameMomentAs(latest.timestamp) &&
              pricePoint.lowestPrice() < latest.lowestPrice();
      if (isNewer || isSameTimeButBetter) {
        latest = pricePoint;
      }
    }

    return Product(
      id: productJson['id'] as int,
      instanceId: safeInstanceId,
      lastUpdated: latest.timestamp,
      brand: productJson['brand']?.toString() ?? '',
      memberPrice: latest.memberPrice,
      salePrice: latest.salePrice,
      basePrice: latest.basePrice,
      size: latest.size,
      pictureUrl: productJson['picture_url']?.toString() ?? '',
      name: productJson['name']?.toString() ?? '',
      priceHistory: priceHistory,
      companyId: productJson['company_id'] as int,
      storeId: instanceJson['store_id'] as int,
      variationGroup: productJson['variation_group']?.toString(),
    );
  }
}

class Store {
  const Store({
    required this.id,
    required this.companyId,
    required this.scraperId,
    required this.town,
    required this.state,
    required this.address,
    required this.zipcode,
  });

  final int id;
  final int companyId;
  final int scraperId;
  final String address;
  final String town;
  final String state;
  final String zipcode;

  @override
  bool operator ==(Object other) {
    return other is Store && other.id == id;
  }

  @override
  int get hashCode => id;

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'] as int,
      companyId: json['company_id'] as int,
      scraperId: json['scraper_id'] as int,
      town: json['town']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      zipcode: json['zipcode']?.toString() ?? '',
    );
  }
}

/// A product (and optional target) presented for user judgement.
class JudgementCandidate {
  const JudgementCandidate({
    required this.productId,
    required this.productName,
    required this.productBrand,
    required this.productPictureUrl,
    this.stapleName,
    this.targetProductId,
    this.targetProductName,
    this.targetProductBrand,
    this.targetProductPictureUrl,
    this.heuristicScore,
  });

  final int productId;
  final String productName;
  final String productBrand;
  final String productPictureUrl;
  final String? stapleName;
  final int? targetProductId;
  final String? targetProductName;
  final String? targetProductBrand;
  final String? targetProductPictureUrl;
  final double? heuristicScore;

  factory JudgementCandidate.fromJson(Map<String, dynamic> json) {
    final product = Map<String, dynamic>.from(json['product'] as Map);
    final target = json['target_product'] != null
        ? Map<String, dynamic>.from(json['target_product'] as Map)
        : null;
    return JudgementCandidate(
      productId: product['id'] as int,
      productName: product['name']?.toString() ?? '',
      productBrand: product['brand']?.toString() ?? '',
      productPictureUrl: product['picture_url']?.toString() ?? '',
      stapleName: json['staple_name']?.toString(),
      targetProductId: target?['id'] as int?,
      targetProductName: target?['name']?.toString(),
      targetProductBrand: target?['brand']?.toString(),
      targetProductPictureUrl: target?['picture_url']?.toString(),
      heuristicScore: (json['heuristic_score'] as num?)?.toDouble(),
    );
  }
}

/// Aggregated staple judgement for a product.
class StapleJudgementSummary {
  const StapleJudgementSummary({
    required this.productId,
    required this.stapleName,
    required this.approvals,
    required this.denials,
  });

  final int productId;
  final String stapleName;
  final int approvals;
  final int denials;

  /// Net score: positive = likely staple, negative = likely not.
  int get netScore => approvals - denials;

  factory StapleJudgementSummary.fromJson(Map<String, dynamic> json) {
    return StapleJudgementSummary(
      productId: json['product_id'] as int,
      stapleName: json['staple_name']?.toString() ?? '',
      approvals: json['approvals'] as int,
      denials: json['denials'] as int,
    );
  }
}

/// Aggregated grouping judgement for a product pair.
class GroupingJudgementSummary {
  const GroupingJudgementSummary({
    required this.productId,
    required this.targetProductId,
    required this.approvals,
    required this.denials,
  });

  final int productId;
  final int targetProductId;
  final int approvals;
  final int denials;

  int get netScore => approvals - denials;

  factory GroupingJudgementSummary.fromJson(Map<String, dynamic> json) {
    return GroupingJudgementSummary(
      productId: json['product_id'] as int,
      targetProductId: json['target_product_id'] as int,
      approvals: json['approvals'] as int,
      denials: json['denials'] as int,
    );
  }
}

/// Heuristic staple score inferred from existing user labels.
class StapleHeuristic {
  const StapleHeuristic({
    required this.productId,
    required this.stapleName,
    required this.score,
  });

  final int productId;
  final String stapleName;

  /// 0 = likely not a staple, 1 = likely a staple.
  final double score;

  factory StapleHeuristic.fromJson(Map<String, dynamic> json) {
    return StapleHeuristic(
      productId: json['product_id'] as int,
      stapleName: json['staple_name'] as String,
      score: (json['score'] as num).toDouble(),
    );
  }
}
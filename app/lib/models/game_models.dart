// Game models for the Grocery Wordle feature.

enum AttributeMatch { exact, close, none }

enum PriceDirection { higher, lower }

class GameProduct {
  const GameProduct({
    required this.id,
    required this.name,
    required this.brand,
    required this.companyName,
    required this.pictureUrl,
  });

  final int id;
  final String name;
  final String brand;
  final String companyName;
  final String pictureUrl;

  @override
  bool operator ==(Object other) => other is GameProduct && other.id == id;

  @override
  int get hashCode => id;

  factory GameProduct.fromJson(Map<String, dynamic> json) => GameProduct(
        id: json['id'] as int,
        name: json['name']?.toString() ?? '',
        brand: json['brand']?.toString() ?? '',
        companyName: json['company_name']?.toString() ?? '',
        pictureUrl: json['picture_url']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'company_name': companyName,
        'picture_url': pictureUrl,
      };
}

class AttributeResult {
  const AttributeResult({
    required this.key,
    required this.label,
    required this.value,
    required this.match,
    this.direction,
  });

  final String key;
  final String label;
  final String value;
  final AttributeMatch match;
  final PriceDirection? direction;

  factory AttributeResult.fromJson(Map<String, dynamic> json) {
    final matchStr = json['match']?.toString() ?? 'none';
    final match = matchStr == 'exact'
        ? AttributeMatch.exact
        : matchStr == 'close'
            ? AttributeMatch.close
            : AttributeMatch.none;

    final dirStr = json['direction']?.toString();
    final direction = dirStr == 'higher'
        ? PriceDirection.higher
        : dirStr == 'lower'
            ? PriceDirection.lower
            : null;

    return AttributeResult(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      match: match,
      direction: direction,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'value': value,
        'match': match.name,
        'direction': direction?.name,
      };
}

class GuessResult {
  const GuessResult({
    required this.guess,
    required this.attributes,
    required this.isCorrect,
  });

  final GameProduct guess;
  final List<AttributeResult> attributes;
  final bool isCorrect;

  factory GuessResult.fromJson(Map<String, dynamic> json) => GuessResult(
        guess: GameProduct.fromJson(
            Map<String, dynamic>.from(json['guess'] as Map)),
        attributes: (json['attributes'] as List<dynamic>)
            .map((e) => AttributeResult.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        isCorrect: json['is_correct'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'guess': guess.toJson(),
        'attributes': attributes.map((a) => a.toJson()).toList(),
        'is_correct': isCorrect,
      };
}

class GameHint {
  const GameHint({required this.key, required this.label, required this.value});

  final String key;
  final String label;
  final String value;

  factory GameHint.fromJson(Map<String, dynamic> json) => GameHint(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        value: json['value']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'value': value};
}

class RevealResult {
  const RevealResult({
    required this.product,
    required this.price,
    this.stapleName,
    this.category,
    this.sizeUnit,
  });

  final GameProduct product;
  final String price;
  final String? stapleName;
  final String? category;
  final String? sizeUnit;

  factory RevealResult.fromJson(Map<String, dynamic> json) => RevealResult(
        product: GameProduct.fromJson(
            Map<String, dynamic>.from(json['product'] as Map)),
        price: json['price']?.toString() ?? '',
        stapleName: json['staple_name']?.toString(),
        category: json['category']?.toString(),
        sizeUnit: json['size_unit']?.toString(),
      );
}

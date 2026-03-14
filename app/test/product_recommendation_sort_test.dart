import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/utils/product_recommendation_sort.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  required int id,
  required String name,
  String brand = 'Store Brand',
  String basePrice = '1.00',
}) {
  return Product(
    id: id,
    instanceId: id * 100,
    lastUpdated: DateTime(2026, 3, 14),
    brand: brand,
    memberPrice: '',
    salePrice: '',
    basePrice: basePrice,
    size: '64 oz',
    pictureUrl: '/static/$id.png',
    name: name,
    priceHistory: [
      PricePoint(
        memberPrice: '',
        salePrice: '',
        basePrice: basePrice,
        size: '64 oz',
        timestamp: DateTime(2026, 3, 14),
      ),
    ],
    companyId: 1,
    storeId: 1,
  );
}

List<String> _sortedNames(String searchTerm, List<String> names) {
  final products = <Product>[
    for (var index = 0; index < names.length; index++)
      _product(id: index + 1, name: names[index]),
  ];

  return sortProductsByRecommendation(
    products,
    searchTerm,
  ).map((product) => product.name).toList();
}

void main() {
  group('sortProductsByRecommendation', () {
    test('prioritizes staple milk variants for generic milk searches', () {
      final sorted = _sortedNames('milk', <String>[
        'Chocolate Milk',
        'Oat Milk',
        '1% Low Fat Milk',
        'Whole Milk',
        'Organic Whole Milk',
        '2% Reduced Fat Milk',
        'Skim Milk',
      ]);

      expect(
        sorted,
        <String>[
          'Whole Milk',
          '2% Reduced Fat Milk',
          '1% Low Fat Milk',
          'Skim Milk',
          'Organic Whole Milk',
          'Chocolate Milk',
          'Oat Milk',
        ],
      );
    });

    test('prioritizes shell eggs before specialty egg products', () {
      expect(
        _sortedNames('egg', <String>[
          'Egg Bites',
          'Liquid Egg Whites',
          'Cage Free Large Eggs',
          'Large Eggs',
          'Extra Large Eggs',
        ]),
        <String>[
          'Large Eggs',
          'Extra Large Eggs',
          'Cage Free Large Eggs',
          'Liquid Egg Whites',
          'Egg Bites',
        ],
      );
    });

    test('prioritizes standard loaves before specialty breads', () {
      expect(
        _sortedNames('bread', <String>[
          'Bread Crumbs',
          'Garlic Bread',
          'Whole Wheat Bread',
          'Sourdough Bread',
          'White Bread',
          'Gluten Free Bread',
        ]),
        <String>[
          'White Bread',
          'Whole Wheat Bread',
          'Sourdough Bread',
          'Garlic Bread',
          'Gluten Free Bread',
          'Bread Crumbs',
        ],
      );
    });

    test('prioritizes basic rice before prepared or alternative rice', () {
      expect(
        _sortedNames('rice', <String>[
          'Cauliflower Rice',
          'Seasoned Rice',
          'Jasmine Rice',
          'Long Grain White Rice',
          'Brown Rice',
          'Ready Rice Bowl',
        ]),
        <String>[
          'Long Grain White Rice',
          'Jasmine Rice',
          'Brown Rice',
          'Seasoned Rice',
          'Cauliflower Rice',
          'Ready Rice Bowl',
        ],
      );
    });

    test('prioritizes regular pasta shapes before specialty pasta items', () {
      expect(
        _sortedNames('pasta', <String>[
          'Chickpea Pasta',
          'Mac and Cheese Pasta',
          'Spinach Pasta',
          'Penne Pasta',
          'Macaroni Pasta',
          'Spaghetti Pasta',
        ]),
        <String>[
          'Spaghetti Pasta',
          'Penne Pasta',
          'Macaroni Pasta',
          'Spinach Pasta',
          'Chickpea Pasta',
          'Mac and Cheese Pasta',
        ],
      );
    });

    test('prioritizes all purpose flour before specialty flours', () {
      expect(
        _sortedNames('flour', <String>[
          'Almond Flour',
          'Organic Unbleached Flour',
          'Bread Flour',
          'Whole Wheat Flour',
          'All Purpose Flour',
        ]),
        <String>[
          'All Purpose Flour',
          'Bread Flour',
          'Whole Wheat Flour',
          'Organic Unbleached Flour',
          'Almond Flour',
        ],
      );
    });

    test('prioritizes cane sugar before specialty sweeteners', () {
      expect(
        _sortedNames('sugar', <String>[
          'Powdered Sugar',
          'Monk Fruit Sugar Alternative',
          'Dark Brown Sugar',
          'Light Brown Sugar',
          'Granulated Sugar',
        ]),
        <String>[
          'Granulated Sugar',
          'Light Brown Sugar',
          'Dark Brown Sugar',
          'Powdered Sugar',
          'Monk Fruit Sugar Alternative',
        ],
      );
    });

    test('prioritizes basic butter before flavored and alternative butters',
        () {
      expect(
        _sortedNames('butter', <String>[
          'Plant Butter',
          'Garlic Butter',
          'Organic Butter',
          'Unsalted Butter',
          'Salted Butter',
        ]),
        <String>[
          'Salted Butter',
          'Unsalted Butter',
          'Organic Butter',
          'Garlic Butter',
          'Plant Butter',
        ],
      );
    });

    test('prioritizes classic cheeses before specialty cheese products', () {
      expect(
        _sortedNames('cheese', <String>[
          'Cheese Dip',
          'Vegan Cheese',
          'Pepper Jack Cheese',
          'Swiss Cheese',
          'Mozzarella Cheese',
          'Cheddar Cheese',
        ]),
        <String>[
          'Cheddar Cheese',
          'Mozzarella Cheese',
          'Swiss Cheese',
          'Pepper Jack Cheese',
          'Vegan Cheese',
          'Cheese Dip',
        ],
      );
    });

    test('prioritizes plain yogurt before flavored or dairy-free yogurt', () {
      expect(
        _sortedNames('yogurt', <String>[
          'Coconut Yogurt',
          'Strawberry Yogurt',
          'Greek Yogurt',
          'Vanilla Yogurt',
          'Plain Yogurt',
        ]),
        <String>[
          'Plain Yogurt',
          'Vanilla Yogurt',
          'Greek Yogurt',
          'Strawberry Yogurt',
          'Coconut Yogurt',
        ],
      );
    });

    test('keeps specific multiword searches ahead of generic milk defaults',
        () {
      final sorted = _sortedNames('oat milk', <String>[
        'Whole Milk',
        'Organic Oat Milk',
        'Oat Milk',
        'Chocolate Milk',
      ]);

      expect(
        sorted.take(2),
        <String>['Oat Milk', 'Organic Oat Milk'],
      );
    });
  });
}

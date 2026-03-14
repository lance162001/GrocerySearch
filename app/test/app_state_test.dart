import 'package:flutter_front_end/config/app_environment.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGroceryApi extends GroceryApi {
  FakeGroceryApi()
      : super(
          environment: AppEnvironment.local,
        );

  @override
  Future<int> fetchOrCreateUserId() async => 42;

  @override
  Future<List<Tag>> fetchTags() async => const [
        Tag(id: 1, name: 'Frozen'),
        Tag(id: 2, name: 'Produce'),
      ];

  @override
  Future<List<Company>> fetchCompanies() async => const [
        Company(id: 1, name: 'Trader Joes', logoUrl: '/logos/tj.png'),
      ];

  @override
  Future<Set<int>> fetchSavedStoreIdsForUser(int userId) async => {7};

  @override
  Future<List<Store>> fetchAllStores() async => const [
        Store(
          id: 7,
          companyId: 1,
          scraperId: 7,
          town: 'Austin',
          state: 'TX',
          address: '123 Market St',
          zipcode: '78701',
        ),
        Store(
          id: 8,
          companyId: 1,
          scraperId: 8,
          town: 'Dallas',
          state: 'TX',
          address: '456 Store Ave',
          zipcode: '75201',
        ),
      ];
}

void main() {
  group('AppState', () {
    test('initialize loads bootstrap data and saved stores', () async {
      final state = AppState(api: FakeGroceryApi());

      await state.initialize();

      expect(state.currentUserId, 42);
      expect(state.bootstrappingUser, isFalse);
      expect(state.tags.map((tag) => tag.name), ['Frozen', 'Produce']);
      expect(state.companies.single.name, 'Trader Joes');
      expect(state.userStores.single.id, 7);
    });

    test('cart and filter actions mutate state predictably', () {
      final state = AppState(api: FakeGroceryApi())
        ..userStores = const [
          Store(
            id: 7,
            companyId: 1,
            scraperId: 7,
            town: 'Austin',
            state: 'TX',
            address: '123 Market St',
            zipcode: '78701',
          ),
        ]
        ..tags = const [
          Tag(id: 1, name: 'Frozen'),
        ];

      final product = Product(
        id: 11,
        instanceId: 111,
        lastUpdated: DateTime(2026, 3, 13),
        brand: 'Store Brand',
        memberPrice: '2.00',
        salePrice: '',
        basePrice: '2.50',
        size: '16 oz',
        pictureUrl: '/static/item.png',
        name: 'Soup',
        priceHistory: [
          PricePoint(
            memberPrice: '2.00',
            salePrice: '',
            basePrice: '2.50',
            size: '16 oz',
            timestamp: DateTime(2026, 3, 13),
          ),
        ],
        companyId: 1,
        storeId: 7,
      );

      state.toggleTag(const Tag(id: 1, name: 'Frozen'));
      state.addToCartQty(product, 2);
      state.moveCartItemToFinished(product);
      state.restoreFinishedItem(product);

      expect(state.userTags.single.id, 1);
      expect(state.cartTotalItems, 2);
      expect(state.cart.single.instanceId, 111);
      expect(state.cartFinished, isEmpty);

      state.removeFromCartAll(product);

      expect(state.cart, isEmpty);
      expect(state.cartQuantities, isEmpty);
    });
  });
}
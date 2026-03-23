import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, kDebugMode;
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/utils/hints_pref_cache.dart';

class AppState extends ChangeNotifier {
  AppState({required this.api});

  final GroceryApi api;

  bool bootstrappingUser = true;
  String? userBootstrapError;
  int? currentUserId;
  List<Tag> tags = [];
  List<Company> companies = [];
  List<Store> userStores = [];
  List<Product> cart = [];
  List<Product> cartFinished = [];
  final Map<int, int> cartQuantities = <int, int>{};
  List<Tag> userTags = [];
  String searchTerm = '';
  bool hideHints = false;
  bool _initialized = false;

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) {
      return;
    }
    _initialized = true;
    bootstrappingUser = true;
    userBootstrapError = null;
    notifyListeners();

    // Load local-only preferences before the network bootstrap completes so
    // they are ready as early as possible.
    readHideHints().then((value) {
      hideHints = value;
      notifyListeners();
    }).catchError((_) {});

    try {
      final metadataFuture = Future.wait<dynamic>([
        api.fetchTags().catchError((_) => <Tag>[]),
        api.fetchCompanies().catchError((_) => <Company>[]),
      ]);
      final userId = await api.fetchOrCreateUserId();
      currentUserId = userId;

      final metadata = await metadataFuture;
      tags = List<Tag>.from(metadata[0] as List<Tag>);
      companies = List<Company>.from(metadata[1] as List<Company>);

      await loadSavedStoresForCurrentUser();
    } catch (error) {
      currentUserId = null;
      userBootstrapError = '$error';
    } finally {
      bootstrappingUser = false;
      notifyListeners();
    }
  }

  Future<void> loadSavedStoresForCurrentUser() async {
    final userId = currentUserId;
    if (userId == null) {
      userStores = [];
      notifyListeners();
      return;
    }

    try {
      final savedStoreIds = await api.fetchSavedStoreIdsForUser(userId);
      if (savedStoreIds.isEmpty) {
        userStores = [];
      } else {
        final allStores = await api.fetchAllStores();
        userStores = allStores.where((store) => savedStoreIds.contains(store.id)).toList();
      }
      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not load saved stores for user $userId: $error');
      }
    }
  }

  Future<void> persistSelectedStores() async {
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('Current user unavailable');
    }
    for (final store in userStores) {
      await api.saveStoreForUser(userId, store.id);
    }
  }

  void toggleStore(Store store) {
    if (userStores.contains(store)) {
      userStores = userStores.where((selectedStore) => selectedStore.id != store.id).toList();
    } else {
      userStores = [...userStores, store];
    }
    notifyListeners();
  }

  Future<void> setHideHints(bool value) async {
    hideHints = value;
    notifyListeners();
    await writeHideHints(value);
  }

  void clearSelectedStores() {
    if (userStores.isEmpty) {
      return;
    }
    userStores = [];
    notifyListeners();
  }

  void toggleTag(Tag tag) {
    if (userTags.contains(tag)) {
      userTags = userTags.where((selectedTag) => selectedTag.id != tag.id).toList();
    } else {
      userTags = [...userTags, tag];
    }
    notifyListeners();
  }

  void setSearchTerm(String term) {
    if (searchTerm == term) {
      return;
    }
    searchTerm = term;
    notifyListeners();
  }

  int quantityFor(Product product) => cartQuantities[product.instanceId] ?? 0;

  int get cartTotalItems => cartQuantities.values.fold(0, (sum, qty) => sum + qty);

  void addToCartQty(Product product, int qty) {
    if (qty <= 0) {
      return;
    }
    cartQuantities[product.instanceId] = quantityFor(product) + qty;
    if (!cart.any((item) => item.instanceId == product.instanceId)) {
      cart.add(product);
    }
    cartFinished.removeWhere((item) => item.instanceId == product.instanceId);
    notifyListeners();
  }

  void removeFromCartAll(Product product) {
    cartQuantities.remove(product.instanceId);
    cart.removeWhere((item) => item.instanceId == product.instanceId);
    notifyListeners();
  }

  void moveCartItemToFinished(Product product) {
    cart.removeWhere((item) => item.instanceId == product.instanceId);
    if (!cartFinished.any((item) => item.instanceId == product.instanceId)) {
      cartFinished.add(product);
    }
    notifyListeners();
  }

  void restoreFinishedItem(Product product) {
    if (!cart.any((item) => item.instanceId == product.instanceId)) {
      cart.add(product);
    }
    cartFinished.removeWhere((item) => item.instanceId == product.instanceId);
    notifyListeners();
  }
}
// app/lib/state/markup_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/models/grocery_models.dart';

class MarkupState extends ChangeNotifier {
  final GroceryApi api;

  // Auth
  int? currentUserId;
  bool isSignedIn = false;

  // Location
  String? zipcode;
  bool locationSet = false;

  // Tags & companies (metadata)
  List<Tag> tags = [];
  List<Company> companies = [];

  // Feed
  List<dynamic> feedItems = [];
  int feedPage = 1;
  bool feedHasMore = true;
  bool feedLoading = false;

  // Search
  String searchTerm = '';
  List<int> activeTagIds = [];
  bool onSaleOnly = false;
  bool biggestSpreadsOnly = false;
  String sortBy = 'best_savings';

  // Tracking (local for anonymous)
  List<int> localTrackedProductIds = [];

  // Points
  int points = 0;

  MarkupState({required this.api});

  Future<void> initialize() async {
    tags = await api.fetchTags();
    companies = await api.fetchCompanies();
    notifyListeners();
  }

  void setZipcode(String? zip) {
    zipcode = zip;
    locationSet = zip != null && zip.isNotEmpty;
    notifyListeners();
  }

  void setUserId(int id) {
    currentUserId = id;
    isSignedIn = true;
    notifyListeners();
  }

  void toggleTag(int tagId) {
    if (activeTagIds.contains(tagId)) {
      activeTagIds.remove(tagId);
    } else {
      activeTagIds.add(tagId);
    }
    notifyListeners();
  }

  void setSearchTerm(String term) {
    searchTerm = term;
    notifyListeners();
  }

  void setSortBy(String sort) {
    sortBy = sort;
    notifyListeners();
  }

  void toggleOnSale() {
    onSaleOnly = !onSaleOnly;
    notifyListeners();
  }

  void toggleBiggestSpreads() {
    biggestSpreadsOnly = !biggestSpreadsOnly;
    notifyListeners();
  }

  void trackProductLocally(int productId) {
    if (!localTrackedProductIds.contains(productId)) {
      localTrackedProductIds.add(productId);
      notifyListeners();
    }
  }

  void untrackProductLocally(int productId) {
    localTrackedProductIds.remove(productId);
    notifyListeners();
  }

  void addPoints(int pts) {
    points += pts;
    notifyListeners();
  }
}

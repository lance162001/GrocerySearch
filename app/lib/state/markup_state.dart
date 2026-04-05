// app/lib/state/markup_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/models/grocery_models.dart';

class MarkupState extends ChangeNotifier {
  final GroceryApi api;

  // Auth
  int? currentUserId;

  // Location
  String? zipcode;

  // Tags & companies (metadata)
  List<Tag> tags = [];
  List<Company> companies = [];

  // Feed
  List<FeedItem> feedItems = [];
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

  bool initializing = false;
  String? initError;

  MarkupState({required this.api});

  bool get isSignedIn => currentUserId != null;
  bool get locationSet => zipcode != null && zipcode!.isNotEmpty;

  Future<void> initialize() async {
    initializing = true;
    initError = null;
    notifyListeners();
    try {
      tags = await api.fetchTags();
      companies = await api.fetchCompanies();
    } catch (e) {
      initError = '$e';
    } finally {
      initializing = false;
      notifyListeners();
    }
  }

  Future<void> loadFeed({bool refresh = false}) async {
    if (feedLoading) return;
    if (refresh) {
      feedItems = [];
      feedPage = 1;
      feedHasMore = true;
    }
    if (!feedHasMore) return;
    feedLoading = true;
    notifyListeners();
    try {
      final resp = await api.fetchFeed(page: feedPage, zipcode: zipcode);
      final newItems = (resp['items'] as List? ?? [])
          .map<FeedItem>((j) => FeedItem.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
      feedItems = refresh ? newItems : [...feedItems, ...newItems];
      feedPage += 1;
      feedHasMore = newItems.isNotEmpty;
    } catch (e) {
      // swallow — feed screen will show stale content
    } finally {
      feedLoading = false;
      notifyListeners();
    }
  }

  void setZipcode(String? zip) {
    zipcode = zip;
    notifyListeners();
  }

  void setUserId(int id) {
    currentUserId = id;
    notifyListeners();
  }

  void clearUserId() {
    currentUserId = null;
    notifyListeners();
  }

  void toggleTag(int tagId) {
    if (activeTagIds.contains(tagId)) {
      activeTagIds = activeTagIds.where((id) => id != tagId).toList();
    } else {
      activeTagIds = [...activeTagIds, tagId];
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

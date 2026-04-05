import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/widgets/search_result_card.dart';
import 'package:flutter_front_end/widgets/filter_chips_bar.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<Product> _results = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String _lastQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search({bool reset = false}) async {
    final state = context.read<MarkupState>();
    final query = _searchController.text.trim();

    if (reset) {
      setState(() {
        _results = [];
        _page = 1;
        _hasMore = true;
        _lastQuery = query;
      });
    }

    if (_loading) return;
    if (!_hasMore && !reset) return;

    setState(() => _loading = true);

    try {
      final items = await state.api.searchProducts(
        search: query,
        tagIds: state.activeTagIds,
        onSaleOnly: state.onSaleOnly,
        hasSpread: state.biggestSpreadsOnly,
        page: reset ? 1 : _page,
        size: 20,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _results = items;
          _page = 2;
        } else {
          _results.addAll(items);
          _page += 1;
        }
        _hasMore = items.length == 20;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MarkupState>();
    return SafeArea(
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(reset: true),
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search, color: MarkupColors.textHint),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: MarkupColors.textHint),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _lastQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          // Filter chips
          FilterChipsBar(
            onSaleActive: state.onSaleOnly,
            biggestSpreadsActive: state.biggestSpreadsOnly,
            tagNames: state.tags.map((t) => t.name).toList(),
            activeTagIds: state.activeTagIds,
            onToggleOnSale: () {
              state.toggleOnSale();
              _search(reset: true);
            },
            onToggleSpreads: () {
              state.toggleBiggestSpreads();
              _search(reset: true);
            },
            onToggleTag: (i) {
              state.toggleTag(state.tags[i].id);
              _search(reset: true);
            },
          ),
          const SizedBox(height: 8),
          // Results header
          if (_results.isNotEmpty || _lastQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    _results.isEmpty ? 'No results' : '${_results.length}+ results',
                    style: const TextStyle(fontSize: 13, color: MarkupColors.textSecondary),
                  ),
                  const Spacer(),
                  _sortDropdown(state),
                ],
              ),
            ),
          // Results list
          Expanded(
            child: _results.isEmpty && !_loading
                ? _lastQuery.isEmpty
                    ? const Center(
                        child: Text(
                          'Search for a product to compare prices',
                          style: TextStyle(color: MarkupColors.textSecondary, fontSize: 14),
                        ),
                      )
                    : const Center(
                        child: Text(
                          'No results found',
                          style: TextStyle(color: MarkupColors.textSecondary, fontSize: 14),
                        ),
                      )
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollEndNotification && n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                        _search();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      itemCount: _results.length + (_loading ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= _results.length) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator(color: MarkupColors.darkGreen)),
                          );
                        }
                        return _buildResultCard(_results[i], i);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Product product, int index) {
    final state = context.read<MarkupState>();

    // Derive price info from the Product's price strings.
    // Product stores prices as strings: salePrice, basePrice, memberPrice.
    // toPricePoint().lowestPrice() returns the best (lowest) price.
    final bestPrice = product.toPricePoint().lowestPrice();
    final basePrice = parsePriceString(product.basePrice) ?? 0.0;
    final isOnSale = product.salePrice.isNotEmpty && parsePriceString(product.salePrice) != null;
    final originalPrice = isOnSale && basePrice > 0 ? basePrice : null;

    return SearchResultCard(
      productName: product.name,
      brand: product.brand,
      size: product.size,
      pictureUrl: product.pictureUrl.isNotEmpty ? product.pictureUrl : null,
      bestPrice: bestPrice,
      bestChain: '',  // Product model has companyId but not company name; chain name not available here
      otherPrices: const [],
      maxSavings: (isOnSale && originalPrice != null && originalPrice > bestPrice)
          ? originalPrice - bestPrice
          : 0,
      isBestDeal: index == 0,
      isOnSale: isOnSale,
      originalPrice: originalPrice,
      onTrack: () => state.trackProductLocally(product.id),
    );
  }

  Widget _sortDropdown(MarkupState state) {
    return DropdownButton<String>(
      value: state.sortBy,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary),
      items: const [
        DropdownMenuItem(value: 'best_savings', child: Text('Best savings')),
        DropdownMenuItem(value: 'lowest_price', child: Text('Lowest price')),
        DropdownMenuItem(value: 'alphabetical', child: Text('A\u2013Z')),
      ],
      onChanged: (v) {
        if (v != null) {
          state.setSortBy(v);
          _search(reset: true);
        }
      },
    );
  }
}

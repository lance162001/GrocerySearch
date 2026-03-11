import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/check_out.dart';
import 'package:flutter_front_end/chart.dart';
import 'package:fl_chart/fl_chart.dart';



class SearchPage extends StatefulWidget {
  SearchPage({
    super.key,
    required this.currentUserId,
    required this.stores,
    required this.userTags,
    required this.companies,
    required this.tags,
    required this.cart,
    required this.cartFinished,
    required this.setCart,
    required this.setCartFinished,
    required this.addToCartQty,
    required this.removeFromCartAll,
    required this.cartQuantities,
    required this.setTags,
    required this.searchTerm,
    required this.setSearchTerm,
  });

  final List<Company> companies;
  final int currentUserId;
  final List<Tag> tags;
  final Function setCart;
  final Function setCartFinished;
  final Function addToCartQty;
  final Function removeFromCartAll;
  final Map<int, int> cartQuantities;
  final Function setTags;
  final Function setSearchTerm;
  final String searchTerm;
  String termt = "";
  final List<Product> cart;
  final List<Product> cartFinished;
  final List<Store> stores;
  Future<List<Product>>? products;
  List<Tag> userTags = [];

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late Product selectedProduct;
  int page = 1;
  int pageLength = 100;
  Map<int, int> quantities = {};
  final ScrollController scrollController = ScrollController();
  TextEditingController searchFieldController = TextEditingController();
  bool showOnlySpread = false;
  bool showOnlySale = false;

  void _addToCart(Product p, int qty) {
    widget.addToCartQty(p, qty);
  }

  void _removeFromCart(Product p) {
    widget.removeFromCartAll(p);
  }

  double? _effectivePrice(Product product) {
    return parsePriceString(product.memberPrice) ??
        parsePriceString(product.salePrice) ??
        parsePriceString(product.basePrice);
  }

  bool _hasSalePrice(Product product) {
    bool hasValue(String value) {
      final normalized = value.trim().toLowerCase();
      return normalized.isNotEmpty && normalized != 'null' && normalized != 'none';
    }

    return hasValue(product.salePrice) || hasValue(product.memberPrice);
  }

  Store? _storeForId(int storeId) {
    for (final store in widget.stores) {
      if (store.id == storeId) {
        return store;
      }
    }
    return null;
  }

  Company? _companyForId(int companyId) {
    for (final company in widget.companies) {
      if (company.id == companyId) {
        return company;
      }
    }
    return null;
  }

  List<Product> _similarProducts(Product selected, List<Product> allProducts) {
    final perStore = <int, Product>{};
    for (final candidate in allProducts) {
      if (candidate.id != selected.id || candidate.storeId == selected.storeId) {
        continue;
      }
      final existing = perStore[candidate.storeId];
      if (existing == null) {
        perStore[candidate.storeId] = candidate;
        continue;
      }
      final existingPrice = _effectivePrice(existing);
      final candidatePrice = _effectivePrice(candidate);
      if (candidatePrice != null &&
          (existingPrice == null || candidatePrice < existingPrice)) {
        perStore[candidate.storeId] = candidate;
      }
    }

    final results = perStore.values.toList();
    results.sort((a, b) {
      final aPrice = _effectivePrice(a);
      final bPrice = _effectivePrice(b);
      if (aPrice == null && bPrice == null) return 0;
      if (aPrice == null) return 1;
      if (bPrice == null) return -1;
      return aPrice.compareTo(bPrice);
    });
    return results;
  }

  Map<String, dynamic>? _getPriceSpreadInfo(Product selected, List<Product> allProducts) {
    final perStore = <int, double>{};
    for (final candidate in allProducts) {
      if (candidate.id != selected.id) continue;
      final price = _effectivePrice(candidate);
      if (price != null) {
        if (!perStore.containsKey(candidate.storeId) || price < perStore[candidate.storeId]!) {
          perStore[candidate.storeId] = price;
        }
      }
    }

    if (perStore.length < 2) return null;

    final prices = perStore.values.toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final spread = maxPrice - minPrice;

    if (spread < 0.01) return null;

    return {
      'spread': spread,
      'storeCount': perStore.length,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
    };
  }

  @override
  void initState() {
    super.initState();
    widget.products = fetchProducts(widget.stores.map((s) => s.id).toList(),
      search: widget.termt,
      tags: widget.userTags,
      onSaleOnly: showOnlySale,
      page: page);
  }

  @override
  Widget build(BuildContext context) {
    List<int> storeIds = widget.stores.map((s) => s.id).toList();
    void s() {
      setState(() => 1);
    }

    setupScrollListener(
        scrollController: scrollController,
        onAtTop: () => 1,
        onAtBottom: () {
          widget.products?.then((v) {
            if (v.length >= page * pageLength) {
              page++;
              print(page);
            } else {
              print("${v.length} < ${page * pageLength}");
              return;
            }
            widget.products = fetchProducts(
              storeIds,
              search: widget.termt,
              tags: widget.userTags,
              onSaleOnly: showOnlySale,
              page: page,
              toAdd: v,
            );
            setState(() => {});
          });
        });

    return Scaffold(
        appBar: AppBar(
            title: Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(5)),
              child: TextField(
                onSubmitted: (text) {
                  page = 1;
                  widget.termt = text;
                  widget.products = fetchProducts(
                    storeIds,
                    search: text,
                    tags: widget.userTags,
                    onSaleOnly: showOnlySale,
                  );
                  setState(() {});
                },
                controller: searchFieldController,
                decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchFieldController.clear();
                        widget.termt = "";
                        page = 1;

                        widget.products =
                            fetchProducts(
                              storeIds,
                              tags: widget.userTags,
                              onSaleOnly: showOnlySale,
                            );
                        widget.products!.then((v) => setState(() => 1));
                      },
                    ),
                    hintText: 'Search By Product...',
                    border: InputBorder.none),
              ),
            ),
            actions: [
              IconButton(
                iconSize: 32,
                icon: Icon(Icons.more_vert),
                onPressed: () => {
                  showModalBottomSheet<void>(
                      context: context,
                      builder: (BuildContext context) {
                        return StatefulBuilder(builder:
                            (BuildContext context, StateSetter setState) {
                          return SizedBox(
                            height: 320,
                            child: Column(
                              children: [
                                Text("Filters",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("Show only items on sale",
                                          style: TextStyle(fontSize: 14)),
                                      Switch(
                                        value: showOnlySale,
                                        onChanged: (bool value) {
                                          page = 1;
                                          setState(() {
                                            showOnlySale = value;
                                          });
                                          widget.products = fetchProducts(
                                            storeIds,
                                            search: widget.termt,
                                            tags: widget.userTags,
                                            onSaleOnly: showOnlySale,
                                          );
                                          this.setState(() => 1);
                                        },
                                      )
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("Show items with price spread",
                                          style: TextStyle(fontSize: 14)),
                                      Switch(
                                        value: showOnlySpread,
                                        onChanged: (bool value) {
                                          setState(() {
                                            showOnlySpread = value;
                                          });
                                          this.setState(() => 1);
                                        },
                                      )
                                    ],
                                  ),
                                ),
                                Divider(),
                                Text("Filter By Tags",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(height: 5),
                                SizedBox(
                                  height: 150,
                                  child: SingleChildScrollView(
                                    child: Wrap(
                                        runSpacing: 2,
                                        spacing: 5.0,
                                        children: widget.tags
                                            .map((tag) => FilterChip(
                                                label: Text(tag.name),
                                                selected: widget.userTags
                                                    .contains(tag),
                                                onSelected: (bool selected) {
                                                  page = 1;
                                                  widget.userTags.contains(tag)
                                                      ? widget.userTags
                                                          .remove(tag)
                                                      : widget.userTags
                                                          .add(tag);
                                                  widget.products =
                                                      fetchProducts(
                                                    storeIds,
                                                    search: widget.termt,
                                                    tags: widget.userTags,
                                                    onSaleOnly: showOnlySale,
                                                  );
                                                  setState(() => 1);
                                                  widget.products!
                                                      .then((v) => s());
                                                }))
                                            .toList()
                                            .cast<Widget>()),
                                  ),
                                ),
                              ],
                            ),
                          );
                        });
                      })
                },
              ),
              Row(
                children: [
                  Text((widget.cartQuantities.values.fold(0, (a, b) => a + b)).toString()),
                  IconButton(
                      icon: Icon(Icons.shopping_cart_checkout),
                      iconSize: 32,
                        onPressed: () => {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CheckOut(
                                  currentUserId: widget.currentUserId,
                                  companies: widget.companies,
                                  stores: widget.stores,
                                  cart: widget.cart,
                                  cartFinished: widget.cartFinished,
                                  setCart: widget.setCart,
                                  setCartFinished:
                                    widget.setCartFinished,
                                  addToCartQty: widget.addToCartQty,
                                  removeFromCartAll: widget.removeFromCartAll,
                                  cartQuantities: widget.cartQuantities,
                                )))
                          }),
                ],
              )
            ]),
        body: FutureBuilder<List<Product>>(
            future: widget.products,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                List<Product> products = snapshot.data!;
                if (products.isEmpty) {
                  return Text("No Products Found!");
                }

                if (showOnlySale) {
                  products = products.where(_hasSalePrice).toList();

                  if (products.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          "No products found that are currently on sale",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ),
                    );
                  }
                }

                // Filter products with price spread if enabled
                if (showOnlySpread) {
                  products = products.where((product) {
                    final spreadInfo = _getPriceSpreadInfo(product, products);
                    return spreadInfo != null;
                  }).toList();
                
                  if (products.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          "No products found with price differences across stores",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ),
                    );
                  }
                }

                return ListView.builder(
                    controller: scrollController,
                    itemCount: products.length,
                    scrollDirection: Axis.vertical,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(1),
                    itemBuilder: (context, index) {
                      Product p = products[index];
                      final spreadInfo = _getPriceSpreadInfo(p, products);
                      return Card(
                        color: (widget.cartQuantities[p.instanceId] ?? 0) > 0
                          ? Colors.lightBlue[100]
                          : Colors.white,
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            InkWell(
                          splashColor: Colors.blue.withAlpha(30),
                          onTap: () {
                            final qty = quantities[p.instanceId] ?? 1;
                            if ((widget.cartQuantities[p.instanceId] ?? 0) > 0) {
                              _removeFromCart(p);
                            } else {
                              _addToCart(p, qty);
                            }
                          },
                          onLongPress: () {
                            final similarProducts = _similarProducts(p, products);
                            showModalBottomSheet<void>(
                                context: context,
                                builder: (BuildContext context) {
                                          return SizedBox(
                                            height: 500,
                                            child: Column(
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                  child: Row(
                                                    children: [
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(8),
                                                        child: getImage(p.pictureUrl, 84, 84),
                                                      ),
                                                      SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(p.name, style: TextStyle(fontWeight: FontWeight.bold)),
                                                            SizedBox(height: 6),
                                                            Text('${p.size} • ${p.brand}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                                                            SizedBox(height: 8),
                                                            Row(
                                                              children: [
                                                                if (p.memberPrice != "") Text(formatPriceString(p.memberPrice), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                                                                SizedBox(width: 8),
                                                                if (p.salePrice != "") Text(formatPriceString(p.salePrice), style: TextStyle(decoration: TextDecoration.lineThrough, color: Colors.redAccent)),
                                                                SizedBox(width: 8),
                                                                Text(formatPriceString(p.basePrice), style: TextStyle(color: Colors.grey[800])),
                                                              ],
                                                            )
                                                          ],
                                                        ),
                                                      )
                                                    ],
                                                  ),
                                                ),
                                                if (similarProducts.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                                    child: Align(
                                                      alignment: Alignment.centerLeft,
                                                      child: Text(
                                                        'At other selected stores',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          color: Colors.grey[800],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (similarProducts.isNotEmpty)
                                                  SizedBox(
                                                    height: 126,
                                                    child: ListView.separated(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                      scrollDirection: Axis.horizontal,
                                                      itemCount: similarProducts.length,
                                                      separatorBuilder: (_, __) => SizedBox(width: 8),
                                                      itemBuilder: (context, similarIndex) {
                                                        final other = similarProducts[similarIndex];
                                                        final selectedPrice = _effectivePrice(p);
                                                        final otherPrice = _effectivePrice(other);
                                                        final store = _storeForId(other.storeId);
                                                        final company = store == null
                                                            ? null
                                                            : _companyForId(store.companyId);

                                                        Color borderColor = Colors.blueGrey;
                                                        Color backgroundColor = Colors.blueGrey.shade50;
                                                        Color accentColor = Colors.blueGrey.shade700;
                                                        String comparison = 'Same price';
                                                        String deltaText = 'No difference';

                                                        if (selectedPrice != null && otherPrice != null) {
                                                          final delta = (selectedPrice - otherPrice).abs();
                                                          if (selectedPrice > otherPrice) {
                                                            borderColor = Colors.red.shade400;
                                                            backgroundColor = Colors.red.shade50;
                                                            accentColor = Colors.red.shade700;
                                                            comparison = 'Higher here';
                                                            deltaText = '\$${delta.toStringAsFixed(2)} more';
                                                          } else if (selectedPrice < otherPrice) {
                                                            borderColor = Colors.green.shade400;
                                                            backgroundColor = Colors.green.shade50;
                                                            accentColor = Colors.green.shade700;
                                                            comparison = 'Lower here';
                                                            deltaText = '\$${delta.toStringAsFixed(2)} less';
                                                          } else {
                                                            borderColor = Colors.blueGrey.shade400;
                                                            backgroundColor = Colors.blueGrey.shade50;
                                                            accentColor = Colors.blueGrey.shade700;
                                                            comparison = 'Same price';
                                                            deltaText = 'No difference';
                                                          }
                                                        } else {
                                                          comparison = 'Price unavailable';
                                                          deltaText = 'Cannot compare';
                                                        }

                                                        return Container(
                                                          width: 168,
                                                          padding: const EdgeInsets.all(8),
                                                          decoration: BoxDecoration(
                                                            color: backgroundColor,
                                                            borderRadius: BorderRadius.circular(10),
                                                            border: Border.all(color: borderColor),
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisAlignment: MainAxisAlignment.start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  if (company != null)
                                                                    ClipRRect(
                                                                      borderRadius: BorderRadius.circular(6),
                                                                      child: getImage(company.logoUrl, 22, 22),
                                                                    ),
                                                                  if (company != null)
                                                                    SizedBox(width: 6),
                                                                  Expanded(
                                                                    child: Text(
                                                                      store?.town ?? 'Store ${other.storeId}',
                                                                      maxLines: 1,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: TextStyle(
                                                                        fontWeight: FontWeight.w600,
                                                                        fontSize: 12,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              SizedBox(height: 6),
                                                              Text(
                                                                other.memberPrice != ""
                                                                    ? formatPriceString(other.memberPrice)
                                                                    : other.salePrice != ""
                                                                        ? formatPriceString(other.salePrice)
                                                                        : formatPriceString(other.basePrice),
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                  color: accentColor,
                                                                  fontSize: 13,
                                                                ),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                              SizedBox(height: 4),
                                                              Text(
                                                                comparison,
                                                                style: TextStyle(
                                                                  color: accentColor,
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.w600,
                                                                ),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                              Text(
                                                                deltaText,
                                                                style: TextStyle(
                                                                  color: Colors.grey[800],
                                                                  fontSize: 11,
                                                                ),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                Expanded(
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                                    child: PriceHistoryChart(pricepoints: p.priceHistory),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 8.0),
                                                  child: ElevatedButton(
                                                    onPressed: () => {
                                                      setState(() {
                                                        final qty = quantities[p.instanceId] ?? 1;
                                                        if ((widget.cartQuantities[p.instanceId] ?? 0) > 0) {
                                                          _removeFromCart(p);
                                                        } else {
                                                          _addToCart(p, qty);
                                                        }
                                                      }),
                                                      Navigator.pop(context)
                                                    },
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                        children: (widget.cartQuantities[p.instanceId] ?? 0) > 0
                                                          ? [
                                                              Text("Remove from Cart?"),
                                                              SizedBox(width: 6),
                                                              Icon(Icons.remove_shopping_cart)
                                                            ]
                                                          : [
                                                              Text("Add To Cart?"),
                                                              SizedBox(width: 6),
                                                              Icon(Icons.add_shopping_cart)
                                                            ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                });
                          },
                          child: Row(
                            children: [
                              Expanded(child: ProductBox(p: p, qty: widget.cartQuantities[p.instanceId] ?? 0)),
                              SizedBox(
                                width: 76,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      iconSize: 24,
                                      padding: EdgeInsets.zero,
                                      icon: (widget.cartQuantities[p.instanceId] ?? 0) > 0
                                        ? Icon(Icons.remove_shopping_cart)
                                        : Icon(Icons.add_shopping_cart),
                                      onPressed: () {
                                        setState(() {
                                          final qty = quantities[p.instanceId] ?? 1;
                                          if ((widget.cartQuantities[p.instanceId] ?? 0) > 0) {
                                            _removeFromCart(p);
                                          } else {
                                            _addToCart(p, qty);
                                          }
                                        });
                                      },
                                      tooltip: (widget.cartQuantities[p.instanceId] ?? 0) > 0
                                        ? 'Remove from cart'
                                        : 'Add to cart',
                                    ),
                                    SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          iconSize: 16,
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                          icon: Icon(Icons.remove_circle_outline),
                                          onPressed: () {
                                            setState(() {
                                              final curr = quantities[p.instanceId] ?? 1;
                                              final next = (curr - 1).clamp(1, 999);
                                              quantities[p.instanceId] = next;
                                            });
                                          },
                                        ),
                                        SizedBox(
                                          width: 22,
                                          child: Text('${quantities[p.instanceId] ?? 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                                        ),
                                        IconButton(
                                          iconSize: 16,
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                          icon: Icon(Icons.add_circle_outline),
                                          onPressed: () {
                                            setState(() {
                                              quantities[p.instanceId] = (quantities[p.instanceId] ?? 1) + 1;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 2),
                                    if (p.salePrice != "")
                                      Chip(
                                        label: Text("SALE",
                                            style: TextStyle(color: Colors.white, fontSize: 10)),
                                        backgroundColor: Colors.redAccent,
                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                      )
                                    else if (p.memberPrice != "")
                                      Chip(
                                        label: Text("MEMBER",
                                            style: TextStyle(color: Colors.white, fontSize: 10)),
                                        backgroundColor:
                                            Theme.of(context).colorScheme.primary,
                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                      )
                                  ],
                                ),
                              ),
                              StoreRow(
                                  product: p,
                                  store: widget.stores
                                      .firstWhere((s) => s.id == p.storeId),
                                  logoUrl: widget
                                      .companies[widget.stores
                                              .firstWhere(
                                                  (s) => s.id == p.storeId)
                                              .companyId -
                                          1]
                                      .logoUrl),
                            ],
                          ),
                        ),
                            if (spreadInfo != null)
                              Positioned(
                                top: 8,
                                left: 0,
                                right: 0,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Builder(
                                    builder: (context) {
                                      final currentPrice = _effectivePrice(p);
                                      final isMinPrice = currentPrice != null &&
                                          (currentPrice - spreadInfo['minPrice']).abs() < 0.01;
                                      final badgeColor = isMinPrice ? Colors.green[600] : Colors.red[600];
                                      final badgeIcon = isMinPrice
                                          ? Icons.trending_down
                                          : Icons.trending_up;
                                      final badgeLabel = isMinPrice
                                          ? '\$${spreadInfo['spread'].toStringAsFixed(2)} Cheaper Here'
                                          : '\$${spreadInfo['spread'].toStringAsFixed(2)} More Here';

                                      return Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: badgeColor,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(badgeIcon,
                                                color: Colors.white, size: 16),
                                            SizedBox(width: 6),
                                            Text(
                                              badgeLabel,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    });
              } else if (snapshot.hasError) {
                return Text('${snapshot.error}');
              } else {
                return CircularProgressIndicator();
              }
            }));
  }
}
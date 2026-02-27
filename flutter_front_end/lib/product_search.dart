import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/check_out.dart';
import 'package:flutter_front_end/chart.dart';
import 'package:fl_chart/fl_chart.dart';



class SearchPage extends StatefulWidget {
  SearchPage({
    super.key,
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

  void _addToCart(Product p, int qty) {
    widget.addToCartQty(p, qty);
  }

  void _removeFromCart(Product p) {
    widget.removeFromCartAll(p);
  }

  @override
  void initState() {
    super.initState();
    widget.products = fetchProducts(widget.stores.map((s) => s.id).toList(),
        search: widget.termt, tags: widget.userTags, page: page);
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
                            fetchProducts(storeIds, tags: widget.userTags);
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
                            height: 175,
                            child: Column(
                              children: [
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

                return ListView.builder(
                    controller: scrollController,
                    itemCount: products.length,
                    scrollDirection: Axis.vertical,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(1),
                    itemBuilder: (context, index) {
                      Product p = products[index];
                      return Card(
                            color: (widget.cartQuantities[p.id] ?? 0) > 0
                              ? Colors.lightBlue[100]
                              : Colors.white,
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          splashColor: Colors.blue.withAlpha(30),
                          onTap: () {
                            final qty = quantities[p.id] ?? 1;
                            if ((widget.cartQuantities[p.id] ?? 0) > 0) {
                              _removeFromCart(p);
                            } else {
                              _addToCart(p, qty);
                            }
                          },
                          onLongPress: () {
                            showModalBottomSheet<void>(
                                context: context,
                                builder: (BuildContext context) {
                                          return SizedBox(
                                            height: 360,
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
                                                        final qty = quantities[p.id] ?? 1;
                                                        if ((widget.cartQuantities[p.id] ?? 0) > 0) {
                                                          _removeFromCart(p);
                                                        } else {
                                                          _addToCart(p, qty);
                                                        }
                                                      }),
                                                      Navigator.pop(context)
                                                    },
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: (widget.cartQuantities[p.id] ?? 0) > 0
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
                              Expanded(child: ProductBox(p: p, qty: widget.cartQuantities[p.id] ?? 0)),
                              SizedBox(
                                width: 96,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      iconSize: 28,
                                      icon: (widget.cartQuantities[p.id] ?? 0) > 0
                                        ? Icon(Icons.remove_shopping_cart)
                                        : Icon(Icons.add_shopping_cart),
                                      onPressed: () {
                                        setState(() {
                                          final qty = quantities[p.id] ?? 1;
                                          if ((widget.cartQuantities[p.id] ?? 0) > 0) {
                                            _removeFromCart(p);
                                          } else {
                                            _addToCart(p, qty);
                                          }
                                        });
                                      },
                                      tooltip: (widget.cartQuantities[p.id] ?? 0) > 0
                                        ? 'Remove from cart'
                                        : 'Add to cart',
                                    ),
                                    SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          iconSize: 18,
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                          icon: Icon(Icons.remove_circle_outline),
                                          onPressed: () {
                                            setState(() {
                                              final curr = quantities[p.id] ?? 1;
                                              final next = (curr - 1).clamp(1, 999);
                                              quantities[p.id] = next;
                                            });
                                          },
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                          child: Text('${quantities[p.id] ?? 1}'),
                                        ),
                                        IconButton(
                                          iconSize: 18,
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                          icon: Icon(Icons.add_circle_outline),
                                          onPressed: () {
                                            setState(() {
                                              quantities[p.id] = (quantities[p.id] ?? 1) + 1;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 6),
                                    if (p.salePrice != "")
                                      Chip(
                                        label: Text("SALE",
                                            style: TextStyle(color: Colors.white)),
                                        backgroundColor: Colors.redAccent,
                                      )
                                    else if (p.memberPrice != "")
                                      Chip(
                                        label: Text("MEMBER",
                                            style: TextStyle(color: Colors.white)),
                                        backgroundColor:
                                            Theme.of(context).colorScheme.primary,
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
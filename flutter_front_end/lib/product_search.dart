import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_front_end/check_out.dart';
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
    required this.setTags,
    required this.searchTerm,
    required this.setSearchTerm,
  });

  final List<Company> companies;
  final List<Tag> tags;
  final Function setCart;
  final Function setCartFinished;
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
  final ScrollController scrollController = ScrollController();
  TextEditingController searchFieldController = TextEditingController();

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
                  Text(widget.cart.length.toString()),
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
                        color: widget.cart.contains(p)
                            ? Colors.lightBlue[100]
                            : Colors.white,
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          splashColor: Colors.blue.withAlpha(30),
                          onTap: () {
                            widget.cart.contains(p)
                                ? widget.cart.remove(p)
                                : widget.cart.add(p);
                            widget.setCart(widget.cart);
                          },
                          onLongPress: () {
                            showModalBottomSheet<void>(
                                context: context,
                                builder: (BuildContext context) {
                                  return SizedBox(
                                    height: 225,
                                    child: Column(
                                      children: [
                                        Text("${p.name}\nPrice History",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        SizedBox(
                                          width: 200,
                                          height: 100,
                                          child: BarChart(
                                            BarChartData(),
                                            swapAnimationCurve: Curves.linear,
                                            swapAnimationDuration:
                                                Duration(milliseconds: 150),
                                          ),
                                        ),
                                        SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: () => {
                                            setState(() =>
                                                widget.cart.contains(p)
                                                    ? widget.cart.remove(p)
                                                    : widget.cart.add(p)),
                                            Navigator.pop(context)
                                          },
                                          child: Column(
                                            children: [
                                              Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: widget.cart
                                                          .contains(p)
                                                      ? [
                                                          Text(
                                                              "Remove from Cart?"),
                                                          Icon(Icons
                                                              .remove_shopping_cart)
                                                        ]
                                                      : [
                                                          Text("Add To Cart?"),
                                                          Icon(Icons
                                                              .add_shopping_cart)
                                                        ]),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                });
                          },
                          child: Row(
                            children: [
                              Expanded(child: ProductBox(p: p)),
                              Expanded(
                                child: getImage(p.pictureUrl, 60, 60),
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
import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart';

class StoreSearch extends StatefulWidget {
  StoreSearch({
    super.key,
    required this.companies,
    required this.tags,
    required this.stores,
    required this.userStores,
    required this.userTags,
    required this.searchTerm,
    required this.setSearchTerm,
    required this.setStore,
    required this.setCart,
    required this.setCartFinished,
    required this.setTags,
    required this.cart,
    required this.cartFinished,
  });

  final List<Company> companies;
  final List<Tag> tags;
  Future<List<Store>> stores;
  List<Store> userStores;
  List<Tag> userTags;
  final Function setStore;
  final Function setCart;
  final Function setCartFinished;
  final Function setTags;
  final List<Product> cart;
  final List<Product> cartFinished;
  final String searchTerm;
  final Function setSearchTerm;

  @override
  State<StoreSearch> createState() => _StoreSearchState();
}

class _StoreSearchState extends State<StoreSearch> {
  late String storeSearch;
  final TextEditingController storeSearchController = TextEditingController();
  bool populatedStores = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(5)),
          child: TextFormField(
            keyboardType: TextInputType.text,
            onChanged: (text) => {
              setState(() {
                widget.stores = fetchStores(text);
              })
            },
            controller: storeSearchController,
            decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    storeSearchController.clear();
                  },
                ),
                hintText: 'Search For Stores By Zipcode or Address!',
                border: InputBorder.none),
          ),
        ),
      ),
      body: Center(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<Store>>(
                  future: widget.stores,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      List<Store> stores = snapshot.data! + widget.userStores;

                      stores = stores.toSet().toList();
                      return GridView.builder(
                        itemCount: stores.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2),
                        shrinkWrap: true,
                        primary: false,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          Store store = stores[index];
                          return Card(
                            color: widget.userStores.contains(store)
                                ? Colors.lightBlue
                                : const Color.fromARGB(255, 144, 220, 255),
                            child: InkWell(
                                splashColor: Colors.blue.withAlpha(30),
                                onTap: () {
                                  widget.setStore(store);
                                },
                                child: Column(children: [
                                  widget.companies.isNotEmpty
                                      ? getImage(
                                          widget.companies[store.companyId - 1]
                                              .logoUrl,
                                          100,
                                          100)
                                      : CircularProgressIndicator(),
                                  Text(store.town,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(store.state,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(store.address,
                                      style: TextStyle(
                                          fontStyle: FontStyle.italic)),
                                ])),
                          );
                        },
                      );
                    } else if (snapshot.hasError) {
                      return Text('${snapshot.error}');
                    }
                    return CircularProgressIndicator();
                  }),
            ),
            SizedBox(height: 20),
            widget.userStores.isEmpty
                ? OutlinedButton(
                    onPressed: () => {}, child: Text("Confirm Stores"))
                : ElevatedButton(
                    onPressed: () => {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (context) {
                            return SearchPage(
                              companies: widget.companies,
                              tags: widget.tags,
                              stores: widget.userStores,
                              userTags: widget.userTags,
                              setTags: widget.setTags,
                              cart: widget.cart,
                              cartFinished: widget.cartFinished,
                              setCart: widget.setCart,
                              setCartFinished: widget.setCartFinished,
                              searchTerm: widget.searchTerm,
                              setSearchTerm: widget.setSearchTerm,
                            );
                          }))
                        },
                    child: Text("Confirm Stores")),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

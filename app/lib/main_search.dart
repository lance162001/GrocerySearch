import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_front_end/main.dart';
import 'package:flutter_front_end/product_search.dart';
import 'package:http/http.dart' as http;

class StoreSearch extends StatefulWidget {
  StoreSearch({
    super.key,
    required this.currentUserId,
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
    required this.addToCartQty,
    required this.removeFromCartAll,
    required this.cartQuantities,
    required this.setTags,
    required this.cart,
    required this.cartFinished,
  });

  final List<Company> companies;
  final int currentUserId;
  final List<Tag> tags;
  Future<List<Store>> stores;
  List<Store> userStores;
  List<Tag> userTags;
  final Function setStore;
  final Function setCart;
  final Function setCartFinished;
  final Function addToCartQty;
  final Function removeFromCartAll;
  final Map<int, int> cartQuantities;
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
  bool showSelectedOnly = false;
  bool _savingStores = false;

  @override
  void initState() {
    super.initState();
    _hydrateSavedStores();
  }

  Future<void> _hydrateSavedStores() async {
    try {
      final savedStoreIds = await fetchSavedStoreIdsForUser(widget.currentUserId);
      if (savedStoreIds.isEmpty) return;

      final loadedStoreIds = widget.userStores.map((store) => store.id).toSet();
      final missingIds = savedStoreIds.difference(loadedStoreIds);
      if (missingIds.isEmpty) return;

      final allStores = await fetchAllStores();
      final storesToAdd = allStores
          .where((store) => missingIds.contains(store.id))
          .toList();

      if (storesToAdd.isEmpty || !mounted) return;
      setState(() {
        widget.userStores.addAll(storesToAdd);
      });
    } catch (_) {}
  }

  Future<void> _saveSelectedStoresForUser() async {
    final headers = {'Content-Type': 'application/json'};
    for (final store in widget.userStores) {
      final response = await http.post(
        Uri.http('$hostname:$port', '/users/${widget.currentUserId}/saved-stores'),
        headers: headers,
        body: jsonEncode({'store_id': store.id, 'member': false}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed saving store ${store.id}: ${response.statusCode}');
      }
    }
  }

  void _clearSelectedStores() {
    final selectedStores = List<Store>.from(widget.userStores);
    for (final store in selectedStores) {
      widget.setStore(store);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 1100
        ? 5
        : screenWidth >= 800
            ? 4
            : screenWidth >= 600
                ? 3
                : 2;

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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.currentUserId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bundle planner',
            icon: const Icon(Icons.route),
            onPressed: () => Navigator.pushNamed(context, '/bundle-plan'),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.userStores.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed:
                      widget.userStores.isEmpty ? null : _clearSelectedStores,
                  child: const Text('Clear all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Selected only'),
                  selected: showSelectedOnly,
                  onSelected: (value) {
                    setState(() => showSelectedOnly = value);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Store>>(
                future: widget.stores,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    List<Store> stores = snapshot.data! + widget.userStores;
                    stores = stores.toSet().toList();

                    stores.sort((a, b) {
                      final aSelected = widget.userStores.contains(a);
                      final bSelected = widget.userStores.contains(b);
                      if (aSelected != bSelected) {
                        return aSelected ? -1 : 1;
                      }
                      final townCompare =
                          a.town.toLowerCase().compareTo(b.town.toLowerCase());
                      if (townCompare != 0) return townCompare;
                      return a.address
                          .toLowerCase()
                          .compareTo(b.address.toLowerCase());
                    });

                    if (showSelectedOnly) {
                      stores = stores
                          .where((store) => widget.userStores.contains(store))
                          .toList();
                    }

                    return GridView.builder(
                      itemCount: stores.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 1.35,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6),
                      shrinkWrap: true,
                      primary: false,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      itemBuilder: (context, index) {
                        Store store = stores[index];
                        final isSaved = widget.userStores.contains(store);
                        return Card(
                          color: isSaved
                              ? Colors.lightBlue
                              : const Color.fromARGB(255, 144, 220, 255),
                          child: InkWell(
                              splashColor: Colors.blue.withAlpha(30),
                              onTap: () {
                                widget.setStore(store);
                                setState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                child: Stack(
                                  children: [
                                    if (isSaved)
                                      const Align(
                                        alignment: Alignment.topRight,
                                        child: Icon(
                                          Icons.bookmark,
                                          size: 18,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        widget.companies.isNotEmpty
                                            ? getImage(
                                                widget.companies[store.companyId - 1]
                                                    .logoUrl,
                                                58,
                                                58)
                                            : SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2),
                                              ),
                                        SizedBox(height: 4),
                                        Text(
                                          store.town,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12),
                                        ),
                                        Text(
                                          store.state,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 11),
                                        ),
                                        Text(
                                          store.address,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )),
                        );
                      },
                    );
                  } else if (snapshot.hasError) {
                    return Text('${snapshot.error}');
                  }
                  return Center(child: CircularProgressIndicator());
                }),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: widget.userStores.isEmpty || _savingStores
                ? null
                : () async {
                    setState(() => _savingStores = true);
                    try {
                      await _saveSelectedStoresForUser();
                      if (!mounted) return;
                      Navigator.push(context, MaterialPageRoute(builder: (context) {
                        return SearchPage(
                          currentUserId: widget.currentUserId,
                          companies: widget.companies,
                          tags: widget.tags,
                          stores: widget.userStores,
                          userTags: widget.userTags,
                          setTags: widget.setTags,
                          cart: widget.cart,
                          cartFinished: widget.cartFinished,
                          setCart: widget.setCart,
                          setCartFinished: widget.setCartFinished,
                          addToCartQty: widget.addToCartQty,
                          removeFromCartAll: widget.removeFromCartAll,
                          cartQuantities: widget.cartQuantities,
                          searchTerm: widget.searchTerm,
                          setSearchTerm: widget.setSearchTerm,
                        );
                      }));
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not save stores: $e')),
                      );
                    } finally {
                      if (mounted) setState(() => _savingStores = false);
                    }
                  },
            child: _savingStores
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Confirm Stores (${widget.userStores.length})'),
          ),
        ),
      ),
    );
  }
}

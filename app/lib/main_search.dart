import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/services/auth_service.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/widgets/top_level_navigation.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:provider/provider.dart';

class StoreSearch extends StatefulWidget {
  const StoreSearch({super.key});

  @override
  State<StoreSearch> createState() => _StoreSearchState();
}

class _StoreSearchState extends State<StoreSearch> {
  final TextEditingController storeSearchController = TextEditingController();
  late Future<List<Store>> _storesFuture;
  bool _initialized = false;
  bool showSelectedOnly = false;
  bool _savingStores = false;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _storesFuture = context.read<GroceryApi>().fetchStores('');
    _initialized = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    storeSearchController.dispose();
    super.dispose();
  }

  void _clearSelectedStores() {
    context.read<AppState>().clearSelectedStores();
  }

  static String _userInitial(String name) {
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  void _searchStores(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _storesFuture = context.read<GroceryApi>().fetchStores(text);
      });
    });
  }

  void _clearSearch() {
    storeSearchController.clear();
    _searchStores('');
  }

  Company? _companyForStore(List<Company> companies, Store store) {
    for (final company in companies) {
      if (company.id == store.companyId) {
        return company;
      }
    }
    return null;
  }

  Future<void> _openDestination(AppTopLevelDestination destination) async {
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (destination == AppTopLevelDestination.staples &&
        appState.userStores.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pick at least one store to browse staples.')),
      );
      return;
    }

    if (destination != AppTopLevelDestination.stores &&
        appState.userStores.isNotEmpty) {
      setState(() => _savingStores = true);
      try {
        await appState.persistSelectedStores();
      } catch (error) {
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not save stores. Please try again.')),
        );
      } finally {
        if (mounted) {
          setState(() => _savingStores = false);
        }
      }
    }

    if (!mounted) {
      return;
    }

    navigator.pushNamed(routeForTopLevelDestination(destination));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedStores = appState.userStores;
    final companies = appState.companies;
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          child: TextFormField(
            keyboardType: TextInputType.text,
            onChanged: _searchStores,
            controller: storeSearchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: Color(0xFF71717A)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Color(0xFF71717A)),
                onPressed: _clearSearch,
              ),
              hintText: 'Search stores by zipcode or address',
              filled: true,
              fillColor: Colors.white,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Builder(
                builder: (context) {
                  final authService = context.watch<AuthService>();
                  final photoUrl = authService.photoUrl;
                  final displayName = authService.displayName ?? authService.email ?? '';
                  return PopupMenuButton<String>(
                    tooltip: displayName,
                    onSelected: (value) {
                      if (value == 'sign_out') {
                        authService.signOut();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'sign_out',
                        child: Text('Sign out'),
                      ),
                    ],
                    child: _ProfileAvatar(
                      photoUrl: photoUrl,
                      initial: _userInitial(displayName),
                    ),
                  );
                },
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bundle planner',
            icon: const Icon(Icons.route),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.bundlePlan),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'label') {
                Navigator.pushNamed(context, AppRoutes.labelJudgement);
              } else if (value == 'suggest_store') {
                Navigator.pushNamed(context, AppRoutes.suggestStore);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'label',
                child: Row(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Help label products'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'suggest_store',
                child: Row(
                  children: [
                    Icon(Icons.add_business, size: 20),
                    SizedBox(width: 12),
                    Text('Suggest a store'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selectedStores.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed:
                      selectedStores.isEmpty ? null : _clearSelectedStores,
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
              future: _storesFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  var stores =
                      <Store>{...snapshot.data!, ...selectedStores}.toList();
                  stores.sort((a, b) {
                    final aSelected = selectedStores.contains(a);
                    final bSelected = selectedStores.contains(b);
                    if (aSelected != bSelected) {
                      return aSelected ? -1 : 1;
                    }
                    final townCompare =
                        a.town.toLowerCase().compareTo(b.town.toLowerCase());
                    if (townCompare != 0) {
                      return townCompare;
                    }
                    return a.address
                        .toLowerCase()
                        .compareTo(b.address.toLowerCase());
                  });

                  if (showSelectedOnly) {
                    stores = stores
                        .where((store) => selectedStores.contains(store))
                        .toList();
                  }

                  return GridView.builder(
                    itemCount: stores.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 1.35,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    shrinkWrap: true,
                    primary: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    itemBuilder: (context, index) {
                      final store = stores[index];
                      final isSaved = selectedStores.contains(store);
                      final company = _companyForStore(companies, store);
                      return Card(
                        color: isSaved
                            ? const Color(0xFFEEF2FF)
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSaved
                                ? const Color(0xFFC7D2FE)
                                : const Color(0xFFE4E4E7),
                          ),
                        ),
                        child: InkWell(
                          splashColor: const Color(0xFF6366F1).withAlpha(20),
                          onTap: () {
                            context.read<AppState>().toggleStore(store);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Stack(
                              children: [
                                if (isSaved)
                                  const Align(
                                    alignment: Alignment.topRight,
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    company != null
                                        ? ProductImage(
                                            url: company.logoUrl,
                                            width: 58,
                                            height: 58,
                                          )
                                        : SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                    const SizedBox(height: 4),
                                    Text(
                                      store.town,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      store.state,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      store.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: selectedStores.isEmpty || _savingStores
                    ? null
                    : () => _openDestination(AppTopLevelDestination.staples),
                icon: _savingStores
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                label: const Text('Continue to Staples'),
              ),
            ),
            const SizedBox(height: 8),
            TopLevelNavigationBar(
              currentDestination: AppTopLevelDestination.stores,
              onDestinationSelected: _openDestination,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl, required this.initial});
  final String? photoUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null) {
      return _fallback(context);
    }
    return ClipOval(
      child: SizedBox(
        width: 32,
        height: 32,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

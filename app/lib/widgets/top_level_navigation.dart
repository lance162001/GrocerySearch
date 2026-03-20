import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:provider/provider.dart';

enum AppTopLevelDestination {
  stores,
  staples,
  search,
  cart,
}

String routeForTopLevelDestination(AppTopLevelDestination destination) {
  switch (destination) {
    case AppTopLevelDestination.stores:
      return AppRoutes.storeSearch;
    case AppTopLevelDestination.staples:
      return AppRoutes.staplesOverview;
    case AppTopLevelDestination.search:
      return AppRoutes.search;
    case AppTopLevelDestination.cart:
      return AppRoutes.checkout;
  }
}

void navigateToTopLevelDestination(
  BuildContext context,
  AppTopLevelDestination destination,
) {
  Navigator.of(context).pushNamedAndRemoveUntil(
    routeForTopLevelDestination(destination),
    (route) => route.isFirst,
  );
}

class TopLevelNavigationBar extends StatelessWidget {
  const TopLevelNavigationBar({
    super.key,
    required this.currentDestination,
    this.onDestinationSelected,
  });

  final AppTopLevelDestination currentDestination;
  final ValueChanged<AppTopLevelDestination>? onDestinationSelected;

  int get _selectedIndex {
    switch (currentDestination) {
      case AppTopLevelDestination.stores:
        return 0;
      case AppTopLevelDestination.staples:
        return 1;
      case AppTopLevelDestination.search:
        return 2;
      case AppTopLevelDestination.cart:
        return 3;
    }
  }

  AppTopLevelDestination _destinationFromIndex(int index) {
    switch (index) {
      case 0:
        return AppTopLevelDestination.stores;
      case 1:
        return AppTopLevelDestination.staples;
      case 2:
        return AppTopLevelDestination.search;
      case 3:
      default:
        return AppTopLevelDestination.cart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<AppState, int>((state) => state.cartTotalItems);

    Widget cartIcon(bool selected) {
      final icon = Icon(selected ? Icons.shopping_cart : Icons.shopping_cart_outlined);
      if (cartCount <= 0) {
        return icon;
      }
      return Badge.count(
        count: cartCount,
        child: icon,
      );
    }

    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        final destination = _destinationFromIndex(index);
        if (destination == currentDestination) {
          return;
        }
        final handler = onDestinationSelected;
        if (handler != null) {
          handler(destination);
          return;
        }
        navigateToTopLevelDestination(context, destination);
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront),
          label: 'Stores',
        ),
        const NavigationDestination(
          icon: Icon(Icons.breakfast_dining_outlined),
          selectedIcon: Icon(Icons.breakfast_dining),
          label: 'Staples',
        ),
        const NavigationDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: 'Search',
        ),
        NavigationDestination(
          icon: cartIcon(false),
          selectedIcon: cartIcon(true),
          label: 'Cart',
        ),
      ],
    );
  }
}
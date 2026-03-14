import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/app_environment.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/product_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ProductBox shows product details and formatted prices', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      Provider<AppEnvironment>.value(
        value: AppEnvironment.local,
        child: MaterialApp(
          home: Scaffold(
            body: ProductBox(
              p: Product(
                id: 10,
                instanceId: 99,
                lastUpdated: DateTime(2026, 3, 13),
                brand: 'Test Brand',
                memberPrice: '1.99',
                salePrice: '2.49',
                basePrice: '3.29',
                size: '12 oz',
                pictureUrl: '/static/test.png',
                name: 'Apples',
                priceHistory: [
                  PricePoint(
                    memberPrice: '1.99',
                    salePrice: '2.49',
                    basePrice: '3.29',
                    size: '12 oz',
                    timestamp: DateTime(2026, 3, 13),
                  ),
                ],
                companyId: 1,
                storeId: 2,
              ),
              qty: 3,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Apples'), findsOneWidget);
    expect(find.text('12 oz'), findsOneWidget);
    expect(find.text(r'$1.99'), findsOneWidget);
    expect(find.text(r'$2.49'), findsOneWidget);
    expect(find.text(r'$3.29'), findsOneWidget);
    expect(find.text('Qty: 3'), findsOneWidget);
    expect(find.byType(ProductBox), findsOneWidget);
  });
}

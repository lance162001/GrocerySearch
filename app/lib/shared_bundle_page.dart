import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
import 'package:flutter_front_end/utils/product_grouping.dart';
import 'package:flutter_front_end/widgets/product_detail_sheet.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Local data models
// ---------------------------------------------------------------------------

class _PricePointData {
  final String basePrice;
  final String? salePrice;
  final String? memberPrice;
  final String? size;

  _PricePointData({
    required this.basePrice,
    this.salePrice,
    this.memberPrice,
    this.size,
  });

  factory _PricePointData.fromJson(Map<String, dynamic> j) => _PricePointData(
        basePrice: j['base_price']?.toString() ?? '0',
        salePrice: j['sale_price']?.toString(),
        memberPrice: j['member_price']?.toString(),
        size: j['size']?.toString(),
      );

  double? get effectivePrice =>
      parsePriceString(memberPrice ?? '') ??
      parsePriceString(salePrice ?? '') ??
      parsePriceString(basePrice);
}

class _InstanceData {
  final int storeId;
  final List<_PricePointData> pricePoints;

  _InstanceData({required this.storeId, required this.pricePoints});

  factory _InstanceData.fromJson(Map<String, dynamic> j) => _InstanceData(
        storeId: j['store_id'] as int,
        pricePoints: (j['price_points'] as List<dynamic>? ?? [])
            .map((e) => _PricePointData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class _SharedProduct {
  final int productId;
  final String name;
  final String brand;
  final String pictureUrl;
  final List<_InstanceData> instances;

  _SharedProduct({
    required this.productId,
    required this.name,
    required this.brand,
    required this.pictureUrl,
    required this.instances,
  });

  factory _SharedProduct.fromJson(Map<String, dynamic> j) => _SharedProduct(
        productId: j['product_id'] as int,
        name: j['name']?.toString() ?? '',
        brand: j['brand']?.toString() ?? '',
        pictureUrl: j['picture_url']?.toString() ?? '',
        instances: (j['instances'] as List<dynamic>? ?? [])
            .map((e) => _InstanceData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  double? get bestPrice {
    double? best;
    for (final inst in instances) {
      for (final pp in inst.pricePoints) {
        final p = pp.effectivePrice;
        if (p != null && (best == null || p < best)) best = p;
      }
    }
    return best;
  }

  ProductGroup toProductGroup() {
    final options = <Product>[];
    for (final inst in instances) {
      if (inst.pricePoints.isEmpty) continue;
      _PricePointData? best;
      for (final pp in inst.pricePoints) {
        if (best == null ||
            (pp.effectivePrice ?? double.infinity) <
                (best.effectivePrice ?? double.infinity)) {
          best = pp;
        }
      }
      best ??= inst.pricePoints.first;

      final history = inst.pricePoints.map((pp) {
        return PricePoint(
          basePrice: pp.basePrice,
          salePrice: pp.salePrice ?? '',
          memberPrice: pp.memberPrice ?? '',
          size: pp.size ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        );
      }).toList();

      final syntheticId =
          Object.hash(productId, inst.storeId) & 0x3fffffff;
      options.add(Product(
        id: productId,
        instanceId: syntheticId,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
        name: name,
        brand: brand,
        pictureUrl: pictureUrl,
        companyId: 0,
        storeId: inst.storeId,
        basePrice: best.basePrice,
        salePrice: best.salePrice ?? '',
        memberPrice: best.memberPrice ?? '',
        size: best.size ?? '',
        priceHistory: history,
      ));
    }

    if (options.isEmpty) {
      options.add(Product(
        id: productId,
        instanceId: productId,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
        name: name,
        brand: brand,
        pictureUrl: pictureUrl,
        companyId: 0,
        storeId: 0,
        basePrice: '0',
        salePrice: '',
        memberPrice: '',
        size: '',
        priceHistory: const [],
      ));
    }

    options.sort((a, b) {
      final pa = productEffectivePrice(a) ?? double.infinity;
      final pb = productEffectivePrice(b) ?? double.infinity;
      return pa.compareTo(pb);
    });

    return ProductGroup(options: options);
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class SharedBundlePage extends StatefulWidget {
  const SharedBundlePage({super.key});

  @override
  State<SharedBundlePage> createState() => _SharedBundlePageState();
}

class _SharedBundlePageState extends State<SharedBundlePage> {
  _Status _status = _Status.loading;
  // Captured eagerly in initState before the browser URL is rewritten.
  String? _token;
  String _bundleName = 'GrocerySearch';
  List<_SharedProduct> _products = [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _token = Uri.base.queryParameters['token'];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb && _token == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _token = args['token'] as String?;
      }
    }
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _status = _Status.notFound);
      return;
    }
    try {
      final api = context.read<GroceryApi>();
      final data = await api.getObject('/bundles/shared/$token');
      if (data == null) {
        setState(() => _status = _Status.notFound);
        return;
      }
      setState(() {
        _bundleName = (data['name'] as String?) ?? 'New this week';
        _products = (data['products'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(_SharedProduct.fromJson)
            .toList();
        _status = _Status.loaded;
      });
    } catch (_) {
      setState(() => _status = _Status.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(_bundleName),
        backgroundColor: const Color(0xFF1b4332),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _goHome,
            child: const Text('Home', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  void _goHome() {
    if (kIsWeb) {
      html.window.location.href = '/';
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  Widget _buildBody() {
    switch (_status) {
      case _Status.loading:
        return const Center(child: CircularProgressIndicator());

      case _Status.notFound:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'This bundle link is invalid or has expired.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ),
        );

      case _Status.error:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Something went wrong loading this bundle.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
          ),
        );

      case _Status.loaded:
        if (_products.isEmpty) {
          return const Center(child: Text('No products in this bundle.'));
        }
        final cs = Theme.of(context).colorScheme;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _products.length,
          itemBuilder: (context, index) => _buildProductCard(_products[index], cs),
        );
    }
  }

  Widget _buildProductCard(_SharedProduct product, ColorScheme cs) {
    final bestPriceText = product.bestPrice != null
        ? '\$${product.bestPrice!.toStringAsFixed(2)}'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => showProductDetailSheet(
          context: context,
          group: product.toProductGroup(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  if (product.brand.isNotEmpty)
                    Text(
                      product.brand,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap for price details & history',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.primary.withValues(alpha: 0.7)),
                  ),
                ],
              );

              final leading = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.pictureUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ProductImage(
                        url: product.pictureUrl,
                        width: 48,
                        height: 48,
                      ),
                    ),
                  if (product.pictureUrl.isNotEmpty) const SizedBox(width: 10),
                  Expanded(child: details),
                ],
              );

              final priceWidget = bestPriceText != null
                  ? Text(
                      bestPriceText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: cs.primary,
                      ),
                    )
                  : null;

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    if (priceWidget != null) ...[
                      const SizedBox(height: 8),
                      priceWidget,
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: leading),
                  if (priceWidget != null) ...[
                    const SizedBox(width: 12),
                    priceWidget,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _Status { loading, loaded, notFound, error }


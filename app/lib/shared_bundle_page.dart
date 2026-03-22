import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/utils/price_utils.dart';
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
    String? money(double? v) =>
        v == null ? null : '\$${v.toStringAsFixed(2)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Product header ----
            LayoutBuilder(
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
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
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
                    if (product.pictureUrl.isNotEmpty)
                      const SizedBox(width: 10),
                    Expanded(child: details),
                  ],
                );

                final bestPriceText = money(product.bestPrice);
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

            // ---- Price points by store ----
            if (product.instances.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                'Price Points by Store',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              ...product.instances.map((inst) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Store ${inst.storeId}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          if (inst.pricePoints.isEmpty)
                            Text(
                              'No price data',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                          ...inst.pricePoints.map((pp) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 2),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    if (pp.size != null &&
                                        pp.size!.isNotEmpty)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.secondaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          pp.size!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                cs.onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      formatPriceString(pp.basePrice),
                                      style: (pp.salePrice != null &&
                                                  pp.salePrice!
                                                      .isNotEmpty) ||
                                              (pp.memberPrice != null &&
                                                  pp.memberPrice!
                                                      .isNotEmpty)
                                          ? TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              decoration: TextDecoration
                                                  .lineThrough,
                                            )
                                          : const TextStyle(
                                              fontSize: 13,
                                              fontWeight:
                                                  FontWeight.w600),
                                    ),
                                    if (pp.salePrice != null &&
                                        pp.salePrice!.isNotEmpty)
                                      Text(
                                        formatPriceString(pp.salePrice!),
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    if (pp.memberPrice != null &&
                                        pp.memberPrice!.isNotEmpty)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.primary
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          formatPriceString(
                                              pp.memberPrice!),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Status { loading, loaded, notFound, error }


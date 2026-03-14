import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/app_environment.dart';
import 'package:provider/provider.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
  });

  final String url;
  final double width;
  final double height;
  final BoxFit fit;

  Widget _fallbackImage(BuildContext context, IconData icon) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: width < 24 ? 12 : 20,
        color: Colors.grey[600],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final environment = context.read<AppEnvironment>();
    if (url.trim().isEmpty ||
        WidgetsBinding.instance is! WidgetsFlutterBinding) {
      return _fallbackImage(context, Icons.image_outlined);
    }

    return CachedNetworkImage(
      imageUrl: environment.resolveAssetUrl(url),
      width: width,
      height: height,
      fit: fit,
      alignment: Alignment.center,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (context, imageUrl) =>
          _fallbackImage(context, Icons.image_outlined),
      errorWidget: (context, imageUrl, error) =>
          _fallbackImage(context, Icons.broken_image),
    );
  }
}

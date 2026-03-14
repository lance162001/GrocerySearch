import 'package:flutter/widgets.dart';

void setupScrollListener({
  required ScrollController scrollController,
  VoidCallback? onAtTop,
  VoidCallback? onAtBottom,
}) {
  scrollController.addListener(() {
    if (!scrollController.hasClients || !scrollController.position.atEdge) {
      return;
    }
    if (scrollController.position.pixels == 0) {
      onAtTop?.call();
      return;
    }
    onAtBottom?.call();
  });
}
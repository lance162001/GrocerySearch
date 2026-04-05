import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/widgets/tracked_item_card.dart';
import 'package:flutter_front_end/config/markup_theme.dart';
import 'package:flutter_front_end/screens/tracking_detail_screen.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  List<TrackedItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<MarkupState>();
    if (state.currentUserId == null) return; // anonymous — no server fetch
    setState(() => _loading = true);
    try {
      final items = await state.api.fetchTrackedItems(state.currentUserId!);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _untrack(int productId) async {
    final state = context.read<MarkupState>();
    state.untrackProductLocally(productId);
    if (state.currentUserId != null) {
      try { await state.api.untrackProduct(state.currentUserId!, productId); } catch (_) {}
    }
    setState(() => _items.removeWhere((i) => i.productId == productId));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MarkupState>();
    final isAnon = state.currentUserId == null;

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(child: Text('Tracking', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary))),
                if (!isAnon)
                  TextButton(onPressed: () {}, child: const Text('Edit', style: TextStyle(color: MarkupColors.darkGreen))),
              ],
            ),
          ),
          // Sign-in nudge
          if (isAnon)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: MarkupColors.darkGreen),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Sign in to get price alerts via email', style: TextStyle(fontSize: 13, color: MarkupColors.darkGreen)),
                  ),
                  GestureDetector(
                    onTap: () {},  // Profile sheet — Task 13
                    child: const Text('Sign in', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            ),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: MarkupColors.darkGreen))
                : isAnon && state.localTrackedProductIds.isEmpty
                    ? _emptyState()
                    : !isAnon && _items.isEmpty
                        ? _emptyState()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              itemCount: isAnon ? state.localTrackedProductIds.length : _items.length,
                              itemBuilder: (ctx, i) {
                                if (isAnon) {
                                  // Anonymous: show product ID only (no price data available without server)
                                  final pid = state.localTrackedProductIds[i];
                                  return _anonTrackedTile(pid, state);
                                }
                                return TrackedItemCard(
                                  item: _items[i],
                                  onTap: () => _openDetail(_items[i].productId),
                                  onUntrack: () => _untrack(_items[i].productId),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _anonTrackedTile(int productId, MarkupState state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: [
          Expanded(child: Text('Product #$productId', style: const TextStyle(fontSize: 14, color: MarkupColors.textPrimary))),
          IconButton(
            icon: const Icon(Icons.notifications_off_outlined, size: 20, color: MarkupColors.textHint),
            onPressed: () => state.untrackProductLocally(productId),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: 400,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.notifications_none, size: 48, color: MarkupColors.textHint),
              SizedBox(height: 12),
              Text('Nothing tracked yet', style: TextStyle(fontSize: 16, color: MarkupColors.textPrimary)),
              SizedBox(height: 4),
              Text('Tap "\u{1F514} Track" on any product to watch its price', style: TextStyle(fontSize: 13, color: MarkupColors.textSecondary), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(int productId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TrackingDetailScreen(productId: productId)));
  }
}

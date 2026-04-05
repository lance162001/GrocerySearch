import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/screens/profile_sheet.dart';
import 'package:flutter_front_end/widgets/location_banner.dart';
import 'package:flutter_front_end/widgets/feed_price_reveal_card.dart';
import 'package:flutter_front_end/widgets/feed_savings_card.dart';
import 'package:flutter_front_end/widgets/feed_community_card.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadFeed() async {
    if (_loading) return;
    setState(() => _loading = true);
    final state = context.read<MarkupState>();
    try {
      final resp = await state.api.fetchFeed(page: 1, size: 10, zipcode: state.zipcode);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp['items'] ?? []);
        _hasMore = resp['has_more'] ?? false;
        _page = 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final state = context.read<MarkupState>();
    try {
      final resp = await state.api.fetchFeed(page: _page + 1, size: 10, zipcode: state.zipcode);
      if (!mounted) return;
      setState(() {
        _items.addAll(List<Map<String, dynamic>>.from(resp['items'] ?? []));
        _hasMore = resp['has_more'] ?? false;
        _page += 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MarkupState>();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('Markup', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(24)),
                    child: const Text('🔍 Search any product...', style: TextStyle(fontSize: 14, color: MarkupColors.textHint)),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showProfile(context),
                  child: const CircleAvatar(radius: 16, backgroundColor: Color(0xFFE0E0E0), child: Icon(Icons.person, size: 18, color: MarkupColors.textHint)),
                ),
              ],
            ),
          ),
          LocationBanner(zipcode: state.zipcode, onSetArea: () => _showSetArea(context, state)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadFeed,
              child: _items.isEmpty && !_loading
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: const Center(child: Text('No feed items yet.', style: TextStyle(color: MarkupColors.textSecondary))),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _items.length + (_loading ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator(color: MarkupColors.darkGreen)),
                          );
                        }
                        return _buildFeedCard(_items[i]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> item) {
    switch (item['type']) {
      case 'price_reveal':
        return FeedPriceRevealCard(
          productName: item['product_name'] as String? ?? '',
          brand: item['brand'] as String? ?? '',
          size: item['size'] as String? ?? '',
          prices: List<Map<String, dynamic>>.from(item['prices'] ?? []),
        );
      case 'savings_ranking':
        return FeedSavingsCard(items: List<Map<String, dynamic>>.from(item['items'] ?? []));
      case 'community_challenge':
        return FeedCommunityCard(data: item);
      default:
        return const SizedBox.shrink();
    }
  }

  void _showSetArea(BuildContext context, MarkupState state) {
    final controller = TextEditingController(text: state.zipcode ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set your area'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter zip code'),
          keyboardType: TextInputType.number,
          maxLength: 5,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              state.setZipcode(controller.text.isEmpty ? null : controller.text);
              Navigator.pop(ctx);
              _loadFeed();
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showProfile(BuildContext context) {
    showProfileSheet(context);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

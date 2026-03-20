import 'package:flutter/material.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/widgets/top_level_navigation.dart';
import 'package:flutter_front_end/widgets/product_image.dart';
import 'package:provider/provider.dart';

class LabelJudgementPage extends StatefulWidget {
  const LabelJudgementPage({super.key});

  @override
  State<LabelJudgementPage> createState() => _LabelJudgementPageState();
}

class _LabelJudgementPageState extends State<LabelJudgementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<JudgementCandidate> _stapleCandidates = [];
  final List<JudgementCandidate> _groupingCandidates = [];
  int _stapleIndex = 0;
  int _groupingIndex = 0;
  int _stapleJudged = 0;
  int _groupingJudged = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stapleCandidates.isEmpty && _groupingCandidates.isEmpty && !_loading) {
      _loadCandidates('staple');
      _loadCandidates('grouping');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates(String type) async {
    final api = context.read<GroceryApi>();
    final userId = context.read<AppState>().currentUserId;
    if (userId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final candidates = await api.fetchJudgementCandidates(
        judgementType: type,
        userId: userId,
        count: 10,
      );
      if (!mounted) return;
      setState(() {
        if (type == 'staple') {
          _stapleCandidates.addAll(candidates);
        } else {
          _groupingCandidates.addAll(candidates);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _skipCandidate(String type) {
    setState(() {
      if (type == 'staple') {
        _stapleIndex++;
        if (_stapleIndex >= _stapleCandidates.length) {
          _stapleCandidates.clear();
          _stapleIndex = 0;
          _loadCandidates('staple');
        }
      } else {
        _groupingIndex++;
        if (_groupingIndex >= _groupingCandidates.length) {
          _groupingCandidates.clear();
          _groupingIndex = 0;
          _loadCandidates('grouping');
        }
      }
    });
  }

  Future<void> _submitJudgement({
    required JudgementCandidate candidate,
    required String type,
    required bool approved,
    String? flavour,
  }) async {
    final api = context.read<GroceryApi>();
    final userId = context.read<AppState>().currentUserId;
    if (userId == null) return;

    try {
      await api.submitJudgement(
        userId: userId,
        productId: candidate.productId,
        judgementType: type,
        approved: approved,
        targetProductId: candidate.targetProductId,
        stapleName: candidate.stapleName,
        flavour: flavour,
      );
    } catch (_) {
      // Best-effort; continue to next card even on failure.
    }

    if (!mounted) return;
    setState(() {
      if (type == 'staple') {
        _stapleJudged++;
        _stapleIndex++;
        if (_stapleIndex >= _stapleCandidates.length) {
          _stapleCandidates.clear();
          _stapleIndex = 0;
          _loadCandidates('staple');
        }
      } else {
        _groupingJudged++;
        _groupingIndex++;
        if (_groupingIndex >= _groupingCandidates.length) {
          _groupingCandidates.clear();
          _groupingIndex = 0;
          _loadCandidates('grouping');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Labels'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(
              icon: const Icon(Icons.star_outline),
              text: 'Staples ($_stapleJudged)',
            ),
            Tab(
              icon: const Icon(Icons.merge_type),
              text: 'Grouping ($_groupingJudged)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildJudgementView('staple'),
          _buildJudgementView('grouping'),
        ],
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: TopLevelNavigationBar(
          currentDestination: AppTopLevelDestination.staples,
        ),
      ),
    );
  }

  Widget _buildJudgementView(String type) {
    if (_loading &&
        (type == 'staple'
            ? _stapleCandidates.isEmpty
            : _groupingCandidates.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null &&
        (type == 'staple'
            ? _stapleCandidates.isEmpty
            : _groupingCandidates.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error loading candidates', style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _loadCandidates(type),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final candidates =
        type == 'staple' ? _stapleCandidates : _groupingCandidates;
    final index = type == 'staple' ? _stapleIndex : _groupingIndex;
    final judgedCount = type == 'staple' ? _stapleJudged : _groupingJudged;

    if (candidates.isEmpty || index >= candidates.length) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text('No more candidates right now!'),
            const SizedBox(height: 8),
            Text('You\'ve judged $judgedCount this session.',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadCandidates(type),
              child: const Text('Load more'),
            ),
          ],
        ),
      );
    }

    final candidate = candidates[index];

    if (type == 'staple') {
      return _StapleJudgementCard(
        candidate: candidate,
        onJudge: (approved) => _submitJudgement(
          candidate: candidate,
          type: 'staple',
          approved: approved,
        ),
        onSkip: () => _skipCandidate('staple'),
      );
    }

    return _GroupingJudgementCard(
      candidate: candidate,
      onJudge: (approved) => _submitJudgement(
        candidate: candidate,
        type: 'grouping',
        approved: approved,
      ),
      onFlavour: () => _submitJudgement(
        candidate: candidate,
        type: 'grouping',
        approved: true,
        flavour: 'flavour',
      ),
      onSkip: () => _skipCandidate('grouping'),
    );
  }
}

class _StapleJudgementCard extends StatelessWidget {
  const _StapleJudgementCard({
    required this.candidate,
    required this.onJudge,
    required this.onSkip,
  });

  final JudgementCandidate candidate;
  final void Function(bool approved) onJudge;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final displayName = candidate.stapleName != null
        ? candidate.stapleName![0].toUpperCase() +
            candidate.stapleName!.substring(1)
        : 'grocery staple';
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Is this $displayName?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              const SizedBox(height: 8),
              Text(
                'Should this product appear under "$displayName" in the staples screen?',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              if (candidate.heuristicScore != null &&
                  (candidate.heuristicScore! - 0.5).abs() < 0.05)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.help_outline,
                            size: 14, color: const Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        Text(
                          'We\'re unsure about this one',
                          style: TextStyle(
                              fontSize: 12, color: const Color(0xFF92400E)),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _ProductCard(
                name: candidate.productName,
                brand: candidate.productBrand,
                pictureUrl: candidate.productPictureUrl,
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 360;
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _JudgeButton(
                          icon: Icons.thumb_down_outlined,
                          label: 'Not a staple',
                          color: const Color(0xFF71717A),
                          onPressed: () => onJudge(false),
                        ),
                        const SizedBox(height: 8),
                        _JudgeButton(
                          icon: Icons.thumb_up_outlined,
                          label: 'Staple',
                          color: const Color(0xFF4F46E5),
                          onPressed: () => onJudge(true),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: _JudgeButton(
                          icon: Icons.thumb_down_outlined,
                          label: 'Not a staple',
                          color: const Color(0xFF71717A),
                          onPressed: () => onJudge(false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _JudgeButton(
                          icon: Icons.thumb_up_outlined,
                          label: 'Staple',
                          color: const Color(0xFF4F46E5),
                          onPressed: () => onJudge(true),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _JudgeButton(
                  icon: Icons.help_outline,
                  label: 'Unsure',
                  color: const Color(0xFFA1A1AA),
                  onPressed: onSkip,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _GroupingJudgementCard extends StatelessWidget {
  const _GroupingJudgementCard({
    required this.candidate,
    required this.onJudge,
    required this.onFlavour,
    required this.onSkip,
  });

  final JudgementCandidate candidate;
  final void Function(bool approved) onJudge;
  final VoidCallback onFlavour;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Are these the same product?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Would you consider these interchangeable?',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (compact)
                      Column(
                        children: [
                          _ProductCard(
                            name: candidate.productName,
                            brand: candidate.productBrand,
                            pictureUrl: candidate.productPictureUrl,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Icon(
                              Icons.compare_arrows,
                              size: 32,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          _ProductCard(
                            name: candidate.targetProductName ?? '',
                            brand: candidate.targetProductBrand ?? '',
                            pictureUrl: candidate.targetProductPictureUrl ?? '',
                          ),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ProductCard(
                              name: candidate.productName,
                              brand: candidate.productBrand,
                              pictureUrl: candidate.productPictureUrl,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
                            child: Icon(
                              Icons.compare_arrows,
                              size: 32,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          Expanded(
                            child: _ProductCard(
                              name: candidate.targetProductName ?? '',
                              brand: candidate.targetProductBrand ?? '',
                              pictureUrl: candidate.targetProductPictureUrl ?? '',
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 32),
                    if (compact) ...[
                      SizedBox(
                        width: double.infinity,
                        child: _JudgeButton(
                          icon: Icons.close,
                          label: 'Different',
                          color: const Color(0xFF71717A),
                          onPressed: () => onJudge(false),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: _JudgeButton(
                          icon: Icons.check,
                          label: 'Same product',
                          color: const Color(0xFF4F46E5),
                          onPressed: () => onJudge(true),
                        ),
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: _JudgeButton(
                              icon: Icons.close,
                              label: 'Different',
                              color: const Color(0xFF71717A),
                              onPressed: () => onJudge(false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _JudgeButton(
                              icon: Icons.check,
                              label: 'Same product',
                              color: const Color(0xFF4F46E5),
                              onPressed: () => onJudge(true),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (compact) ...[
                      SizedBox(
                        width: double.infinity,
                        child: _JudgeButton(
                          icon: Icons.style_outlined,
                          label: 'Flavor / Variation',
                          color: const Color(0xFFD97706),
                          onPressed: onFlavour,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: _JudgeButton(
                          icon: Icons.help_outline,
                          label: 'Unsure',
                          color: const Color(0xFFA1A1AA),
                          onPressed: onSkip,
                        ),
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: _JudgeButton(
                              icon: Icons.style_outlined,
                              label: 'Flavor / Variation',
                              color: const Color(0xFFD97706),
                              onPressed: onFlavour,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _JudgeButton(
                              icon: Icons.help_outline,
                              label: 'Unsure',
                              color: const Color(0xFFA1A1AA),
                              onPressed: onSkip,
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.name,
    required this.brand,
    required this.pictureUrl,
  });

  final String name;
  final String brand;
  final String pictureUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ProductImage(
                url: pictureUrl,
                width: 120,
                height: 120,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (brand.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                brand,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JudgeButton extends StatelessWidget {
  const _JudgeButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

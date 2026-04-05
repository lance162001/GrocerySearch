import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/models/grocery_models.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/config/markup_theme.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/widgets/challenge_card.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  JudgementCandidate? _matchChallenge;
  JudgementCandidate? _stapleChallenge;
  bool _loadingMatch = false;
  bool _loadingStaple = false;
  int _answeredCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMatchChallenge();
      _loadStapleChallenge();
      _loadPoints();
    });
  }

  Future<void> _loadPoints() async {
    final state = context.read<MarkupState>();
    if (state.currentUserId == null) return;
    try {
      final resp = await state.api.fetchPoints(state.currentUserId!);
      if (!mounted) return;
      final serverPoints = resp['points'] as int? ?? 0;
      if (serverPoints > state.points) {
        state.addPoints(serverPoints - state.points);
      }
    } catch (_) {}
  }

  Future<void> _loadMatchChallenge() async {
    setState(() => _loadingMatch = true);
    final state = context.read<MarkupState>();
    try {
      final candidates = await state.api.fetchJudgementCandidates(
        judgementType: 'grouping',
        userId: state.currentUserId ?? 0,
        count: 1,
      );
      if (!mounted) return;
      setState(() {
        _matchChallenge = candidates.isNotEmpty ? candidates.first : null;
        _loadingMatch = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMatch = false);
    }
  }

  Future<void> _loadStapleChallenge() async {
    setState(() => _loadingStaple = true);
    final state = context.read<MarkupState>();
    try {
      final candidates = await state.api.fetchJudgementCandidates(
        judgementType: 'staple',
        userId: state.currentUserId ?? 0,
        count: 1,
      );
      if (!mounted) return;
      setState(() {
        _stapleChallenge = candidates.isNotEmpty ? candidates.first : null;
        _loadingStaple = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStaple = false);
    }
  }

  Future<void> _submitMatchJudgement(bool approved) async {
    final challenge = _matchChallenge;
    if (challenge == null) return;
    final state = context.read<MarkupState>();
    try {
      await state.api.submitJudgement(
        userId: state.currentUserId ?? 0,
        productId: challenge.productId,
        judgementType: 'grouping',
        targetProductId: challenge.targetProductId,
        approved: approved,
      );
      state.addPoints(5);
      setState(() => _answeredCount++);
    } catch (_) {}
    if (mounted) _loadMatchChallenge();
  }

  Future<void> _submitStapleJudgement(bool approved) async {
    final challenge = _stapleChallenge;
    if (challenge == null) return;
    final state = context.read<MarkupState>();
    try {
      await state.api.submitJudgement(
        userId: state.currentUserId ?? 0,
        productId: challenge.productId,
        judgementType: 'staple',
        stapleName: challenge.stapleName,
        approved: approved,
      );
      state.addPoints(3);
      setState(() => _answeredCount++);
    } catch (_) {}
    if (mounted) _loadStapleChallenge();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MarkupState>();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(child: Text('Play', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.star, size: 16, color: MarkupColors.darkGreen),
                    const SizedBox(width: 4),
                    Text('${state.points} pts', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                  ]),
                ),
              ],
            ),
          ),
          // Daily Price Guess game
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.game),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [MarkupColors.darkGreen, MarkupColors.mediumGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🎯 Daily Price Guess', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                        SizedBox(height: 4),
                        Text('Guess which store has the better price to earn bonus points', style: TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Challenges section label
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('CHALLENGES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1)),
          ),
          // Product Match challenge
          if (_loadingMatch)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: MarkupColors.darkGreen)))
          else if (_matchChallenge != null)
            ChallengeCard(
              type: ChallengeType.productMatch,
              points: 5,
              productName: _matchChallenge!.productName,
              productBrand: _matchChallenge!.productBrand,
              targetProductName: _matchChallenge!.targetProductName,
              targetProductBrand: _matchChallenge!.targetProductBrand,
              onAnswer: _submitMatchJudgement,
              onSkip: _loadMatchChallenge,
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('No product match challenges available right now.', style: TextStyle(color: MarkupColors.textSecondary)),
            ),
          // Staple Check challenge
          if (_loadingStaple)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: MarkupColors.darkGreen)))
          else if (_stapleChallenge != null)
            ChallengeCard(
              type: ChallengeType.stapleCheck,
              points: 3,
              productName: _stapleChallenge!.productName,
              productBrand: _stapleChallenge!.productBrand,
              stapleName: _stapleChallenge!.stapleName,
              onAnswer: _submitStapleJudgement,
              onSkip: _loadStapleChallenge,
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('No staple check challenges available right now.', style: TextStyle(color: MarkupColors.textSecondary)),
            ),
          // Your Impact stats
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR IMPACT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statBlock('$_answeredCount', 'this session'),
                    _statBlock('${state.points}', 'total pts'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBlock(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
        Text(label, style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
      ],
    );
  }
}

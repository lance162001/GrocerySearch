// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_front_end/models/game_models.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/widgets/product_image.dart';

// dart:html is web-only; guarded by kIsWeb at every call site.
// ignore: uri_does_not_exist
import 'dart:html' as html;

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const int _maxGuesses = 8;

  // Game state
  late String _gameDate;
  final List<GuessResult> _guesses = [];
  bool _isComplete = false;
  bool _isWon = false;
  bool _animateLatest = false;

  // Infinite mode
  int _infiniteRound = 0; // 0 = daily; 1+ = bonus rounds

  // Search / staging
  GameProduct? _stagedGuess;
  String? _knownCompany;

  // Submission
  bool _submitting = false;

  // Post-game reveal
  RevealResult? _revealResult;

  // Confetti
  late final ConfettiController _confettiController;

  // Streak (daily mode only)
  int _streak = 0;
  int _maxStreak = 0;

  // Hint
  bool _hintUsed = false;
  GameHint? _hintResult;
  bool _fetchingHint = false;

  @override
  void initState() {
    super.initState();
    _gameDate = DateTime.now().toLocal().toIso8601String().substring(0, 10);
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));
    _loadLocalState();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  // ── localStorage helpers ───────────────────────────────────────────────────

  String get _storageKey => 'grocerywordle_$_gameDate';
  static const String _streakKey = 'grocerywordle_streak';
  static const String _maxStreakKey = 'grocerywordle_max_streak';
  static const String _lastPlayedKey = 'grocerywordle_last_played';
  String get _hintStorageKey => 'grocerywordle_hint_$_gameDate';

  void _loadLocalState() {
    if (!kIsWeb) return;
    try {
      // Load streak
      _streak =
          int.tryParse(html.window.localStorage[_streakKey] ?? '') ?? 0;
      _maxStreak =
          int.tryParse(html.window.localStorage[_maxStreakKey] ?? '') ?? 0;

      // Load hint state for today's daily game
      final hintRaw = html.window.localStorage[_hintStorageKey];
      if (hintRaw != null && hintRaw.isNotEmpty) {
        _hintUsed = true;
        _hintResult = GameHint.fromJson(
            jsonDecode(hintRaw) as Map<String, dynamic>);
      }

      // Load game state
      final raw = html.window.localStorage[_storageKey];
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final saved = (data['guesses'] as List<dynamic>)
          .map((g) => GuessResult.fromJson(
              Map<String, dynamic>.from(g as Map)))
          .toList();
      setState(() {
        _guesses.addAll(saved);
        _isComplete = data['is_complete'] as bool? ?? false;
        _isWon = data['is_won'] as bool? ?? false;
        _knownCompany = _findKnownCompany();
      });
      if (_isComplete) _fetchReveal();
    } catch (_) {
      // Ignore corrupt/missing storage
    }
  }

  void _saveLocalState() {
    if (!kIsWeb || _infiniteRound > 0) return;
    try {
      html.window.localStorage[_storageKey] = jsonEncode({
        'guesses': _guesses.map((g) => g.toJson()).toList(),
        'is_complete': _isComplete,
        'is_won': _isWon,
      });
    } catch (_) {}
  }

  void _updateStreak() {
    if (!kIsWeb || _infiniteRound > 0) return;
    try {
      final lastPlayed = html.window.localStorage[_lastPlayedKey];
      final yesterday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toLocal()
          .toIso8601String()
          .substring(0, 10);

      int newStreak;
      if (_isWon) {
        if (lastPlayed == _gameDate) {
          // Already counted today (shouldn't normally happen)
          newStreak = _streak;
        } else if (lastPlayed == yesterday) {
          // Continue streak
          newStreak = _streak + 1;
        } else {
          // Gap in play — start fresh
          newStreak = 1;
        }
      } else {
        newStreak = 0;
      }

      final newMax = newStreak > _maxStreak ? newStreak : _maxStreak;
      html.window.localStorage[_streakKey] = '$newStreak';
      html.window.localStorage[_maxStreakKey] = '$newMax';
      html.window.localStorage[_lastPlayedKey] = _gameDate;
      setState(() {
        _streak = newStreak;
        _maxStreak = newMax;
      });
    } catch (_) {}
  }

  String? _findKnownCompany() {
    for (final g in _guesses) {
      for (final attr in g.attributes) {
        if (attr.key == 'company' && attr.match == AttributeMatch.exact) {
          return g.guess.companyName;
        }
      }
    }
    return null;
  }

  // ── search ─────────────────────────────────────────────────────────────────

  void _stageProduct(GameProduct product) {
    setState(() => _stagedGuess = product);
  }

  void _clearStaged() => setState(() => _stagedGuess = null);

  // ── guess submission ───────────────────────────────────────────────────────

  Future<void> _submitGuess() async {
    final staged = _stagedGuess;
    if (staged == null || _submitting || _isComplete) return;
    setState(() => _submitting = true);
    try {
      final result = await context.read<GroceryApi>().submitGameGuess(
            productId: staged.id,
            gameDate: _gameDate,
            round: _infiniteRound,
          );
      if (!mounted) return;
      setState(() {
        _guesses.insert(0, result);
        _stagedGuess = null;
        _animateLatest = true;
        _knownCompany ??= _findKnownCompany();
        if (result.isCorrect) {
          _isWon = true;
          _isComplete = true;
        } else if (_guesses.length >= _maxGuesses) {
          _isComplete = true;
        }
        _submitting = false;
      });
      _saveLocalState();
      if (_isComplete) {
        _updateStreak();
        _fetchReveal();
        if (_isWon) {
          // Delay confetti until after tiles have flipped
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted) _confettiController.play();
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }

  Future<void> _fetchReveal() async {
    try {
      final reveal = await context
          .read<GroceryApi>()
          .revealDailyAnswer(_gameDate, round: _infiniteRound);
      if (!mounted) return;
      setState(() => _revealResult = reveal);
    } catch (_) {}
  }

  Future<void> _useHint() async {
    if (_hintUsed || _fetchingHint) return;
    setState(() => _fetchingHint = true);
    try {
      final hint = await context
          .read<GroceryApi>()
          .getGameHint(_gameDate, round: _infiniteRound);
      if (!mounted) return;
      if (kIsWeb && _infiniteRound == 0) {
        html.window.localStorage[_hintStorageKey] =
            jsonEncode(hint.toJson());
      }
      setState(() {
        _hintUsed = true;
        _hintResult = hint;
        _fetchingHint = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _fetchingHint = false);
    }
  }

  void _startInfinite() {
    setState(() {
      _infiniteRound += 1;
      _guesses.clear();
      _isComplete = false;
      _isWon = false;
      _stagedGuess = null;
      _revealResult = null;
      _knownCompany = null;
      _animateLatest = false;
      _hintUsed = false;
      _hintResult = null;
    });
  }

  void _shareResults() {
    final guessCount =
        _isWon ? '${_guesses.length}/$_maxGuesses' : 'X/$_maxGuesses';
    final label = _infiniteRound > 0
        ? 'Grocery Wordle ♾️ Round $_infiniteRound'
        : 'Grocery Wordle $_gameDate';
    final buf = StringBuffer('$label\n$guessCount\n\n');
    for (final g in _guesses.reversed) {
      for (final attr in g.attributes) {
        buf.write(switch (attr.match) {
          AttributeMatch.exact => '🟩',
          AttributeMatch.close => '🟨',
          AttributeMatch.none => '⬛',
        });
      }
      buf.write('\n');
    }
    final text = buf.toString().trimRight();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF1b4332),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1b4332),
            foregroundColor: Colors.white,
            title: const Text(
              'Grocery Wordle',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              if (_infiniteRound == 0 && (_streak > 0 || _maxStreak > 0))
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '🔥 $_streak',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      if (_maxStreak > 1)
                        Text(
                          'best $_maxStreak',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white70),
                        ),
                    ],
                  ),
                ),
            ],
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          backgroundColor: const Color(0xFFFAFAFA),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInstructions(),
                  const SizedBox(height: 12),
                  _buildGuessCounter(),
                  const SizedBox(height: 12),
                  if (!_isComplete) ...[
                    _buildHintSection(),
                    _buildSearchSection(),
                    const SizedBox(height: 12),
                  ],
                  _buildGuessHistory(),
                  if (_isComplete) ...[
                    const SizedBox(height: 16),
                    _buildGameOverSection(),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
        // Confetti overlay — sits above everything
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [
              Color(0xFF1b4332),
              Color(0xFF52B788),
              Color(0xFFF59E0B),
              Colors.white,
              Color(0xFFD8F3DC),
            ],
            numberOfParticles: 30,
            gravity: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFDCE8DC)),
      ),
      child: ExpansionTile(
        title: const Text(
          'How to Play',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: const [
          Text(
            'Search for a grocery product and submit a guess. Each guess reveals how it compares to today\'s mystery product across eight attributes:\n\n'
            '  Store · Category · Price · Amount · Unit · Staple · Brand · Name\n\n'
            '🟩  Green  — exact match\n'
            '🟨  Yellow — price or size within range (↑↓ shows direction)\n'
            '⬛  Gray   — no match\n\n'
            'You have 8 guesses. After 3 guesses, a hint becomes available. Complete the daily game to unlock Infinite Mode!',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildGuessCounter() {
    final remaining = _maxGuesses - _guesses.length;
    String text;
    Color color;
    if (_isWon) {
      text = 'Solved in ${_guesses.length} / $_maxGuesses '
          '${_guesses.length == 1 ? "guess" : "guesses"}! 🎉';
      color = const Color(0xFF1b4332);
    } else if (_isComplete) {
      text = 'Game over — all $_maxGuesses guesses used';
      color = const Color(0xFF71717A);
    } else {
      text = '$remaining ${remaining == 1 ? "guess" : "guesses"} remaining';
      color = Colors.black87;
    }
    return Column(
      children: [
        if (_infiniteRound > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '♾️ Infinite Mode — Round $_infiniteRound',
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1b4332),
                  fontWeight: FontWeight.w500),
            ),
          ),
        Text(
          text,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 14, color: color),
        ),
      ],
    );
  }

  Widget _buildHintSection() {
    // Hints only in daily mode
    if (_infiniteRound > 0) return const SizedBox.shrink();

    if (_hintResult != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFF59E0B), width: 1.2),
          ),
          child: Row(
            children: [
              const Text('💡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hint: ${_hintResult!.label} is "${_hintResult!.value}"',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_guesses.length >= 3 && !_hintUsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextButton.icon(
          onPressed: _fetchingHint ? null : _useHint,
          icon: _fetchingHint
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFF59E0B)),
                )
              : const Text('💡', style: TextStyle(fontSize: 14)),
          label: const Text('Get a Hint'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF92400E),
            backgroundColor: const Color(0xFFFFF8E1),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFF59E0B)),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_stagedGuess != null) ...[
          _buildStagedProduct(_stagedGuess!),
        ] else ...[
          if (_knownCompany != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt,
                      size: 14, color: Color(0xFF1b4332)),
                  const SizedBox(width: 4),
                  Text(
                    'Filtering by $_knownCompany',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1b4332),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          Autocomplete<GameProduct>(
            displayStringForOption: (p) => p.name,
            optionsBuilder: (textEditingValue) async {
              final q = textEditingValue.text.trim();
              if (q.length < 2) return [];
              final guessedIds =
                  _guesses.map((g) => g.guess.id).toSet();
              try {
                final results = await context
                    .read<GroceryApi>()
                    .gameSearch(q,
                        limit: 8, companyName: _knownCompany);
                return results
                    .where((p) => !guessedIds.contains(p.id));
              } catch (_) {
                return [];
              }
            },
            onSelected: _stageProduct,
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'Search for a product to guess…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFD4D4D8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFD4D4D8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: Color(0xFF1b4332), width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, color: Color(0xFFDCE8DC)),
                      itemBuilder: (context, i) {
                        final p = options.elementAt(i);
                        return ListTile(
                          dense: true,
                          leading: ProductImage(
                            url: p.pictureUrl,
                            width: 36,
                            height: 36,
                          ),
                          title: Text(p.name,
                              style:
                                  const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${p.brand} · ${p.companyName}',
                            style:
                                const TextStyle(fontSize: 11),
                          ),
                          onTap: () => onSelected(p),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: _stagedGuess != null && !_submitting
                ? _submitGuess
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1b4332),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF1b4332).withOpacity(0.35),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Guess',
                    style:
                        TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildStagedProduct(GameProduct p) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF1b4332), width: 1.5),
      ),
      child: ListTile(
        leading: ProductImage(
          url: p.pictureUrl,
          width: 40,
          height: 40,
        ),
        title: Text(
          p.name,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${p.brand} · ${p.companyName}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _clearStaged,
          tooltip: 'Clear',
        ),
      ),
    );
  }

  Widget _buildGuessHistory() {
    if (_guesses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No guesses yet — search for a product above!',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _guesses.length; i++) ...[
          _GuessRow(
            key: ValueKey(_guesses[i].guess.id),
            guess: _guesses[i],
            animate: i == 0 && _animateLatest,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildGameOverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color:
              _isWon ? const Color(0xFFE9F7EE) : const Color(0xFFF5F5F5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: _isWon
                  ? const Color(0xFF1b4332).withOpacity(0.3)
                  : const Color(0xFFD4D4D8),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _isWon
                      ? '🎉  You got it! Well done!'
                      : '😔  Better luck tomorrow!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _isWon
                        ? const Color(0xFF1b4332)
                        : const Color(0xFF71717A),
                  ),
                ),
                if (_isWon && _streak > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    '🔥 $_streak day streak!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1b4332),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareResults,
                icon: const Text('📤', style: TextStyle(fontSize: 16)),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1b4332),
                  side: const BorderSide(color: Color(0xFF1b4332)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startInfinite,
                icon: const Text('♾️', style: TextStyle(fontSize: 16)),
                label: const Text('Infinite Mode'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1b4332),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_revealResult != null)
          _RevealCard(reveal: _revealResult!)
        else
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(
                  color: Color(0xFF1b4332)),
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Guess row widget (with flip animations)
// ────────────────────────────────────────────────────────────────────────────

class _GuessRow extends StatefulWidget {
  const _GuessRow({super.key, required this.guess, this.animate = false});

  final GuessResult guess;
  final bool animate;

  @override
  State<_GuessRow> createState() => _GuessRowState();
}

class _GuessRowState extends State<_GuessRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _warmthFade;

  // Each tile flips sequentially: stagger of 100ms, flip duration 180ms.
  static const int _staggerMs = 100;
  static const int _flipMs = 180;

  late final int _numAttrs;
  late final int _totalMs;

  @override
  void initState() {
    super.initState();
    _numAttrs = widget.guess.attributes.length;
    // Total = last start + flip duration
    _totalMs =
        (_numAttrs > 1 ? (_numAttrs - 1) * _staggerMs : 0) + _flipMs;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
    );

    if (widget.animate) {
      // Warmth bar fades in during the last 8% of the animation
      _warmthFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.92, 1.0, curve: Curves.easeIn),
        ),
      );
      _controller.forward();
    } else {
      _warmthFade = const AlwaysStoppedAnimation(1.0);
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFDCE8DC)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product header
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ProductImage(
                  url: widget.guess.guess.pictureUrl,
                  width: 44,
                  height: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.guess.guess.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.guess.guess.brand} · ${widget.guess.guess.companyName}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF71717A)),
                      ),
                    ],
                  ),
                ),
                if (widget.guess.isCorrect)
                  const Icon(Icons.check_circle,
                      color: Color(0xFF1b4332), size: 20),
              ],
            ),
            const SizedBox(height: 8),
            // Animated attribute tiles
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final elapsed = _controller.value * _totalMs;
                return Row(
                  children: List.generate(
                    _numAttrs,
                    (i) {
                      final startMs = i * _staggerMs.toDouble();
                      final midMs = startMs + _flipMs / 2.0;
                      final endMs = startMs + _flipMs.toDouble();

                      double scaleX;
                      bool revealed;
                      if (elapsed <= startMs) {
                        scaleX = 1.0;
                        revealed = false;
                      } else if (elapsed <= midMs) {
                        scaleX =
                            1.0 - (elapsed - startMs) / (midMs - startMs);
                        revealed = false;
                      } else if (elapsed <= endMs) {
                        scaleX =
                            (elapsed - midMs) / (endMs - midMs);
                        revealed = true;
                      } else {
                        scaleX = 1.0;
                        revealed = true;
                      }

                      final attr = widget.guess.attributes[i];
                      return Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Transform(
                            alignment: Alignment.center,
                            transform:
                                Matrix4.identity()..scale(scaleX, 1.0),
                            child: revealed
                                ? _AttributeTile(attribute: attr)
                                : const _BlankTile(),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            // Warmth score — fades in after all tiles flip
            FadeTransition(
              opacity: _warmthFade,
              child: _WarmthBar(attributes: widget.guess.attributes),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Warmth bar — shows exact/close counts below tiles
// ────────────────────────────────────────────────────────────────────────────

class _WarmthBar extends StatelessWidget {
  const _WarmthBar({required this.attributes});

  final List<AttributeResult> attributes;

  @override
  Widget build(BuildContext context) {
    final exact =
        attributes.where((a) => a.match == AttributeMatch.exact).length;
    final close =
        attributes.where((a) => a.match == AttributeMatch.close).length;
    final n = attributes.length;
    if (exact == 0 && close == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (exact > 0) ...[
            _dot(const Color(0xFF1b4332)),
            const SizedBox(width: 3),
            Text(
              '$exact/$n exact',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF1b4332),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (close > 0) const SizedBox(width: 8),
          ],
          if (close > 0) ...[
            _dot(const Color(0xFFF59E0B)),
            const SizedBox(width: 3),
            Text(
              '$close/$n close',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFF59E0B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ────────────────────────────────────────────────────────────────────────────
// Blank tile — shown on the un-flipped side
// ────────────────────────────────────────────────────────────────────────────

class _BlankTile extends StatelessWidget {
  const _BlankTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFE4E4E7),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Attribute tile widget
// ────────────────────────────────────────────────────────────────────────────

class _AttributeTile extends StatelessWidget {
  const _AttributeTile({required this.attribute});

  final AttributeResult attribute;

  static const Color _colorExact = Color(0xFF1b4332);
  static const Color _colorClose = Color(0xFFF59E0B);
  static const Color _colorNone = Color(0xFF71717A);

  static const Map<String, String> _shortLabels = {
    'company': 'Store',
    'category': 'Category',
    'price': 'Price',
    'size_value': 'Amount',
    'size_unit': 'Unit',
    'staple': 'Staple',
    'brand': 'Brand',
    'name': 'Name',
  };

  Color get _bgColor => switch (attribute.match) {
        AttributeMatch.exact => _colorExact,
        AttributeMatch.close => _colorClose,
        AttributeMatch.none => _colorNone,
      };

  String get _valueText {
    String v = attribute.value;
    if ((attribute.key == 'price' || attribute.key == 'size_value') &&
        attribute.direction != null) {
      v += attribute.direction == PriceDirection.higher ? ' ↑' : ' ↓';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _shortLabels[attribute.key] ?? attribute.label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 7,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
          const SizedBox(height: 3),
          Text(
            _valueText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Reveal card (shown after game over)
// ────────────────────────────────────────────────────────────────────────────

class _RevealCard extends StatelessWidget {
  const _RevealCard({required this.reveal});

  final RevealResult reveal;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFDCE8DC)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Today's Product",
              style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF71717A),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            ProductImage(
              url: reveal.product.pictureUrl,
              width: 110,
              height: 110,
            ),
            const SizedBox(height: 12),
            Text(
              reveal.product.name,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '${reveal.product.brand} · ${reveal.product.companyName}',
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF71717A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                if (reveal.category != null)
                  _chip(reveal.category!),
                if (reveal.stapleName != null)
                  _chip('staple: ${reveal.stapleName!}'),
                _chip(reveal.price),
                if (reveal.sizeUnit != null)
                  _chip(reveal.sizeUnit!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F7EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF1b4332).withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF1b4332),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';

/// The four things the app is.
enum ElevarTab {
  play('PLAY', Icons.sports_esports_rounded),
  board('BOARD', Icons.leaderboard_rounded),
  shop('SHOP', Icons.redeem_rounded),
  you('YOU', Icons.person_rounded);

  const ElevarTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The app shell.
///
/// The hub used to be a single scrolling page with the rewards catalogue
/// hanging off the bottom of it. That was fine with three games and one thing
/// to spend points on; it stopped being fine the moment there was a
/// leaderboard, because a leaderboard buried under a fold is a leaderboard
/// nobody competes on — and competing is the entire reason it exists.
///
/// Four tabs, and each one answers a different question a player actually has:
/// *what can I play*, *where am I*, *what is this worth*, *who am I on the
/// board*.
class ElevarShell extends StatefulWidget {
  const ElevarShell({super.key});

  @override
  State<ElevarShell> createState() => _ElevarShellState();
}

class _ElevarShellState extends State<ElevarShell> {
  ElevarTab _tab = ElevarTab.play;

  /// Bumped when a tab is re-entered, so the page under it refreshes.
  ///
  /// Points are earned on a screen pushed *over* this one, so coming back to
  /// a tab is exactly when its numbers are wrong. Cheaper and more reliable
  /// than a state-management layer for four pages that each read a database
  /// once.
  int _revision = 0;

  void _select(ElevarTab tab) {
    setState(() {
      _tab = tab;
      _revision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_tab) {
        ElevarTab.play => HomeScreen(
            key: ValueKey<int>(_revision),
            onSeeLeaderboard: () => _select(ElevarTab.board),
            onSpendPoints: () => _select(ElevarTab.shop),
          ),
        ElevarTab.board => LeaderboardScreen(key: ValueKey<int>(_revision)),
        ElevarTab.shop =>
          RewardsScreen(key: ValueKey<int>(_revision), embedded: true),
        ElevarTab.you => ProfileScreen(key: ValueKey<int>(_revision)),
      },
      bottomNavigationBar: _TabBar(current: _tab, onSelect: _select),
    );
  }
}

/// The bar.
///
/// Hand-built rather than a `NavigationBar`, because Material 3's bar brings
/// its own elevation, ripple and indicator pill, and mixing those into a
/// design whose whole character is flat ink outlines and hard offset shadows
/// reads immediately as two apps stitched together.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final ElevarTab current;
  final ValueChanged<ElevarTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ElevarColors.surfaceRaised,
        border: Border(
          top: BorderSide(color: ElevarColors.ink, width: 3),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: <Widget>[
              for (final tab in ElevarTab.values)
                Expanded(
                  child: _TabButton(
                    tab: tab,
                    selected: tab == current,
                    onTap: () => onSelect(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final ElevarTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? ElevarColors.ball : ElevarColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? ElevarColors.ball.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(tab.icon, color: colour, size: 22),
              const SizedBox(height: 3),
              Text(tab.label, style: ElevarType.label(9, color: colour)),
            ],
          ),
        ),
      ),
    );
  }
}

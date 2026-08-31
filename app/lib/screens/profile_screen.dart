import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../data/player_profile.dart';
import '../data/points_repository.dart';
import '../data/profile_repository.dart';
import '../games/registry.dart';
import 'format.dart';

/// Who you are on the board, and what you have done.
///
/// The name and the avatar are editable here and nowhere else. There is
/// deliberately no sign-up: Elevar has no account server yet, and putting a
/// registration wall in front of a game is the most reliable way to lose
/// somebody who arrived from an Instagram link. The player id underneath is
/// what a real account will later be attached to, so nothing earned before
/// signing in is lost when they do.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  PlayerProfile? _profile;
  int _lifetime = 0;
  int _balance = 0;
  int _streak = 0;
  List<GameStat> _stats = const <GameStat>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await profileRepository.profile();
    final lifetime = await pointsRepository.lifetimePoints();
    final balance = await pointsRepository.balance();
    final today = await pointsRepository.todaySoFar();
    final stats = await pointsRepository.perGameStats();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _lifetime = lifetime;
      _balance = balance;
      _streak = today.streakDays;
      _stats = stats;
    });
  }

  Future<void> _pickAvatar(int index) async {
    final updated = await profileRepository.updateProfile(avatarIndex: index);
    if (!mounted) return;
    setState(() => _profile = updated);
  }

  Future<void> _editName() async {
    final current = _profile;
    if (current == null) return;

    final controller = TextEditingController(
      text: current.hasDefaultName ? '' : current.displayName,
    );
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(controller: controller),
    );
    if (chosen == null) return;

    final updated = await profileRepository.updateProfile(displayName: chosen);
    if (!mounted) return;
    setState(() => _profile = updated);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final avatar = profile == null
        ? PlayerAvatars.all.first
        : PlayerAvatars.at(profile.avatarIndex);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: <Widget>[
          Text('YOUR PROFILE', style: ElevarType.display(30)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: avatar.colour,
                shape: BoxShape.circle,
                border: Border.all(color: ElevarColors.ink, width: 5),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
                ],
              ),
              child: Text(avatar.emoji, style: const TextStyle(fontSize: 42)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _editName,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      profile?.displayName ?? '…',
                      style: ElevarType.display(26),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: ElevarColors.muted,
                  ),
                ],
              ),
            ),
          ),
          if (profile != null && profile.hasDefaultName) ...<Widget>[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Pick a name — it is what shows on the leaderboard.',
                textAlign: TextAlign.center,
                style: ElevarType.body(13, color: ElevarColors.muted),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text('AVATAR', style: ElevarType.label(10)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (var i = 0; i < PlayerAvatars.all.length; i++)
                _AvatarChoice(
                  avatar: PlayerAvatars.all[i],
                  selected: profile?.avatarIndex == i,
                  onTap: () => _pickAvatar(i),
                ),
            ],
          ),
          const SizedBox(height: 26),
          Text('TOTALS', style: ElevarType.label(10)),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _StatBox(
                  label: 'EP EARNED',
                  value: groupedNumber(_lifetime),
                  colour: ElevarColors.ball,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'EP TO SPEND',
                  value: groupedNumber(_balance),
                  colour: ElevarColors.table,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'DAY STREAK',
                  value: '$_streak',
                  colour: ElevarColors.p1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text('BY GAME', style: ElevarType.label(10)),
          const SizedBox(height: 10),
          if (_stats.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: ElevarColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ElevarColors.ink, width: 3),
              ),
              child: Text(
                'Nothing played yet. Every match lands here.',
                style: ElevarType.body(14, color: ElevarColors.muted),
              ),
            )
          else
            for (final stat in _stats)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GameStatRow(stat: stat),
              ),
          const SizedBox(height: 24),
          if (profile != null)
            Center(
              child: Text(
                'PLAYER ID · ${profile.playerId.substring(0, 8)}',
                style: ElevarType.label(9),
              ),
            ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatelessWidget {
  const _NameDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ElevarColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: ElevarColors.ink, width: 3),
      ),
      title: Text('YOUR NAME', style: ElevarType.display(20)),
      content: TextField(
        controller: controller,
        autofocus: true,
        // Capped here as well as in the repository. The repository's limit is
        // the one that binds — this only stops the field from looking as
        // though a longer name would be accepted.
        maxLength: 18,
        textCapitalization: TextCapitalization.words,
        style: ElevarType.body(16),
        decoration: InputDecoration(
          hintText: 'Pick something',
          hintStyle: ElevarType.body(16, color: ElevarColors.muted),
          counterStyle: ElevarType.label(9),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: ElevarColors.muted, width: 2),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: ElevarColors.table, width: 2),
          ),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: ElevarType.label(11)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(
            'SAVE',
            style: ElevarType.label(11, color: ElevarColors.table),
          ),
        ),
      ],
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  final PlayerAvatar avatar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: avatar.colour.withValues(alpha: selected ? 1 : 0.35),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? ElevarColors.white : ElevarColors.ink,
            width: selected ? 4 : 3,
          ),
        ),
        child: Text(avatar.emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.colour,
  });

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Column(
        children: <Widget>[
          FittedBox(
            child: Text(value, style: ElevarType.display(22, color: colour)),
          ),
          const SizedBox(height: 4),
          FittedBox(child: Text(label, style: ElevarType.label(8))),
        ],
      ),
    );
  }
}

class _GameStatRow extends StatelessWidget {
  const _GameStatRow({required this.stat});

  final GameStat stat;

  /// The registry is the only place that knows a slug's colour and name, so a
  /// stat row for a game this build has never heard of still renders — which
  /// matters the moment the server starts returning history from a newer
  /// version of the app than the one installed.
  @override
  Widget build(BuildContext context) {
    final game = elevarGames.where((g) => g.slug == stat.slug).firstOrNull;
    final title = game?.title.replaceAll('\n', ' ') ??
        stat.slug.replaceAll('_', ' ').toUpperCase();
    final colour = game?.accent ?? ElevarColors.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ElevarColors.ink, width: 2),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 12,
            height: 34,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ElevarColors.ink, width: 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: ElevarType.display(15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${stat.played} played · ${stat.won} won',
                  style: ElevarType.body(12, color: ElevarColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            groupedNumber(stat.points),
            style: ElevarType.display(16, color: ElevarColors.ball),
          ),
        ],
      ),
    );
  }
}

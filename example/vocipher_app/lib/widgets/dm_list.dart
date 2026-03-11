import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';
import 'user_avatar.dart';

/// Discord DM sidebar shown when "Home" is selected in the server sidebar.
class DmList extends StatelessWidget {
  const DmList({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SpacetimeDbService>();
    final conversations = service.dmConversations;

    return Container(
      color: DiscordColors.channelSidebarBg,
      child: Column(
        children: [
          // Search bar placeholder
          _SearchBar(),

          // Quick-action items
          _QuickActionItem(
            icon: Icons.people,
            label: 'Friends',
            onTap: () {},
          ),
          _QuickActionItem(
            icon: Icons.diamond_outlined,
            label: 'Nitro',
            onTap: () {},
          ),

          // Divider
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: DiscordColors.divider,
            ),
          ),

          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    'DIRECT MESSAGES',
                    style: TextStyle(
                      color: DiscordColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.02,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // DM conversation list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final identity = conversations[index];
                return _DmItem(
                  identity: identity,
                  service: service,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search bar placeholder
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: DiscordColors.backgroundDarkest,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: const Text(
          'Find or start a conversation',
          style: TextStyle(
            color: DiscordColors.textMuted,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-action items (Friends, Nitro)
// ---------------------------------------------------------------------------

class _QuickActionItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_QuickActionItem> createState() => _QuickActionItemState();
}

class _QuickActionItemState extends State<_QuickActionItem> {
  bool _hovered = false;
  bool _tapped = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () {
            setState(() => _tapped = !_tapped);
            widget.onTap();
          },
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: _tapped
                  ? DiscordColors.backgroundModifierSelected
                  : (_hovered
                      ? DiscordColors.backgroundModifierHover
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: DiscordColors.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _tapped || _hovered
                        ? DiscordColors.textNormal
                        : DiscordColors.textMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
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

// ---------------------------------------------------------------------------
// Individual DM conversation item
// ---------------------------------------------------------------------------

class _DmItem extends StatefulWidget {
  final dynamic identity; // Identity
  final SpacetimeDbService service;

  const _DmItem({
    required this.identity,
    required this.service,
  });

  @override
  State<_DmItem> createState() => _DmItemState();
}

class _DmItemState extends State<_DmItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final identity = widget.identity;
    final user = service.getUserByIdentity(identity);
    final isSelected = service.selectedDmUser == identity;

    final username = user?.username ?? 'Unknown';
    final avatarUrl = user?.avatarUrl;
    final isOnline = user?.online ?? false;

    // Status text or last message preview
    final dms = service.getDmsWith(identity);
    String subtitle;
    if (user?.statusText.isNotEmpty == true) {
      subtitle = user!.statusText;
    } else if (dms.isNotEmpty) {
      subtitle = dms.last.content;
    } else {
      subtitle = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => service.selectDmUser(identity),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? DiscordColors.backgroundModifierSelected
                  : (_hovered
                      ? DiscordColors.backgroundModifierHover
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Avatar with status
                UserAvatar(
                  username: username,
                  avatarUrl:
                      (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null,
                  size: 32,
                  showStatus: true,
                  isOnline: isOnline,
                  parentBackgroundColor: DiscordColors.channelSidebarBg,
                ),
                const SizedBox(width: 12),

                // Username + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        username,
                        style: TextStyle(
                          color: isSelected
                              ? DiscordColors.textNormal
                              : DiscordColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: DiscordColors.textMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
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

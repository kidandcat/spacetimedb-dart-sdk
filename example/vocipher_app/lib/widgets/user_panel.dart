import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';

/// Bottom panel in the channel sidebar showing current user info and controls.
class UserPanel extends StatelessWidget {
  const UserPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SpacetimeDbService>();
    final user = service.currentUser;

    final username = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : (user?.username ?? 'Unknown');
    final statusText = user?.statusText ?? '';
    final letter =
        username.isNotEmpty ? username[0].toUpperCase() : '?';
    final hasAvatar = user?.avatarUrl.isNotEmpty == true;

    return Container(
      height: 52,
      color: DiscordColors.backgroundTertiary,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Avatar with online status
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: DiscordColors.blurple,
                backgroundImage:
                    hasAvatar ? NetworkImage(user!.avatarUrl) : null,
                child: hasAvatar
                    ? null
                    : Text(
                        letter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              Positioned(
                bottom: -1,
                right: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: user?.online == true
                        ? DiscordColors.statusOnline
                        : DiscordColors.statusOffline,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: DiscordColors.backgroundTertiary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Username & status
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    color: DiscordColors.headerPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (statusText.isNotEmpty)
                  Text(
                    statusText,
                    style: const TextStyle(
                      color: DiscordColors.textMuted,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Control buttons
          _ControlButton(
            icon: Icons.mic,
            mutedIcon: Icons.mic_off,
            isMuted: _isMuted(service),
            onTap: () => service.toggleMute(),
          ),
          _ControlButton(
            icon: Icons.headphones,
            mutedIcon: Icons.headset_off,
            isMuted: _isDeafened(service),
            onTap: () => service.toggleDeafen(),
          ),
          _ControlButton(
            icon: Icons.settings,
            onTap: () {
              debugPrint('Settings tapped');
            },
          ),
        ],
      ),
    );
  }

  /// Check if the current user is muted via their voice state.
  bool _isMuted(SpacetimeDbService service) {
    if (service.myIdentity == null) return false;
    try {
      final vs = service.voiceStates.rows
          .where((v) => v.identity == service.myIdentity)
          .firstOrNull;
      return vs?.muted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if the current user is deafened via their voice state.
  bool _isDeafened(SpacetimeDbService service) {
    if (service.myIdentity == null) return false;
    try {
      final vs = service.voiceStates.rows
          .where((v) => v.identity == service.myIdentity)
          .firstOrNull;
      return vs?.deafened ?? false;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Small icon button used in the user panel
// ---------------------------------------------------------------------------

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final IconData? mutedIcon;
  final bool isMuted;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    this.mutedIcon,
    this.isMuted = false,
    required this.onTap,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = widget.isMuted && widget.mutedIcon != null
        ? widget.mutedIcon!
        : widget.icon;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hovered
                ? DiscordColors.backgroundModifierHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            effectiveIcon,
            size: 20,
            color: widget.isMuted
                ? DiscordColors.red
                : (_hovered
                    ? DiscordColors.textNormal
                    : DiscordColors.textMuted),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';
import 'user_avatar.dart';

/// Discord-style member list sidebar (right side, 240px).
class MemberList extends StatelessWidget {
  const MemberList({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SpacetimeDbService>();
    final members = service.currentMembers;

    // Resolve each member to a User and partition by online status.
    final online = <_ResolvedMember>[];
    final offline = <_ResolvedMember>[];

    for (final member in members) {
      final user = service.getUserByIdentity(member.identity);
      final resolved = _ResolvedMember(member: member, user: user);
      if (user?.online == true) {
        online.add(resolved);
      } else {
        offline.add(resolved);
      }
    }

    // Sort alphabetically within each group.
    online.sort((a, b) => a.displayName.compareTo(b.displayName));
    offline.sort((a, b) => a.displayName.compareTo(b.displayName));

    return Container(
      color: DiscordColors.memberListBg,
      child: ListView(
        padding: const EdgeInsets.only(top: 16, left: 8, right: 8),
        children: [
          // Online section
          if (online.isNotEmpty) ...[
            _SectionHeader(label: 'ONLINE', count: online.length),
            for (final m in online) _MemberItem(resolved: m, faded: false),
          ],

          // Offline section
          if (offline.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionHeader(label: 'OFFLINE', count: offline.length),
            for (final m in offline) _MemberItem(resolved: m, faded: true),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper: resolved member (ServerMember + User?)
// ---------------------------------------------------------------------------

class _ResolvedMember {
  final dynamic member; // ServerMember
  final dynamic user; // User?

  _ResolvedMember({required this.member, required this.user});

  String get displayName {
    if (user != null) {
      if ((user.displayName as String).isNotEmpty) return user.displayName;
      if ((user.username as String).isNotEmpty) return user.username;
    }
    return 'Unknown';
  }

  String get username => (user?.username as String?) ?? 'Unknown';
  String? get avatarUrl {
    final url = user?.avatarUrl as String?;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  bool get isOnline => (user?.online as bool?) ?? false;

  String get roleOrActivity {
    final role = member.role as String;
    if (role.isNotEmpty) return role;
    final status = user?.statusText as String?;
    return status ?? '';
  }
}

// ---------------------------------------------------------------------------
// Section header (e.g. "ONLINE — 5")
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;

  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 12, bottom: 4),
      child: Text(
        '$label \u2014 $count',
        style: const TextStyle(
          color: DiscordColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual member item
// ---------------------------------------------------------------------------

class _MemberItem extends StatefulWidget {
  final _ResolvedMember resolved;
  final bool faded;

  const _MemberItem({required this.resolved, required this.faded});

  @override
  State<_MemberItem> createState() => _MemberItemState();
}

class _MemberItemState extends State<_MemberItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.resolved;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Opacity(
          opacity: widget.faded ? 0.3 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: _hovered
                  ? DiscordColors.backgroundModifierHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Avatar with status dot
                UserAvatar(
                  username: m.username,
                  avatarUrl: m.avatarUrl,
                  size: 32,
                  showStatus: true,
                  isOnline: m.isOnline,
                  parentBackgroundColor: DiscordColors.memberListBg,
                ),
                const SizedBox(width: 12),

                // Username + role/activity
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        m.displayName,
                        style: const TextStyle(
                          color: DiscordColors.textNormal,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (m.roleOrActivity.isNotEmpty)
                        Text(
                          m.roleOrActivity,
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

import 'package:flutter/material.dart';

import '../theme/discord_theme.dart';

/// Consistent avatar colors picked by username hash.
const avatarColors = [
  Color(0xFF5865F2), // blurple
  Color(0xFF57F287), // green
  Color(0xFFFEE75C), // yellow
  Color(0xFFEB459E), // fuchsia
  Color(0xFFED4245), // red
  Color(0xFF1ABC9C), // teal
  Color(0xFFE91E63), // pink
  Color(0xFF9B59B6), // purple
  Color(0xFFE67E22), // orange
  Color(0xFF3498DB), // blue
];

/// Reusable Discord-style avatar with optional online status dot.
class UserAvatar extends StatelessWidget {
  final String? username;
  final String? avatarUrl;
  final double size;
  final bool showStatus;
  final bool isOnline;

  /// Background color behind the status dot border (should match the parent
  /// surface so the dot looks "cut out").
  final Color parentBackgroundColor;

  const UserAvatar({
    super.key,
    this.username,
    this.avatarUrl,
    this.size = 40,
    this.showStatus = false,
    this.isOnline = false,
    this.parentBackgroundColor = DiscordColors.channelSidebarBg,
  });

  /// Generate a consistent color from [username].
  Color _colorForUsername(String name) {
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return avatarColors[hash.abs() % avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final letter = (username != null && username!.isNotEmpty)
        ? username![0].toUpperCase()
        : '?';
    final bgColor =
        (username != null && username!.isNotEmpty) ? _colorForUsername(username!) : avatarColors[0];

    // Status dot sizing: 12px diameter for a 40px avatar, scaled proportionally.
    final dotSize = size * 12 / 40;
    final borderWidth = size * 3 / 40;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Avatar circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasAvatar ? Colors.transparent : bgColor,
              image: hasAvatar
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: hasAvatar
                ? null
                : Text(
                    letter,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),

          // Status indicator dot
          if (showStatus)
            Positioned(
              right: -(borderWidth / 2),
              bottom: -(borderWidth / 2),
              child: Container(
                width: dotSize + borderWidth * 2,
                height: dotSize + borderWidth * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parentBackgroundColor,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline
                        ? DiscordColors.statusOnline
                        : DiscordColors.statusOffline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

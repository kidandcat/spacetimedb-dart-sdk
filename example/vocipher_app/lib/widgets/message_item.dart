import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:spacetimedb_sdk/spacetimedb.dart';

import '../generated/module.dart';
import '../theme/discord_theme.dart';

/// Discord-style username colors derived from the username hash.
const _usernameColors = [
  DiscordColors.blurple,
  DiscordColors.green,
  DiscordColors.yellow,
  DiscordColors.fuchsia,
  DiscordColors.red,
  Color(0xFF1ABC9C),
  Color(0xFFE91E63),
  Color(0xFF9B59B6),
  Color(0xFFE67E22),
  Color(0xFF3498DB),
  Color(0xFF2ECC71),
  Color(0xFFE74C3C),
  Color(0xFFF1C40F),
  Color(0xFF1F8B4C),
  Color(0xFFC27C0E),
  Color(0xFFA84300),
];

Color _colorForUsername(String username) {
  var hash = 0;
  for (var i = 0; i < username.length; i++) {
    hash = username.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return _usernameColors[hash.abs() % _usernameColors.length];
}

String _formatTimestamp(int microsecondsSinceEpoch) {
  final date =
      DateTime.fromMicrosecondsSinceEpoch(microsecondsSinceEpoch, isUtc: true)
          .toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final messageDay = DateTime(date.year, date.month, date.day);

  final timeFormat = DateFormat.jm(); // e.g. "3:45 PM"

  if (messageDay == today) {
    return 'Today at ${timeFormat.format(date)}';
  } else if (messageDay == yesterday) {
    return 'Yesterday at ${timeFormat.format(date)}';
  } else {
    return DateFormat('MM/dd/yyyy').format(date);
  }
}

class MessageItem extends StatefulWidget {
  final String content;
  final Identity senderIdentity;
  final int timestampMicros;
  final bool edited;
  final bool showHeader;
  final bool isOwn;
  final User? senderUser;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const MessageItem({
    super.key,
    required this.content,
    required this.senderIdentity,
    required this.timestampMicros,
    this.edited = false,
    required this.showHeader,
    required this.isOwn,
    this.senderUser,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  bool _hovered = false;

  String get _displayName =>
      widget.senderUser?.displayName.isNotEmpty == true
          ? widget.senderUser!.displayName
          : widget.senderUser?.username ?? widget.senderIdentity.toHex().substring(0, 8);

  String get _username =>
      widget.senderUser?.username ?? widget.senderIdentity.toHex().substring(0, 8);

  String get _avatarLetter {
    final name = _displayName;
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            color: _hovered
                ? DiscordColors.backgroundModifierHover
                : Colors.transparent,
            padding: EdgeInsets.only(
              left: 72,
              right: 48,
              top: widget.showHeader ? 16 : 2,
              bottom: 2,
            ),
            child: widget.showHeader ? _buildWithHeader() : _buildContentOnly(),
          ),
          if (_hovered) _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildWithHeader() {
    final usernameColor = _colorForUsername(_username);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Avatar positioned to the left
        Positioned(
          left: -56,
          top: 0,
          child: _buildAvatar(),
        ),
        // Username + timestamp row, then content
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: usernameColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(widget.timestampMicros),
                  style: const TextStyle(
                    fontSize: 12,
                    color: DiscordColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            _buildContent(),
          ],
        ),
      ],
    );
  }

  Widget _buildContentOnly() {
    return Align(
      alignment: Alignment.centerLeft,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(
            text: widget.content,
            style: const TextStyle(
              fontSize: 16,
              color: DiscordColors.textNormal,
              height: 1.375,
            ),
          ),
          if (widget.edited)
            const TextSpan(
              text: ' (edited)',
              style: TextStyle(
                fontSize: 10,
                color: DiscordColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = widget.senderUser?.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(avatarUrl),
        backgroundColor: DiscordColors.backgroundModifierActive,
      );
    }
    final color = _colorForUsername(_username);
    return CircleAvatar(
      radius: 20,
      backgroundColor: color,
      child: Text(
        _avatarLetter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Positioned(
      top: -4,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: DiscordColors.backgroundPrimary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: DiscordColors.backgroundTertiary,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionButton(
              Icons.emoji_emotions_outlined,
              'Add Reaction',
              () {},
            ),
            if (widget.isOwn && widget.onEdit != null)
              _actionButton(Icons.edit_outlined, 'Edit', widget.onEdit!),
            if (widget.isOwn && widget.onDelete != null)
              _actionButton(Icons.delete_outlined, 'Delete', widget.onDelete!),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: DiscordColors.textMuted),
        ),
      ),
    );
  }
}

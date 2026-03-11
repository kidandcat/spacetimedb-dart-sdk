import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spacetimedb_sdk/spacetimedb.dart' show Identity;

import '../generated/module.dart';
import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';
import 'user_panel.dart';

/// Discord-style channel list that fills the 240px sidebar column.
class ChannelList extends StatelessWidget {
  const ChannelList({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SpacetimeDbService>();
    final server = service.selectedServer;

    if (server == null) {
      return Container(
        width: 240,
        color: DiscordColors.channelSidebarBg,
        child: const Column(
          children: [
            Spacer(),
            UserPanel(),
          ],
        ),
      );
    }

    final textChannels = service.currentTextChannels;
    final voiceChannels = service.currentVoiceChannels;

    return Container(
      width: 240,
      color: DiscordColors.channelSidebarBg,
      child: Column(
        children: [
          // Server name header
          _ServerHeader(server: server),
          // Channel list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                // Text channels category
                _CategoryHeader(
                  label: 'TEXT CHANNELS',
                  onAddChannel: () =>
                      _showCreateChannelDialog(context, service, server.id),
                ),
                for (final channel in textChannels)
                  _TextChannelItem(
                    channel: channel,
                    isSelected: service.selectedChannelId == channel.id,
                    onTap: () => service.selectChannel(channel.id),
                  ),
                const SizedBox(height: 8),
                // Voice channels category
                _CategoryHeader(
                  label: 'VOICE CHANNELS',
                  onAddChannel: () => _showCreateChannelDialog(
                      context, service, server.id,
                      defaultType: ChannelType.voice),
                ),
                for (final channel in voiceChannels)
                  _VoiceChannelItem(
                    channel: channel,
                    isSelected: service.selectedChannelId == channel.id,
                    onTap: () => service.joinVoiceChannel(channel.id),
                    voiceUsers: service.voiceUsersInChannel(channel.id),
                    getUserByIdentity: service.getUserByIdentity,
                  ),
              ],
            ),
          ),
          // User panel at bottom
          const UserPanel(),
        ],
      ),
    );
  }

  void _showCreateChannelDialog(
    BuildContext context,
    SpacetimeDbService service,
    int serverId, {
    ChannelType defaultType = ChannelType.text,
  }) {
    final nameController = TextEditingController();
    ChannelType selectedType = defaultType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create Channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'channel-name',
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    service.createChannel(
                        serverId, value.trim(), selectedType, '');
                    Navigator.of(ctx).pop();
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'CHANNEL TYPE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DiscordColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<ChannelType>(
                groupValue: selectedType,
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedType = v);
                },
                child: Column(
                  children: [
                    RadioListTile<ChannelType>(
                      title: const Row(
                        children: [
                          Icon(Icons.tag,
                              size: 18, color: DiscordColors.textMuted),
                          SizedBox(width: 8),
                          Text('Text'),
                        ],
                      ),
                      value: ChannelType.text,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<ChannelType>(
                      title: const Row(
                        children: [
                          Icon(Icons.volume_up,
                              size: 18, color: DiscordColors.textMuted),
                          SizedBox(width: 8),
                          Text('Voice'),
                        ],
                      ),
                      value: ChannelType.voice,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  service.createChannel(serverId, name, selectedType, '');
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Server name header (48px)
// ---------------------------------------------------------------------------

class _ServerHeader extends StatelessWidget {
  final Server server;

  const _ServerHeader({required this.server});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        debugPrint('Server settings tapped: ${server.name}');
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: DiscordColors.divider, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                server.name,
                style: const TextStyle(
                  color: DiscordColors.headerPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: DiscordColors.headerPrimary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category header ("TEXT CHANNELS", etc.)
// ---------------------------------------------------------------------------

class _CategoryHeader extends StatelessWidget {
  final String label;
  final VoidCallback onAddChannel;

  const _CategoryHeader({
    required this.label,
    required this.onAddChannel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 8, top: 16, bottom: 4),
      child: Row(
        children: [
          const Icon(
            Icons.chevron_right,
            size: 12,
            color: DiscordColors.textMuted,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DiscordColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ),
          InkWell(
            onTap: onAddChannel,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.add,
                size: 16,
                color: DiscordColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text channel item
// ---------------------------------------------------------------------------

class _TextChannelItem extends StatefulWidget {
  final Channel channel;
  final bool isSelected;
  final VoidCallback onTap;

  const _TextChannelItem({
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TextChannelItem> createState() => _TextChannelItemState();
}

class _TextChannelItemState extends State<_TextChannelItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    final Color bgColor;

    if (widget.isSelected) {
      textColor = DiscordColors.headerPrimary;
      bgColor = DiscordColors.backgroundModifierSelected;
    } else if (_hovered) {
      textColor = DiscordColors.headerPrimary;
      bgColor = DiscordColors.backgroundModifierHover;
    } else {
      textColor = DiscordColors.textMuted;
      bgColor = Colors.transparent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.tag, size: 20, color: textColor.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.channel.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: widget.isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
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
// Voice channel item (with nested voice users)
// ---------------------------------------------------------------------------

class _VoiceChannelItem extends StatefulWidget {
  final Channel channel;
  final bool isSelected;
  final VoidCallback onTap;
  final List<VoiceState> voiceUsers;
  final User? Function(Identity) getUserByIdentity;

  const _VoiceChannelItem({
    required this.channel,
    required this.isSelected,
    required this.onTap,
    required this.voiceUsers,
    required this.getUserByIdentity,
  });

  @override
  State<_VoiceChannelItem> createState() => _VoiceChannelItemState();
}

class _VoiceChannelItemState extends State<_VoiceChannelItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    final Color bgColor;

    if (widget.isSelected) {
      textColor = DiscordColors.headerPrimary;
      bgColor = DiscordColors.backgroundModifierSelected;
    } else if (_hovered) {
      textColor = DiscordColors.headerPrimary;
      bgColor = DiscordColors.backgroundModifierHover;
    } else {
      textColor = DiscordColors.textMuted;
      bgColor = Colors.transparent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.volume_up,
                        size: 20, color: textColor.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.channel.name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Voice users in this channel
        if (widget.voiceUsers.isNotEmpty)
          ...widget.voiceUsers.map((vs) {
            final user = widget.getUserByIdentity(vs.identity);
            final name = user?.displayName.isNotEmpty == true
                ? user!.displayName
                : (user?.username ?? 'Unknown');
            final letter =
                name.isNotEmpty ? name[0].toUpperCase() : '?';

            return Padding(
              padding: const EdgeInsets.only(left: 44, right: 8, bottom: 2),
              child: Row(
                children: [
                  // Small avatar
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: DiscordColors.blurple,
                    child: Text(
                      letter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: DiscordColors.textMuted,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (vs.muted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.mic_off,
                          size: 14, color: DiscordColors.textMuted),
                    ),
                  if (vs.deafened)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.headset_off,
                          size: 14, color: DiscordColors.textMuted),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

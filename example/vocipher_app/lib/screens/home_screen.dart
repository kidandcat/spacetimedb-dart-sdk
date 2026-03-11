import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../generated/types/channel_type.dart';
import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';
import '../widgets/channel_list.dart';
import '../widgets/chat_view.dart';
import '../widgets/dm_list.dart';
import '../widgets/member_list.dart';
import '../widgets/server_sidebar.dart';
import '../widgets/user_panel.dart';
import '../widgets/voice_channel_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<SpacetimeDbService>(
        builder: (context, service, _) {
          return Row(
            children: [
              // Server sidebar (far left)
              const SizedBox(
                width: 72,
                child: ServerSidebar(),
              ),

              // Channel list / DM list + user panel
              SizedBox(
                width: 240,
                child: Container(
                  color: DiscordColors.channelSidebarBg,
                  child: Column(
                    children: [
                      Expanded(
                        child: service.showDms
                            ? const DmList()
                            : const ChannelList(),
                      ),
                      const UserPanel(),
                    ],
                  ),
                ),
              ),

              // Main content area
              Expanded(
                child: Column(
                  children: [
                    // Top bar
                    _TopBar(service: service),

                    // Chat or voice view
                    Expanded(
                      child: _buildMainContent(service),
                    ),
                  ],
                ),
              ),

              // Member list (optional, right side)
              if (service.showMemberList && !service.showDms)
                SizedBox(
                  width: 240,
                  child: Container(
                    color: DiscordColors.memberListBg,
                    child: const MemberList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainContent(SpacetimeDbService service) {
    final channel = service.selectedChannel;

    if (channel != null && channel.channelType == ChannelType.voice) {
      return const VoiceChannelView();
    }

    return const ChatView();
  }
}

class _TopBar extends StatelessWidget {
  final SpacetimeDbService service;

  const _TopBar({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: DiscordColors.chatBg,
        border: Border(
          bottom: BorderSide(
            color: DiscordColors.divider,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Left side: channel/DM info
          Expanded(child: _buildLeftInfo()),

          // Right side: action icons
          ..._buildRightIcons(context),
        ],
      ),
    );
  }

  Widget _buildLeftInfo() {
    if (service.showDms && service.selectedDmUser != null) {
      final dmUser = service.getUserByIdentity(service.selectedDmUser!);
      final displayName =
          dmUser?.displayName.isNotEmpty == true ? dmUser!.displayName : dmUser?.username ?? 'Unknown';
      return Row(
        children: [
          const Icon(
            Icons.alternate_email,
            color: DiscordColors.textMuted,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            displayName,
            style: const TextStyle(
              color: DiscordColors.headerPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final channel = service.selectedChannel;
    if (channel != null) {
      final isVoice = channel.channelType == ChannelType.voice;
      return Row(
        children: [
          Icon(
            isVoice ? Icons.volume_up : Icons.tag,
            color: DiscordColors.textMuted,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            channel.name,
            style: const TextStyle(
              color: DiscordColors.headerPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (channel.topic.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 24,
              color: DiscordColors.divider,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.topic,
                style: const TextStyle(
                  color: DiscordColors.textMuted,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ],
      );
    }

    // No channel or DM selected
    return const SizedBox.shrink();
  }

  List<Widget> _buildRightIcons(BuildContext context) {
    return [
      if (!service.showDms)
        _TopBarIcon(
          icon: Icons.people,
          tooltip: 'Toggle Member List',
          isActive: service.showMemberList,
          onPressed: service.toggleMemberList,
        ),
      const _TopBarIcon(
        icon: Icons.push_pin_outlined,
        tooltip: 'Pinned Messages',
      ),
      const _TopBarIcon(
        icon: Icons.search,
        tooltip: 'Search',
      ),
    ];
  }
}

class _TopBarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onPressed;

  const _TopBarIcon({
    required this.icon,
    required this.tooltip,
    this.isActive = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: isActive
                ? DiscordColors.headerPrimary
                : DiscordColors.textMuted,
            size: 20,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';

class VoiceChannelView extends StatelessWidget {
  const VoiceChannelView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SpacetimeDbService>(
      builder: (context, service, _) {
        final channel = service.selectedChannel;
        if (channel == null) {
          return const Center(
            child: Text(
              'No voice channel selected',
              style: TextStyle(color: DiscordColors.textMuted),
            ),
          );
        }

        final voiceUsers = service.currentVoiceUsers;
        final myIdentity = service.myIdentity;
        final isInChannel =
            myIdentity != null &&
            voiceUsers.any((v) => v.identity == myIdentity);
        final myVoiceState = isInChannel
            ? voiceUsers.firstWhere((v) => v.identity == myIdentity)
            : null;

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Speaker icon
              const Icon(
                Icons.speaker_group,
                size: 64,
                color: DiscordColors.textMuted,
              ),
              const SizedBox(height: 16),

              // "Voice Channel" label
              const Text(
                'Voice Channel',
                style: TextStyle(
                  fontSize: 14,
                  color: DiscordColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),

              // Channel name
              Text(
                channel.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: DiscordColors.headerPrimary,
                ),
              ),
              const SizedBox(height: 24),

              // Connected users list
              if (voiceUsers.isNotEmpty) ...[
                const Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DiscordColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...voiceUsers.map((vs) {
                  final user = service.getUserByIdentity(vs.identity);
                  final name = user?.displayName.isNotEmpty == true
                      ? user!.displayName
                      : user?.username ??
                          vs.identity.toHex().substring(0, 8);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: DiscordColors.blurple,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: const TextStyle(
                            color: DiscordColors.textNormal,
                            fontSize: 14,
                          ),
                        ),
                        if (vs.muted) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.mic_off,
                              size: 14, color: DiscordColors.red),
                        ],
                        if (vs.deafened) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.headset_off,
                              size: 14, color: DiscordColors.red),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No one is connected',
                    style: TextStyle(
                      fontSize: 14,
                      color: DiscordColors.textMuted,
                    ),
                  ),
                ),
              ],

              // Join / Disconnect button
              if (!isInChannel)
                ElevatedButton.icon(
                  onPressed: () => service.joinVoiceChannel(channel.id),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Join Voice'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DiscordColors.blurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                )
              else ...[
                ElevatedButton.icon(
                  onPressed: () => service.leaveVoiceChannel(),
                  icon: const Icon(Icons.call_end, size: 18),
                  label: const Text('Disconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DiscordColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Mute / Deafen toggles
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _VoiceToggleButton(
                      icon: myVoiceState!.muted ? Icons.mic_off : Icons.mic,
                      label: myVoiceState.muted ? 'Unmute' : 'Mute',
                      active: myVoiceState.muted,
                      onPressed: () => service.toggleMute(),
                    ),
                    const SizedBox(width: 12),
                    _VoiceToggleButton(
                      icon: myVoiceState.deafened
                          ? Icons.headset_off
                          : Icons.headset,
                      label: myVoiceState.deafened ? 'Undeafen' : 'Deafen',
                      active: myVoiceState.deafened,
                      onPressed: () => service.toggleDeafen(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VoiceToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  const _VoiceToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: active
                ? DiscordColors.red.withValues(alpha: 0.2)
                : DiscordColors.backgroundModifierActive,
            foregroundColor:
                active ? DiscordColors.red : DiscordColors.textNormal,
            padding: const EdgeInsets.all(12),
            shape: const CircleBorder(),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: DiscordColors.textMuted,
          ),
        ),
      ],
    );
  }
}

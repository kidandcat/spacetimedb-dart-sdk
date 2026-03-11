import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../generated/module.dart';
import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';

/// Discord-style server sidebar (72px wide vertical strip on the far left).
class ServerSidebar extends StatelessWidget {
  const ServerSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SpacetimeDbService>();
    final servers = service.myServers;

    return Container(
      width: 72,
      color: DiscordColors.serverSidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Home / DM button
          _HomeButton(
            isSelected: service.showDms,
            onTap: () => service.showDirectMessages(),
          ),
          const SizedBox(height: 8),
          // Divider
          Container(
            width: 32,
            height: 2,
            decoration: BoxDecoration(
              color: DiscordColors.divider,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 8),
          // Server list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 0),
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ServerIcon(
                    server: server,
                    isSelected: service.selectedServerId == server.id,
                    onTap: () => service.selectServer(server.id),
                  ),
                );
              },
            ),
          ),
          // Add server button
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AddServerButton(
              onTap: () => _showCreateServerDialog(context, service),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateServerDialog(
      BuildContext context, SpacetimeDbService service) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a Server'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Server name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              service.createServer(value.trim());
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                service.createServer(name);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home button (DM / chat bubble icon)
// ---------------------------------------------------------------------------

class _HomeButton extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _HomeButton({required this.isSelected, required this.onTap});

  @override
  State<_HomeButton> createState() => _HomeButtonState();
}

class _HomeButtonState extends State<_HomeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _hovered;

    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Pill indicator
          if (widget.isSelected)
            Positioned(
              left: -16,
              top: 4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive
                      ? DiscordColors.blurple
                      : DiscordColors.backgroundPrimary,
                  borderRadius:
                      BorderRadius.circular(isActive ? 16 : 24),
                ),
                child: const Icon(
                  Icons.chat_bubble,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual server icon
// ---------------------------------------------------------------------------

class _ServerIcon extends StatefulWidget {
  final Server server;
  final bool isSelected;
  final VoidCallback onTap;

  const _ServerIcon({
    required this.server,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ServerIcon> createState() => _ServerIconState();
}

class _ServerIconState extends State<_ServerIcon> {
  bool _hovered = false;

  /// Pick a consistent color from the server name.
  static const _palette = [
    Color(0xFF5865F2), // blurple
    Color(0xFF57F287), // green
    Color(0xFFFEE75C), // yellow
    Color(0xFFEB459E), // fuchsia
    Color(0xFFED4245), // red
    Color(0xFF3BA55D), // dark green
    Color(0xFFF47B67), // salmon
    Color(0xFF9B84EE), // light purple
    Color(0xFFF7A531), // orange
    Color(0xFF45DDC0), // teal
  ];

  Color _colorForName(String name) {
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return _palette[hash.abs() % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _hovered;
    final hasIcon = widget.server.iconUrl.isNotEmpty;
    final letter = widget.server.name.isNotEmpty
        ? widget.server.name[0].toUpperCase()
        : '?';

    return Center(
      child: Tooltip(
        message: widget.server.name,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 500),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Pill indicator
            Positioned(
              left: -16,
              top: widget.isSelected ? 4 : 18,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 4,
                height: widget.isSelected
                    ? 40
                    : (_hovered ? 20 : 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hasIcon
                        ? Colors.transparent
                        : _colorForName(widget.server.name),
                    borderRadius:
                        BorderRadius.circular(isActive ? 16 : 24),
                    image: hasIcon
                        ? DecorationImage(
                            image: NetworkImage(widget.server.iconUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: hasIcon
                      ? null
                      : Text(
                          letter,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add server button (green +)
// ---------------------------------------------------------------------------

class _AddServerButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddServerButton({required this.onTap});

  @override
  State<_AddServerButton> createState() => _AddServerButtonState();
}

class _AddServerButtonState extends State<_AddServerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _hovered
                  ? DiscordColors.green
                  : DiscordColors.backgroundPrimary,
              borderRadius:
                  BorderRadius.circular(_hovered ? 16 : 24),
            ),
            child: Icon(
              Icons.add,
              color: _hovered ? Colors.white : DiscordColors.green,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

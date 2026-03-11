import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spacetimedb_sdk/spacetimedb.dart';

import '../generated/module.dart';
import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';
import 'message_item.dart';

/// Represents a unified message for display (either a channel Message or a DirectMessage).
class _DisplayMessage {
  final int id;
  final Identity sender;
  final String content;
  final int timestampMicros;
  final bool edited;
  final bool isChannelMessage;

  _DisplayMessage({
    required this.id,
    required this.sender,
    required this.content,
    required this.timestampMicros,
    required this.edited,
    required this.isChannelMessage,
  });

  factory _DisplayMessage.fromMessage(Message m) => _DisplayMessage(
        id: m.id,
        sender: m.sender,
        content: m.content,
        timestampMicros: m.sentAt.microsecondsSinceEpoch,
        edited: m.edited,
        isChannelMessage: true,
      );

  factory _DisplayMessage.fromDm(DirectMessage dm) => _DisplayMessage(
        id: dm.id,
        sender: dm.sender,
        content: dm.content,
        timestampMicros: dm.sentAt.microsecondsSinceEpoch,
        edited: false,
        isChannelMessage: false,
      );
}

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage(SpacetimeDbService service) {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    if (service.showDms && service.selectedDmUser != null) {
      service.sendDm(service.selectedDmUser!, content);
    } else {
      service.sendMessage(content);
    }

    _messageController.clear();
    _focusNode.requestFocus();
  }

  void _handleEditMessage(SpacetimeDbService service, _DisplayMessage msg) {
    if (!msg.isChannelMessage) return; // DMs don't support edit
    final controller = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(color: DiscordColors.textNormal),
          decoration: const InputDecoration(
            hintText: 'Edit your message...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty && newContent != msg.content) {
                service.editMessage(msg.id, newContent);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteMessage(SpacetimeDbService service, _DisplayMessage msg) {
    if (!msg.isChannelMessage) return; // DMs don't support delete
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text(
          'Are you sure you want to delete this message? This cannot be undone.',
          style: TextStyle(color: DiscordColors.textNormal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              service.deleteMessage(msg.id);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: DiscordColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Groups consecutive messages from the same sender within 7 minutes.
  /// Returns a list of (message, showHeader) pairs.
  List<(_DisplayMessage, bool)> _groupMessages(List<_DisplayMessage> messages) {
    if (messages.isEmpty) return [];
    final result = <(_DisplayMessage, bool)>[];
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (i == 0) {
        result.add((msg, true));
        continue;
      }
      final prev = messages[i - 1];
      final sameUser = msg.sender == prev.sender;
      final withinTimeWindow =
          (msg.timestampMicros - prev.timestampMicros).abs() <
              7 * 60 * 1000000; // 7 minutes in micros
      result.add((msg, !(sameUser && withinTimeWindow)));
    }
    return result;
  }

  String get _inputPlaceholder {
    final service = context.read<SpacetimeDbService>();
    if (service.showDms && service.selectedDmUser != null) {
      final dmUser = service.getUserByIdentity(service.selectedDmUser!);
      final name = dmUser?.displayName.isNotEmpty == true
          ? dmUser!.displayName
          : dmUser?.username ?? 'user';
      return 'Message @$name';
    }
    final channel = service.selectedChannel;
    return 'Message #${channel?.name ?? 'channel'}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SpacetimeDbService>(
      builder: (context, service, _) {
        // Determine which messages to show
        final bool isDm = service.showDms && service.selectedDmUser != null;
        final bool hasChannel = service.selectedChannelId != null;

        if (!isDm && !hasChannel) {
          return _buildEmptyState();
        }

        final List<_DisplayMessage> messages;
        if (isDm) {
          messages = service
              .getDmsWith(service.selectedDmUser!)
              .map(_DisplayMessage.fromDm)
              .toList();
        } else {
          messages = service.currentMessages
              .map(_DisplayMessage.fromMessage)
              .toList();
        }

        final grouped = _groupMessages(messages);

        return Column(
          children: [
            Expanded(
              child: _buildMessageList(service, grouped, isDm),
            ),
            _buildMessageInput(service),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: DiscordColors.textMuted),
          SizedBox(height: 16),
          Text(
            'Select a channel or conversation to start chatting',
            style: TextStyle(
              color: DiscordColors.textMuted,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    SpacetimeDbService service,
    List<(_DisplayMessage, bool)> grouped,
    bool isDm,
  ) {
    // The list is reversed: index 0 = newest message (at the bottom of the screen).
    // We add +1 to the item count for the welcome header at the very top
    // (which, because the list is reversed, is the LAST index).
    final itemCount = grouped.length + 1;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // The welcome message is the last item in reversed index
        if (index == itemCount - 1) {
          return _buildWelcomeHeader(service, isDm);
        }

        // Reversed index: index 0 = last message in grouped list
        final reversedIdx = grouped.length - 1 - index;
        final (msg, showHeader) = grouped[reversedIdx];
        final myIdentity = service.myIdentity;
        final isOwn = myIdentity != null && msg.sender == myIdentity;
        final senderUser = service.getUserByIdentity(msg.sender);

        return MessageItem(
          key: ValueKey('msg-${msg.id}-${msg.isChannelMessage ? "ch" : "dm"}'),
          content: msg.content,
          senderIdentity: msg.sender,
          timestampMicros: msg.timestampMicros,
          edited: msg.edited,
          showHeader: showHeader,
          isOwn: isOwn,
          senderUser: senderUser,
          onEdit: isOwn && msg.isChannelMessage
              ? () => _handleEditMessage(service, msg)
              : null,
          onDelete: isOwn && msg.isChannelMessage
              ? () => _handleDeleteMessage(service, msg)
              : null,
        );
      },
    );
  }

  Widget _buildWelcomeHeader(SpacetimeDbService service, bool isDm) {
    if (isDm) {
      final dmUser = service.getUserByIdentity(service.selectedDmUser!);
      final name = dmUser?.displayName.isNotEmpty == true
          ? dmUser!.displayName
          : dmUser?.username ?? 'Unknown User';
      return Padding(
        padding: const EdgeInsets.fromLTRB(72, 24, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: DiscordColors.blurple,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: DiscordColors.headerPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This is the beginning of your direct message history with @$name.',
              style: const TextStyle(
                fontSize: 14,
                color: DiscordColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: DiscordColors.divider, height: 1),
          ],
        ),
      );
    }

    final channelName = service.selectedChannel?.name ?? 'channel';
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: DiscordColors.backgroundModifierActive,
              borderRadius: BorderRadius.circular(34),
            ),
            child: const Icon(
              Icons.tag,
              size: 40,
              color: DiscordColors.headerPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome to #$channelName!',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: DiscordColors.headerPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is the start of the #$channelName channel.',
            style: const TextStyle(
              fontSize: 14,
              color: DiscordColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: DiscordColors.divider, height: 1),
        ],
      ),
    );
  }

  Widget _buildMessageInput(SpacetimeDbService service) {
    return Container(
      color: DiscordColors.chatBg,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        decoration: BoxDecoration(
          color: DiscordColors.inputBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment button
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: DiscordColors.textMuted),
              onPressed: () {
                // Placeholder for attachment functionality
              },
              tooltip: 'Attach file',
            ),
            // Text field
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  // Handled in the TextField's onSubmitted and
                  // the Actions/Shortcuts below
                },
                child: Shortcuts(
                  shortcuts: {
                    LogicalKeySet(LogicalKeyboardKey.enter):
                        const _SendMessageIntent(),
                    LogicalKeySet(
                        LogicalKeyboardKey.shift, LogicalKeyboardKey.enter):
                        const _NewLineIntent(),
                  },
                  child: Actions(
                    actions: {
                      _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                        onInvoke: (_) {
                          _sendMessage(service);
                          return null;
                        },
                      ),
                      _NewLineIntent: CallbackAction<_NewLineIntent>(
                        onInvoke: (_) {
                          final text = _messageController.text;
                          final selection = _messageController.selection;
                          final newText = text.replaceRange(
                            selection.start,
                            selection.end,
                            '\n',
                          );
                          _messageController.value = TextEditingValue(
                            text: newText,
                            selection: TextSelection.collapsed(
                              offset: selection.start + 1,
                            ),
                          );
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      maxLines: null,
                      style: const TextStyle(
                        color: DiscordColors.textNormal,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: _inputPlaceholder,
                        hintStyle: const TextStyle(
                          color: DiscordColors.textMuted,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 11,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Emoji button
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined,
                  color: DiscordColors.textMuted),
              onPressed: () {
                // Placeholder for emoji picker
              },
              tooltip: 'Emoji',
            ),
            // Gift button
            IconButton(
              icon: const Icon(Icons.card_giftcard_outlined,
                  color: DiscordColors.textMuted),
              onPressed: () {
                // Placeholder for gift functionality
              },
              tooltip: 'Gift',
            ),
          ],
        ),
      ),
    );
  }
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _NewLineIntent extends Intent {
  const _NewLineIntent();
}

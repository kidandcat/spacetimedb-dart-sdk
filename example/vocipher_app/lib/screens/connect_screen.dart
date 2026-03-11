import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/spacetimedb_service.dart';
import '../theme/discord_theme.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _hostController =
      TextEditingController(text: 'http://127.0.0.1:3002');
  final _databaseController = TextEditingController(text: 'vocipher');
  final _usernameController = TextEditingController();

  bool _isConnecting = false;
  bool _showUsernameStep = false;

  @override
  void dispose() {
    _hostController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final service = context.read<SpacetimeDbService>();
    setState(() => _isConnecting = true);

    await service.connect(
      _hostController.text.trim(),
      _databaseController.text.trim(),
    );

    if (!mounted) return;

    if (service.connectionError != null) {
      setState(() => _isConnecting = false);
    } else {
      // Connection successful — wait for subscriptions to apply
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final currentUser = service.currentUser;
      if (currentUser != null && currentUser.username.isNotEmpty) {
        // User already has a username, go directly to home
        service.completeSetup();
        return;
      }

      setState(() {
        _isConnecting = false;
        _showUsernameStep = true;
      });
    }
  }

  void _setUsername() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    final service = context.read<SpacetimeDbService>();
    service.setUsername(username);
    service.completeSetup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiscordColors.backgroundDarkest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _showUsernameStep ? _buildUsernameStep() : _buildConnectStep(),
        ),
      ),
    );
  }

  Widget _buildConnectStep() {
    return Consumer<SpacetimeDbService>(
      builder: (context, service, _) {
        return Container(
          width: 480,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: DiscordColors.backgroundPrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App title
              Text(
                'Vocipher',
                style: TextStyle(
                  color: DiscordColors.headerPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect to a SpacetimeDB instance',
                style: TextStyle(
                  color: DiscordColors.textMuted,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),

              // Host field
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'HOST',
                    style: TextStyle(
                      color: DiscordColors.headerSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: _hostController,
                enabled: !_isConnecting,
                style: const TextStyle(color: DiscordColors.textNormal),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: DiscordColors.inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Database field
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'DATABASE',
                    style: TextStyle(
                      color: DiscordColors.headerSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: _databaseController,
                enabled: !_isConnecting,
                style: const TextStyle(color: DiscordColors.textNormal),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: DiscordColors.inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Error message
              if (service.connectionError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DiscordColors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: DiscordColors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      service.connectionError!,
                      style: const TextStyle(
                        color: DiscordColors.red,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

              // Connect button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DiscordColors.blurple,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        DiscordColors.blurple.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    elevation: 0,
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Connect',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsernameStep() {
    return Container(
      width: 480,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: DiscordColors.backgroundPrimary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Welcome icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: DiscordColors.blurple,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.waving_hand_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Welcome to Vocipher!',
            style: TextStyle(
              color: DiscordColors.headerPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a username to get started',
            style: TextStyle(
              color: DiscordColors.textMuted,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),

          // Username field
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'USERNAME',
                style: TextStyle(
                  color: DiscordColors.headerSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          TextField(
            controller: _usernameController,
            enabled: true,
            autofocus: true,
            style: const TextStyle(color: DiscordColors.textNormal),
            decoration: InputDecoration(
              filled: true,
              fillColor: DiscordColors.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              hintText: 'Enter a username',
              hintStyle: const TextStyle(color: DiscordColors.textMuted),
            ),
            onSubmitted: (_) => _setUsername(),
          ),
          const SizedBox(height: 24),

          // Continue button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _setUsername,
              style: ElevatedButton.styleFrom(
                backgroundColor: DiscordColors.blurple,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    DiscordColors.blurple.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                elevation: 0,
              ),
              child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

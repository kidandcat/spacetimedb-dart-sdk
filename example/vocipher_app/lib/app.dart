import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'services/spacetimedb_service.dart';
import 'theme/discord_theme.dart';

class VocipherApp extends StatelessWidget {
  const VocipherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vocipher',
      debugShowCheckedModeBanner: false,
      theme: DiscordTheme.dark(),
      home: Consumer<SpacetimeDbService>(
        builder: (context, service, _) {
          if (service.isConnected && service.setupComplete) {
            return const HomeScreen();
          }
          return const ConnectScreen();
        },
      ),
    );
  }
}

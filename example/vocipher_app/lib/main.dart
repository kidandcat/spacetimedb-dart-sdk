import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/spacetimedb_service.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => SpacetimeDbService(),
      child: const VocipherApp(),
    ),
  );
}

// Example: Connecting to SpacetimeDB vocipher module with generated bindings.
//
// Prerequisites:
//   1. SpacetimeDB running on localhost:3002
//   2. vocipher module published
//   3. Run codegen: dart run spacetimedb_sdk:generate -h http://127.0.0.1:3002 -d vocipher -o example/vocipher

import 'dart:async';
import 'dart:io';

import 'package:spacetimedb_sdk/spacetimedb.dart';
import 'vocipher/module.dart';

void main() async {
  // Create client.
  final client = SpacetimeDbClient.builder()
      .withUri('http://127.0.0.1:3002')
      .withDatabase('vocipher')
      .withAutoReconnect(true)
      .build();

  // Create typed table handles using generated code.
  final userCache = UserTableHandle.createCache();
  final serverCache = ServerTableHandle.createCache();
  final channelCache = ChannelTableHandle.createCache();
  final messageCache = MessageTableHandle.createCache();

  final users = UserTableHandle(userCache);
  final servers = ServerTableHandle(serverCache);
  final channels = ChannelTableHandle(channelCache);
  final messages = MessageTableHandle(messageCache);

  client.registerTableCache(userCache);
  client.registerTableCache(serverCache);
  client.registerTableCache(channelCache);
  client.registerTableCache(messageCache);

  // Create typed reducer access.
  final reducers = RemoteReducers(
    callReducer: client.callReducer,
    onReducer: client.onReducer,
  );

  // Register callbacks.
  final connected = Completer<void>();
  client.onIdentityReceived = (identity, token, connectionId) {
    print('Connected as: ${identity.toHex().substring(0, 16)}...');
    print('Token: ${token.value.substring(0, 20)}...');
    if (!connected.isCompleted) connected.complete();
  };

  users.onInsert((user) {
    print('User joined: ${user.username} (online: ${user.online})');
  });

  users.onUpdate((oldUser, newUser) {
    if (oldUser.username != newUser.username) {
      print('User renamed: ${oldUser.username} -> ${newUser.username}');
    }
    if (oldUser.online != newUser.online) {
      print('User ${newUser.username} is now ${newUser.online ? "online" : "offline"}');
    }
  });

  servers.onInsert((server) {
    print('Server created: ${server.name}');
  });

  messages.onInsert((msg) {
    print('New message in channel ${msg.channelId}: ${msg.content}');
  });

  // Connect.
  await client.connect();
  await connected.future;

  // Subscribe to all public tables.
  final subComplete = Completer<void>();
  client.subscribe(['SELECT * FROM user']).onApplied(() {
    print('User subscription applied (${users.count} users)');
    if (!subComplete.isCompleted) subComplete.complete();
  });

  client.subscribe(['SELECT * FROM server']);
  client.subscribe(['SELECT * FROM channel']);
  client.subscribe(['SELECT * FROM message']);

  await subComplete.future;

  // Set our username.
  print('\nSetting username to "dart_example"...');
  await reducers.setUsername('dart_example');

  // Wait a moment for the update to propagate.
  await Future<void>.delayed(const Duration(milliseconds: 500));

  // Print all users.
  print('\nOnline users:');
  for (final user in users.rows) {
    print('  ${user.username} (online: ${user.online})');
  }

  // Print all servers.
  print('\nServers:');
  for (final server in servers.rows) {
    print('  ${server.name} (id: ${server.id})');
  }

  // Disconnect.
  await client.disconnect();
  client.dispose();
  print('\nDisconnected.');
  exit(0);
}

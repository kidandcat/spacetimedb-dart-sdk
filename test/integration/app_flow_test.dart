// Integration test that simulates the Flutter app's flow:
// connect → set username → create server → create channel → send message
//
// Uses the generated vocipher bindings (same as the app).
//
// Prerequisites:
//   1. SpacetimeDB running on localhost:3002
//   2. vocipher module published

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:spacetimedb_sdk/spacetimedb.dart';

// Import generated vocipher types (same as the app does)
import '../../example/vocipher/module.dart';

const _host = 'http://127.0.0.1:3002';
const _database = 'vocipher';

void main() {
  group('App flow integration', () {
    late SpacetimeDbClient client;
    late RemoteReducers reducers;

    // Table handles (same setup as SpacetimeDbService)
    late UserTableHandle users;
    late ServerTableHandle servers;
    late ChannelTableHandle channels;
    late MessageTableHandle messages;
    late ServerMemberTableHandle serverMembers;

    setUp(() async {
      client = SpacetimeDbClient.builder()
          .withUri(_host)
          .withDatabase(_database)
          .build();

      // Create caches
      final userCache = UserTableHandle.createCache();
      final serverCache = ServerTableHandle.createCache();
      final channelCache = ChannelTableHandle.createCache();
      final messageCache = MessageTableHandle.createCache();
      final memberCache = ServerMemberTableHandle.createCache();

      // Register
      client.registerTableCache(userCache);
      client.registerTableCache(serverCache);
      client.registerTableCache(channelCache);
      client.registerTableCache(messageCache);
      client.registerTableCache(memberCache);

      // Create handles
      users = UserTableHandle(userCache);
      servers = ServerTableHandle(serverCache);
      channels = ChannelTableHandle(channelCache);
      messages = MessageTableHandle(messageCache);
      serverMembers = ServerMemberTableHandle(memberCache);

      // Create reducers
      reducers = RemoteReducers(
        callReducer: client.callReducer,
        onReducer: client.onReducer,
      );

      // Connect and wait for identity
      final identityReady = Completer<void>();
      client.onIdentityReceived = (_, __, ___) {
        if (!identityReady.isCompleted) identityReady.complete();
      };

      await client.connect();
      await identityReady.future.timeout(const Duration(seconds: 5));
    });

    tearDown(() async {
      await client.disconnect();
      client.dispose();
    });

    test('create_server reducer works with generated bindings', () async {
      // Subscribe to server + server_member tables
      final serverSub = Completer<void>();
      final memberSub = Completer<void>();

      final h1 = client.subscribe(['SELECT * FROM server']);
      h1.onApplied(() {
        if (!serverSub.isCompleted) serverSub.complete();
      });

      final h2 = client.subscribe(['SELECT * FROM server_member']);
      h2.onApplied(() {
        if (!memberSub.isCompleted) memberSub.complete();
      });

      await serverSub.future.timeout(const Duration(seconds: 10));
      await memberSub.future.timeout(const Duration(seconds: 10));

      final initialServerCount = servers.count;

      // Create server using generated reducer
      final serverName =
          'test_server_${DateTime.now().millisecondsSinceEpoch}';
      print('Creating server: $serverName');
      print(
          'Calling createServer... (servers before: $initialServerCount)');

      await reducers
          .createServer(serverName, '')
          .timeout(const Duration(seconds: 10));

      // Wait for cache update
      await Future<void>.delayed(const Duration(milliseconds: 500));

      print('Servers after: ${servers.count}');
      for (final s in servers.rows) {
        print('  Server: ${s.name} (id: ${s.id})');
      }

      // Verify server was created
      final newServer =
          servers.rows.where((s) => s.name == serverName);
      expect(newServer, isNotEmpty, reason: 'Server should appear in cache');

      // Verify we were added as a member
      final myMembership = serverMembers.rows.where((m) =>
          m.serverId == newServer.first.id &&
          m.identity == client.identity);
      expect(myMembership, isNotEmpty,
          reason: 'Should be a member of the new server');
    });

    test('full flow: set_username → create_server → create_channel → send_message',
        () async {
      // Subscribe to all relevant tables
      final subs = <Completer<void>>[];
      for (final table in [
        'user',
        'server',
        'channel',
        'message',
        'server_member'
      ]) {
        final c = Completer<void>();
        subs.add(c);
        final h = client.subscribe(['SELECT * FROM $table']);
        h.onApplied(() {
          if (!c.isCompleted) c.complete();
        });
      }

      for (final c in subs) {
        await c.future.timeout(const Duration(seconds: 10));
      }

      print('All subscriptions applied');

      // 1. Set username
      final username = 'flow_test_${DateTime.now().millisecondsSinceEpoch}';
      await reducers
          .setUsername(username)
          .timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final user = users.findByIdentity(client.identity!);
      expect(user, isNotNull, reason: 'User should exist after set_username');
      expect(user!.username, username);
      print('1. Username set: ${user.username}');

      // 2. Create server
      final serverName = 'flow_server_${DateTime.now().millisecondsSinceEpoch}';
      await reducers
          .createServer(serverName, '')
          .timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final server = servers.rows.where((s) => s.name == serverName).first;
      expect(server.ownerIdentity, client.identity);
      print('2. Server created: ${server.name} (id: ${server.id})');

      // 3. Create channel
      final channelName = 'general';
      await reducers
          .createChannel(server.id, channelName, ChannelType.text, 'Welcome!')
          .timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final channel = channels.rows
          .where((c) => c.serverId == server.id && c.name == channelName);
      expect(channel, isNotEmpty, reason: 'Channel should exist');
      print('3. Channel created: #${channel.first.name} (id: ${channel.first.id})');

      // 4. Send message
      final msgContent = 'Hello from integration test!';
      await reducers
          .sendMessage(channel.first.id, msgContent)
          .timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final msg = messages.rows.where(
          (m) => m.channelId == channel.first.id && m.content == msgContent);
      expect(msg, isNotEmpty, reason: 'Message should exist in cache');
      expect(msg.first.sender, client.identity);
      print('4. Message sent: "${msg.first.content}"');

      print('\nFull flow completed successfully!');
    });

    test('callReducer Future resolves on TransactionUpdate', () async {
      // This verifies the core issue: callReducer returns a Future
      // that should complete when the server sends TransactionUpdate.

      final subApplied = Completer<void>();
      final h = client.subscribe(['SELECT * FROM user']);
      h.onApplied(() {
        if (!subApplied.isCompleted) subApplied.complete();
      });
      await subApplied.future.timeout(const Duration(seconds: 10));

      // Listen for events to debug
      final events = <SpacetimeEvent>[];
      client.events.listen((event) {
        events.add(event);
        print('Event: ${event.runtimeType}');
      });

      final username = 'future_test_${DateTime.now().millisecondsSinceEpoch}';
      final encoder = BsatnEncoder();
      encoder.writeString(username);

      print('Calling callReducer...');
      final stopwatch = Stopwatch()..start();

      await client
          .callReducer('set_username', encoder.toBytes())
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();
      print('callReducer completed in ${stopwatch.elapsedMilliseconds}ms');
      print('Events received: ${events.length}');

      expect(stopwatch.elapsedMilliseconds, lessThan(5000),
          reason: 'callReducer should complete quickly');
    });
  },
      skip: !_isSpacetimeDbRunning()
          ? 'SpacetimeDB not running on localhost:3002'
          : null);
}

bool _isSpacetimeDbRunning() {
  try {
    final socket = Socket.connect('127.0.0.1', 3002,
        timeout: const Duration(seconds: 1));
    socket.then((s) => s.destroy());
    return true;
  } catch (_) {
    return false;
  }
}

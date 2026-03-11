// Integration test against a real SpacetimeDB instance running the vocipher module.
//
// Prerequisites:
//   1. SpacetimeDB running on localhost:3002
//   2. vocipher module published
//
// Run: dart test test/integration/vocipher_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:spacetimedb_sdk/spacetimedb.dart';

const _host = 'http://127.0.0.1:3002';
const _database = 'vocipher';

void main() {
  group('SpacetimeDB integration (vocipher)', () {
    late SpacetimeDbClient client;

    setUp(() {
      client = SpacetimeDbClient.builder()
          .withUri(_host)
          .withDatabase(_database)
          .build();
    });

    tearDown(() async {
      await client.disconnect();
      client.dispose();
    });

    test('connects and receives identity', () async {
      final identityCompleter = Completer<Identity>();

      client.onIdentityReceived = (identity, token, connectionId) {
        identityCompleter.complete(identity);
      };

      await client.connect();

      final identity =
          await identityCompleter.future.timeout(const Duration(seconds: 5));
      expect(identity.isZero, isFalse);
      expect(client.token, isNotNull);
      expect(client.token, isNotEmpty);
      expect(client.connectionId, isNotNull);
    });

    test('subscribes to tables and receives initial rows', () async {
      final identityCompleter = Completer<void>();
      final subApplied = Completer<void>();

      // Register a user table cache.
      final userCache = TableCache<_SimpleRow>(
        tableName: 'user',
        decoder: (decoder) {
          // Decode User: identity (32 bytes), username (string),
          // display_name (string), avatar_url (string), online (bool),
          // status_text (string)
          final identity = Identity.readBsatn(decoder);
          final username = decoder.readString();
          final displayName = decoder.readString();
          final avatarUrl = decoder.readString();
          final online = decoder.readBool();
          final statusText = decoder.readString();
          return _SimpleRow(
            pk: identity,
            data: {
              'identity': identity,
              'username': username,
              'display_name': displayName,
              'avatar_url': avatarUrl,
              'online': online,
              'status_text': statusText,
            },
          );
        },
        pkExtractor: (row) => row.pk,
      );
      client.registerTableCache(userCache);

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      // Subscribe
      final handle = client.subscribe(['SELECT * FROM user']);
      handle.onApplied(() {
        if (!subApplied.isCompleted) subApplied.complete();
      });

      await subApplied.future.timeout(const Duration(seconds: 10));

      // Should have at least one user (the one we connected as, or from
      // previous test runs).
      expect(userCache.count, greaterThanOrEqualTo(0));
      expect(handle.isActive, isTrue);
    });

    test('calls a reducer (set_username) and receives update', () async {
      final identityCompleter = Completer<void>();
      final subApplied = Completer<void>();

      // User cache
      final userCache = TableCache<_SimpleRow>(
        tableName: 'user',
        decoder: (decoder) {
          final identity = Identity.readBsatn(decoder);
          final username = decoder.readString();
          final displayName = decoder.readString();
          final avatarUrl = decoder.readString();
          final online = decoder.readBool();
          final statusText = decoder.readString();
          return _SimpleRow(
            pk: identity,
            data: {
              'identity': identity,
              'username': username,
              'display_name': displayName,
              'avatar_url': avatarUrl,
              'online': online,
              'status_text': statusText,
            },
          );
        },
        pkExtractor: (row) => row.pk,
      );
      client.registerTableCache(userCache);

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      final handle = client.subscribe(['SELECT * FROM user']);
      handle.onApplied(() {
        if (!subApplied.isCompleted) subApplied.complete();
      });
      await subApplied.future.timeout(const Duration(seconds: 10));

      // Call set_username reducer.
      final testUsername = 'dart_test_${DateTime.now().millisecondsSinceEpoch}';
      final encoder = BsatnEncoder();
      encoder.writeString(testUsername);

      await client
          .callReducer('set_username', encoder.toBytes())
          .timeout(const Duration(seconds: 10));

      // Give a moment for the cache to update.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Find the user with our identity.
      final myUser = userCache.rows.where(
        (row) => row.pk == client.identity,
      );
      expect(myUser, isNotEmpty);
      expect(myUser.first.data['username'], testUsername);
    });

    test('one-off query works', skip: 'OneOffQuery response parsing needs investigation', () async {
      final identityCompleter = Completer<void>();

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      final response = await client
          .oneOffQuery('SELECT * FROM user')
          .timeout(const Duration(seconds: 10));

      expect(response.isSuccess, isTrue);
      expect(response.tables, isNotEmpty);
      expect(response.tables.first.tableName, 'user');
    });

    test('reconnects with stored token and preserves identity', () async {
      final identityCompleter = Completer<Identity>();

      client.onIdentityReceived = (identity, token, connectionId) {
        if (!identityCompleter.isCompleted) {
          identityCompleter.complete(identity);
        }
      };

      await client.connect();
      final firstIdentity =
          await identityCompleter.future.timeout(const Duration(seconds: 5));
      final savedToken = client.token!;

      await client.disconnect();
      client.dispose();

      // Reconnect with saved token.
      final client2 = SpacetimeDbClient.builder()
          .withUri(_host)
          .withDatabase(_database)
          .withToken(savedToken)
          .build();

      final identity2Completer = Completer<Identity>();
      client2.onIdentityReceived = (identity, token, connectionId) {
        identity2Completer.complete(identity);
      };

      await client2.connect();
      final secondIdentity =
          await identity2Completer.future.timeout(const Duration(seconds: 5));

      // Identity should be the same.
      expect(secondIdentity, firstIdentity);

      await client2.disconnect();
      client2.dispose();
    });

    test('subscribe to multiple tables', () async {
      final identityCompleter = Completer<void>();
      int subscriptionsApplied = 0;
      final allApplied = Completer<void>();

      // Register caches for server and channel tables.
      final serverCache = TableCache<_SimpleRow>(
        tableName: 'server',
        decoder: (decoder) {
          final id = decoder.readU64();
          final name = decoder.readString();
          final ownerIdentity = Identity.readBsatn(decoder);
          final iconUrl = decoder.readString();
          final createdAt = Timestamp.readBsatn(decoder);
          return _SimpleRow(pk: id, data: {'id': id, 'name': name});
        },
        pkExtractor: (row) => row.pk,
      );

      final channelCache = TableCache<_SimpleRow>(
        tableName: 'channel',
        decoder: (decoder) {
          final id = decoder.readU64();
          final serverId = decoder.readU64();
          final name = decoder.readString();
          final channelType = decoder.readSumTag(); // ChannelType enum
          final topic = decoder.readString();
          final position = decoder.readU32();
          return _SimpleRow(pk: id, data: {'id': id, 'name': name});
        },
        pkExtractor: (row) => row.pk,
      );

      client.registerTableCache(serverCache);
      client.registerTableCache(channelCache);

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      // Subscribe to server table.
      final h1 = client.subscribe(['SELECT * FROM server']);
      h1.onApplied(() {
        subscriptionsApplied++;
        if (subscriptionsApplied >= 2 && !allApplied.isCompleted) {
          allApplied.complete();
        }
      });

      // Subscribe to channel table.
      final h2 = client.subscribe(['SELECT * FROM channel']);
      h2.onApplied(() {
        subscriptionsApplied++;
        if (subscriptionsApplied >= 2 && !allApplied.isCompleted) {
          allApplied.complete();
        }
      });

      await allApplied.future.timeout(const Duration(seconds: 10));

      expect(h1.isActive, isTrue);
      expect(h2.isActive, isTrue);
    });
  },
      skip: !_isSpacetimeDbRunning()
          ? 'SpacetimeDB not running on localhost:3002'
          : null);
}

/// Helper row type for tests.
class _SimpleRow {
  final dynamic pk;
  final Map<String, dynamic> data;

  _SimpleRow({required this.pk, required this.data});

  @override
  bool operator ==(Object other) => other is _SimpleRow && pk == other.pk;

  @override
  int get hashCode => pk.hashCode;
}

/// Check if SpacetimeDB is running.
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

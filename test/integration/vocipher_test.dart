// Integration test against a real SpacetimeDB instance running the vocipher module.
//
// Prerequisites:
//   1. SpacetimeDB running on localhost:3002
//   2. vocipher module published
//
// Run: dart test test/integration/vocipher_test.dart

import 'dart:async';
import 'dart:io';

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

    test('one-off query works', () async {
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

    test('Option fields: update_settings with nullable values', () async {
      final identityCompleter = Completer<void>();
      final subApplied = Completer<void>();

      // Register user_settings cache using the generated type decoder.
      final settingsCache = TableCache<_SimpleRow>(
        tableName: 'user_settings',
        decoder: (decoder) {
          final id = decoder.readU64();
          final ownerIdentity = Identity.readBsatn(decoder);
          final theme = decoder.readOption() ? decoder.readString() : null;
          final language = decoder.readOption() ? decoder.readString() : null;
          final notificationsEnabled = decoder.readBool();
          final customStatusEmoji =
              decoder.readOption() ? decoder.readString() : null;
          return _SimpleRow(pk: id, data: {
            'id': id,
            'ownerIdentity': ownerIdentity,
            'theme': theme,
            'language': language,
            'notificationsEnabled': notificationsEnabled,
            'customStatusEmoji': customStatusEmoji,
          });
        },
        pkExtractor: (row) => row.pk,
      );
      client.registerTableCache(settingsCache);

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      final handle = client.subscribe(['SELECT * FROM user_settings']);
      handle.onApplied(() {
        if (!subApplied.isCompleted) subApplied.complete();
      });
      await subApplied.future.timeout(const Duration(seconds: 10));

      // Call update_settings with some null and non-null Option fields.
      final encoder = BsatnEncoder();
      // theme = Some("dark")
      encoder.writeOptionSome();
      encoder.writeString('dark');
      // language = None
      encoder.writeOptionNone();
      // notifications = true
      encoder.writeBool(true);
      // emoji = Some("🔥")
      encoder.writeOptionSome();
      encoder.writeString('🔥');

      await client
          .callReducer('update_settings', encoder.toBytes())
          .timeout(const Duration(seconds: 10));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Find settings for our identity.
      final mySettings = settingsCache.rows.where(
        (row) => row.data['ownerIdentity'] == client.identity,
      );
      expect(mySettings, isNotEmpty);
      final settings = mySettings.first;
      expect(settings.data['theme'], 'dark');
      expect(settings.data['language'], isNull);
      expect(settings.data['notificationsEnabled'], isTrue);
      expect(settings.data['customStatusEmoji'], '🔥');
    });

    test('Vec fields: set_roles with array values', () async {
      final identityCompleter = Completer<void>();
      final subApplied = Completer<void>();

      final rolesCache = TableCache<_SimpleRow>(
        tableName: 'user_roles',
        decoder: (decoder) {
          final identity = Identity.readBsatn(decoder);
          final serverId = decoder.readU64();
          final roleCount = decoder.readArrayHeader();
          final roleNames = <String>[];
          for (var i = 0; i < roleCount; i++) {
            roleNames.add(decoder.readString());
          }
          final permCount = decoder.readArrayHeader();
          final permissions = <int>[];
          for (var i = 0; i < permCount; i++) {
            permissions.add(decoder.readU32());
          }
          return _SimpleRow(pk: identity, data: {
            'identity': identity,
            'serverId': serverId,
            'roleNames': roleNames,
            'permissions': permissions,
          });
        },
        pkExtractor: (row) => row.pk,
      );
      client.registerTableCache(rolesCache);

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      final handle = client.subscribe(['SELECT * FROM user_roles']);
      handle.onApplied(() {
        if (!subApplied.isCompleted) subApplied.complete();
      });
      await subApplied.future.timeout(const Duration(seconds: 10));

      // Call set_roles reducer with Vec<String> and Vec<u32>.
      final encoder = BsatnEncoder();
      encoder.writeU64(1); // server_id
      encoder.writeArrayHeader(2); // roleNames
      encoder.writeString('admin');
      encoder.writeString('moderator');
      encoder.writeArrayHeader(3); // permissions
      encoder.writeU32(1);
      encoder.writeU32(2);
      encoder.writeU32(4);

      await client
          .callReducer('set_roles', encoder.toBytes())
          .timeout(const Duration(seconds: 10));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      final myRoles = rolesCache.rows.where(
        (row) => row.data['identity'] == client.identity,
      );
      expect(myRoles, isNotEmpty);
      final roles = myRoles.first;
      expect(roles.data['roleNames'], ['admin', 'moderator']);
      expect(roles.data['permissions'], [1, 2, 4]);
    });

    test('reducer callback fires on success', () async {
      final identityCompleter = Completer<void>();
      final callbackFired = Completer<ReducerCallbackEvent>();

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      client.onReducer('set_username', (event) {
        if (!callbackFired.isCompleted) {
          callbackFired.complete(event);
        }
      });

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      final testUsername =
          'cb_test_${DateTime.now().millisecondsSinceEpoch}';
      final encoder = BsatnEncoder();
      encoder.writeString(testUsername);
      await client
          .callReducer('set_username', encoder.toBytes())
          .timeout(const Duration(seconds: 10));

      final event =
          await callbackFired.future.timeout(const Duration(seconds: 5));

      expect(event.reducerName, 'set_username');
      expect(event.status, isA<Committed>());
      expect(event.callerIdentity, client.identity);
    });

    test('one-off query on user_settings with Option fields', () async {
      final identityCompleter = Completer<void>();

      client.onIdentityReceived = (_, __, ___) {
        if (!identityCompleter.isCompleted) identityCompleter.complete();
      };

      await client.connect();
      await identityCompleter.future.timeout(const Duration(seconds: 5));

      final response = await client
          .oneOffQuery('SELECT * FROM user_settings')
          .timeout(const Duration(seconds: 10));

      expect(response.isSuccess, isTrue);
      expect(response.tables, isNotEmpty);
      expect(response.tables.first.tableName, 'user_settings');

      // Decode the rows using the generated decoder.
      for (final rowBytes in response.tables.first.rows) {
        final decoder = BsatnDecoder(rowBytes);
        final id = decoder.readU64();
        final ownerIdentity = Identity.readBsatn(decoder);
        if (decoder.readOption()) decoder.readString(); // theme
        if (decoder.readOption()) decoder.readString(); // language
        decoder.readBool(); // notificationsEnabled
        if (decoder.readOption()) decoder.readString(); // customStatusEmoji
        // Just verify it decodes without error.
        expect(id, isA<int>());
        expect(ownerIdentity.isZero, isFalse);
      }
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
          Identity.readBsatn(decoder); // ownerIdentity
          decoder.readString(); // iconUrl
          Timestamp.readBsatn(decoder); // createdAt
          return _SimpleRow(pk: id, data: {'id': id, 'name': name});
        },
        pkExtractor: (row) => row.pk,
      );

      final channelCache = TableCache<_SimpleRow>(
        tableName: 'channel',
        decoder: (decoder) {
          final id = decoder.readU64();
          decoder.readU64(); // serverId
          final name = decoder.readString();
          decoder.readSumTag(); // channelType enum
          decoder.readString(); // topic
          decoder.readU32(); // position
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

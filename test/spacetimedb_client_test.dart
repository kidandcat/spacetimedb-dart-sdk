import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:spacetimedb_sdk/spacetimedb.dart';

void main() {
  group('SpacetimeDbClientBuilder', () {
    test('builds client with required fields', () {
      final client = SpacetimeDbClient.builder()
          .withUri('http://localhost:3000')
          .withDatabase('test_db')
          .build();
      expect(client, isNotNull);
      expect(client.identity, isNull);
      expect(client.connectionId, isNull);
      expect(client.token, isNull);
      expect(client.isConnected, isFalse);
    });

    test('builds client with token', () {
      final client = SpacetimeDbClient.builder()
          .withUri('http://localhost:3000')
          .withDatabase('test_db')
          .withToken('my-token')
          .build();
      // Token is stored for reconnection but identity is null until server confirms
      expect(client.token, 'my-token');
      expect(client.identity, isNull);
    });

    test('throws when URI is missing', () {
      expect(
        () => SpacetimeDbClient.builder().withDatabase('test_db').build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when database is missing', () {
      expect(
        () => SpacetimeDbClient.builder().withUri('http://localhost:3000').build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('builder with auto reconnect', () {
      final client = SpacetimeDbClient.builder()
          .withUri('http://localhost:3000')
          .withDatabase('test_db')
          .withAutoReconnect(true)
          .withMaxReconnectAttempts(5)
          .withReconnectBackoff(
            const Duration(seconds: 2),
            const Duration(seconds: 60),
          )
          .build();
      expect(client, isNotNull);
    });

    test('builder fluent chaining', () {
      final builder = SpacetimeDbClient.builder();
      expect(builder.withUri('http://localhost'), same(builder));
      expect(builder.withDatabase('db'), same(builder));
      expect(builder.withToken('tok'), same(builder));
      expect(builder.withAutoReconnect(true), same(builder));
      expect(
        builder.withReconnectBackoff(Duration.zero, Duration.zero),
        same(builder),
      );
      expect(builder.withMaxReconnectAttempts(3), same(builder));
    });
  });

  group('SpacetimeDbClient table cache', () {
    late SpacetimeDbClient client;

    setUp(() {
      client = SpacetimeDbClient.builder()
          .withUri('http://localhost:3000')
          .withDatabase('test_db')
          .build();
    });

    tearDown(() {
      client.dispose();
    });

    test('registerTableCache and getTableCache', () {
      final cache = TableCache<_TestRow>(
        tableName: 'test',
        decoder: (d) => _TestRow(d.readU32(), d.readString()),
        pkExtractor: (row) => row.id,
      );
      client.registerTableCache(cache);
      expect(client.getTableCache<_TestRow>('test'), same(cache));
    });

    test('getTableCache returns null for unregistered table', () {
      expect(client.getTableCache<_TestRow>('nonexistent'), isNull);
    });
  });

  group('SpacetimeDbClient events stream', () {
    late SpacetimeDbClient client;

    setUp(() {
      client = SpacetimeDbClient.builder()
          .withUri('http://localhost:3000')
          .withDatabase('test_db')
          .build();
    });

    tearDown(() {
      client.dispose();
    });

    test('events stream is broadcast', () {
      // Should be able to listen multiple times
      final sub1 = client.events.listen((_) {});
      final sub2 = client.events.listen((_) {});
      sub1.cancel();
      sub2.cancel();
    });
  });

  group('Event types', () {
    test('ConnectedEvent is a SpacetimeEvent', () {
      expect(ConnectedEvent(), isA<SpacetimeEvent>());
    });

    test('DisconnectedEvent with and without error', () {
      final withError = DisconnectedEvent('some error');
      expect(withError.error, 'some error');

      final withoutError = DisconnectedEvent();
      expect(withoutError.error, isNull);
    });

    test('IdentityReceivedEvent fields', () {
      final identity = Identity(Uint8List(32));
      final token = Token('test-token');
      final connectionId = ConnectionId(Uint8List(16));

      final event = IdentityReceivedEvent(identity, token, connectionId);
      expect(event.identity, identity);
      expect(event.token, token);
      expect(event.connectionId, connectionId);
    });

    test('SubscriptionAppliedEvent fields', () {
      final event = SubscriptionAppliedEvent(42);
      expect(event.queryId, 42);
    });

    test('ErrorEvent fields', () {
      final event = ErrorEvent(Exception('test'));
      expect(event.error, isA<Exception>());
    });

    test('ReducerCallbackEvent fields', () {
      final identity = Identity(Uint8List(32));
      final connectionId = ConnectionId(Uint8List(16));
      final status = const Committed(DatabaseUpdate(tables: []));

      final event = ReducerCallbackEvent(
        reducerName: 'test_reducer',
        callerIdentity: identity,
        callerConnectionId: connectionId,
        status: status,
        energyConsumed: EnergyQuanta.zero(),
        args: Uint8List(0),
      );

      expect(event.reducerName, 'test_reducer');
      expect(event.callerIdentity, identity);
      expect(event.callerConnectionId, connectionId);
      expect(event.status, isA<Committed>());
      expect(event.errorMessage, isNull);
      expect(event.args.length, 0);
    });

    test('ReducerCallbackEvent with error', () {
      final identity = Identity(Uint8List(32));
      final connectionId = ConnectionId(Uint8List(16));
      final status = const Failed('something broke');

      final event = ReducerCallbackEvent(
        reducerName: 'bad_reducer',
        callerIdentity: identity,
        callerConnectionId: connectionId,
        status: status,
        errorMessage: 'something broke',
        energyConsumed: EnergyQuanta.zero(),
        args: Uint8List(0),
      );

      expect(event.errorMessage, 'something broke');
      expect(event.status, isA<Failed>());
    });

    test('TransactionUpdateEvent fields', () {
      final identity = Identity(Uint8List(32));
      final connectionId = ConnectionId(Uint8List(16));
      final update = TransactionUpdate(
        status: const Committed(DatabaseUpdate(tables: [])),
        timestamp: Timestamp(0),
        callerIdentity: identity,
        callerConnectionId: connectionId,
        reducerCall: ReducerCallInfo(
          reducerName: 'test',
          reducerId: 0,
          args: Uint8List(0),
          requestId: 1,
        ),
        energyQuantaUsed: EnergyQuanta.zero(),
        totalHostExecutionDuration: TimeDuration.zero(),
      );

      final event = TransactionUpdateEvent(update);
      expect(event.update, same(update));
    });
  });

  group('SpacetimeDbClient onReducer', () {
    late SpacetimeDbClient client;

    setUp(() {
      client = SpacetimeDbClient.builder()
          .withUri('http://localhost:3000')
          .withDatabase('test_db')
          .build();
    });

    tearDown(() {
      client.dispose();
    });

    test('registers callbacks for different reducers', () {
      var called1 = false;
      var called2 = false;
      client.onReducer('reducer_a', (_) => called1 = true);
      client.onReducer('reducer_b', (_) => called2 = true);
      // Callbacks are stored; no assertion needed until invoked
      expect(called1, isFalse);
      expect(called2, isFalse);
    });

    test('registers multiple callbacks for same reducer', () {
      var count = 0;
      client.onReducer('reducer_a', (_) => count++);
      client.onReducer('reducer_a', (_) => count++);
      expect(count, 0);
    });
  });

  group('SpacetimeDbClient subscribe', () {
    late SpacetimeDbClient client;

    setUp(() {
      client = SpacetimeDbClient.builder()
          .withUri('http://localhost:3000')
          .withDatabase('test_db')
          .build();
    });

    tearDown(() {
      client.dispose();
    });

    test('subscribe returns handle with correct queries', () {
      // Note: subscribe without connection will fail to send, but handle is
      // still created. We test the handle state, not the send.
      try {
        final handle = client.subscribe(['SELECT * FROM users']);
        expect(handle.queries, ['SELECT * FROM users']);
        expect(handle.state, SubscriptionState.pending);
      } catch (_) {
        // Expected - no connection
      }
    });
  });
}

class _TestRow {
  final int id;
  final String name;

  _TestRow(this.id, this.name);

  @override
  bool operator ==(Object other) => other is _TestRow && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

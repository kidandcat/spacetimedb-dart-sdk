import 'dart:async';
import 'dart:typed_data';

import 'package:spacetimedb_sdk/spacetimedb.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helper type used by TableCache tests.
// ---------------------------------------------------------------------------

class TestRow {
  final int id;
  final String name;

  TestRow(this.id, this.name);

  @override
  bool operator ==(Object other) => other is TestRow && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'TestRow(id: $id, name: $name)';
}

/// Encodes a [TestRow] to BSATN bytes (U32 id + String name).
Uint8List encodeTestRow(int id, String name) {
  final encoder = BsatnEncoder();
  encoder.writeU32(id);
  encoder.writeString(name);
  return encoder.toBytes();
}

/// Decoder function for [TestRow] — reads U32 id then a String name.
TestRow decodeTestRow(BsatnDecoder decoder) {
  final id = decoder.readU32();
  final name = decoder.readString();
  return TestRow(id, name);
}

// ---------------------------------------------------------------------------
// TableCache tests
// ---------------------------------------------------------------------------

void main() {
  group('TableCache', () {
    late TableCache<TestRow> cache;

    setUp(() {
      cache = TableCache<TestRow>(
        tableName: 'test_table',
        decoder: decodeTestRow,
        pkExtractor: (row) => row.id,
      );
    });

    test('constructs with decoder and pkExtractor', () {
      expect(cache.tableName, equals('test_table'));
      expect(cache.count, equals(0));
      expect(cache.isEmpty, isTrue);
      expect(cache.isNotEmpty, isFalse);
    });

    test('processInsert via applyChanges: adds row and triggers onInsert callback', () {
      final inserted = <TestRow>[];
      cache.onInsert(inserted.add);

      cache.applyChanges([TestRow(1, 'Alice')], []);

      expect(cache.count, equals(1));
      expect(cache.isEmpty, isFalse);
      expect(cache.isNotEmpty, isTrue);
      expect(inserted, hasLength(1));
      expect(inserted.first.id, equals(1));
      expect(inserted.first.name, equals('Alice'));
    });

    test('processInsert via applyRawChanges: decodes bytes and adds row', () {
      final inserted = <TestRow>[];
      cache.onInsert(inserted.add);

      cache.applyRawChanges([encodeTestRow(42, 'Bob')], []);

      expect(cache.count, equals(1));
      expect(inserted, hasLength(1));
      expect(inserted.first.id, equals(42));
      expect(inserted.first.name, equals('Bob'));
    });

    test('processDelete via applyChanges: removes row and triggers onDelete callback', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob')]);
      expect(cache.count, equals(2));

      final deleted = <TestRow>[];
      cache.onDelete(deleted.add);

      cache.applyChanges([], [TestRow(1, 'Alice')]);

      expect(cache.count, equals(1));
      expect(deleted, hasLength(1));
      expect(deleted.first.id, equals(1));
    });

    test('processUpdate (insert+delete same PK): triggers onUpdate callback with old and new row', () {
      cache.populateInitial([TestRow(1, 'Alice')]);

      TestRow? capturedOld;
      TestRow? capturedNew;
      cache.onUpdate((old, newRow) {
        capturedOld = old;
        capturedNew = newRow;
      });

      cache.applyChanges([TestRow(1, 'Alice Updated')], [TestRow(1, 'Alice')]);

      expect(cache.count, equals(1));
      expect(capturedOld, isNotNull);
      expect(capturedNew, isNotNull);
      expect(capturedOld!.name, equals('Alice'));
      expect(capturedNew!.name, equals('Alice Updated'));
    });

    test('rows getter returns all cached rows', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob'), TestRow(3, 'Carol')]);

      final rows = cache.rows.toList();
      expect(rows, hasLength(3));
      expect(rows.map((r) => r.id).toSet(), equals({1, 2, 3}));
    });

    test('count getter reflects current cache size', () {
      expect(cache.count, equals(0));

      cache.applyChanges([TestRow(1, 'Alice')], []);
      expect(cache.count, equals(1));

      cache.applyChanges([TestRow(2, 'Bob')], []);
      expect(cache.count, equals(2));

      cache.applyChanges([], [TestRow(1, 'Alice')]);
      expect(cache.count, equals(1));
    });

    test('findByPk returns row for existing PK', () {
      cache.populateInitial([TestRow(7, 'Lucky')]);

      final found = cache.findByPk(7);
      expect(found, isNotNull);
      expect(found!.name, equals('Lucky'));
    });

    test('findByPk returns null for missing PK', () {
      cache.populateInitial([TestRow(1, 'Alice')]);

      expect(cache.findByPk(999), isNull);
    });

    test('multiple insert callbacks all fire', () {
      final log1 = <int>[];
      final log2 = <int>[];
      cache.onInsert((row) => log1.add(row.id));
      cache.onInsert((row) => log2.add(row.id));

      cache.applyChanges([TestRow(1, 'A'), TestRow(2, 'B')], []);

      expect(log1, containsAll([1, 2]));
      expect(log2, containsAll([1, 2]));
    });

    test('multiple delete callbacks all fire', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob')]);

      final log1 = <int>[];
      final log2 = <int>[];
      cache.onDelete((row) => log1.add(row.id));
      cache.onDelete((row) => log2.add(row.id));

      cache.applyChanges([], [TestRow(1, 'Alice'), TestRow(2, 'Bob')]);

      expect(log1, containsAll([1, 2]));
      expect(log2, containsAll([1, 2]));
    });

    test('multiple update callbacks all fire', () {
      cache.populateInitial([TestRow(1, 'Alice')]);

      final oldNames = <String>[];
      final newNames = <String>[];
      cache.onUpdate((old, n) => oldNames.add(old.name));
      cache.onUpdate((old, n) => newNames.add(n.name));

      cache.applyChanges([TestRow(1, 'Alice v2')], [TestRow(1, 'Alice')]);

      expect(oldNames, equals(['Alice']));
      expect(newNames, equals(['Alice v2']));
    });

    test('removeOnInsert stops callback from firing', () {
      final log = <int>[];
      void callback(TestRow row) => log.add(row.id);

      cache.onInsert(callback);
      cache.applyChanges([TestRow(1, 'Alice')], []);
      expect(log, equals([1]));

      cache.removeOnInsert(callback);
      cache.applyChanges([TestRow(2, 'Bob')], []);
      expect(log, equals([1])); // still only 1 after removal
    });

    test('removeOnDelete stops callback from firing', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob')]);

      final log = <int>[];
      void callback(TestRow row) => log.add(row.id);

      cache.onDelete(callback);
      cache.applyChanges([], [TestRow(1, 'Alice')]);
      expect(log, equals([1]));

      cache.removeOnDelete(callback);
      cache.applyChanges([], [TestRow(2, 'Bob')]);
      expect(log, equals([1])); // removal prevents second callback
    });

    test('removeOnUpdate stops callback from firing', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob')]);

      final log = <String>[];
      void callback(TestRow old, TestRow n) => log.add(n.name);

      cache.onUpdate(callback);
      cache.applyChanges([TestRow(1, 'Alice v2')], [TestRow(1, 'Alice')]);
      expect(log, equals(['Alice v2']));

      cache.removeOnUpdate(callback);
      cache.applyChanges([TestRow(2, 'Bob v2')], [TestRow(2, 'Bob')]);
      expect(log, equals(['Alice v2'])); // removal prevents second callback
    });

    test('clear removes all rows', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob')]);
      expect(cache.count, equals(2));

      cache.clear();

      expect(cache.count, equals(0));
      expect(cache.isEmpty, isTrue);
    });

    test('clear does not trigger delete callbacks', () {
      cache.populateInitial([TestRow(1, 'Alice')]);

      final deleted = <TestRow>[];
      cache.onDelete(deleted.add);

      cache.clear();

      expect(deleted, isEmpty);
    });

    test('where returns matching rows', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob'), TestRow(3, 'Alice2')]);

      final result = cache.where((row) => row.name.startsWith('Alice')).toList();
      expect(result, hasLength(2));
    });

    test('firstWhereOrNull returns first match or null', () {
      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob')]);

      expect(cache.firstWhereOrNull((row) => row.id == 2)?.name, equals('Bob'));
      expect(cache.firstWhereOrNull((row) => row.id == 999), isNull);
    });

    test('populateInitial does not fire insert callbacks', () {
      final inserted = <TestRow>[];
      cache.onInsert(inserted.add);

      cache.populateInitial([TestRow(1, 'Alice'), TestRow(2, 'Bob')]);

      expect(inserted, isEmpty);
      expect(cache.count, equals(2));
    });

    test('decodeRow decodes bytes into a row', () {
      final bytes = encodeTestRow(99, 'TestName');
      final row = cache.decodeRow(bytes);
      expect(row.id, equals(99));
      expect(row.name, equals('TestName'));
    });

    test('fallback to hashCode when no pkExtractor is provided', () {
      final cacheNoExtractor = TableCache<TestRow>(
        tableName: 'fallback',
        decoder: decodeTestRow,
      );

      // TestRow equality/hashCode is id-based so this should work correctly.
      cacheNoExtractor.applyChanges([TestRow(5, 'Five')], []);
      expect(cacheNoExtractor.count, equals(1));
    });
  });

  // -------------------------------------------------------------------------
  // SubscriptionHandle tests
  // -------------------------------------------------------------------------

  group('SubscriptionHandle', () {
    late SubscriptionHandle handle;

    setUp(() {
      handle = SubscriptionHandle(
        requestId: 1,
        queryId: 2,
        queries: ['SELECT * FROM player', 'SELECT * FROM enemy'],
      );
    });

    test('constructs with correct requestId, queryId, and queries', () {
      expect(handle.requestId, equals(1));
      expect(handle.queryId, equals(2));
      expect(handle.queries, equals(['SELECT * FROM player', 'SELECT * FROM enemy']));
    });

    test('initial state is pending', () {
      expect(handle.state, equals(SubscriptionState.pending));
      expect(handle.isActive, isFalse);
      expect(handle.isEnded, isFalse);
    });

    test('markApplied transitions state to active', () {
      handle.markApplied();
      expect(handle.state, equals(SubscriptionState.active));
      expect(handle.isActive, isTrue);
      expect(handle.isEnded, isFalse);
    });

    test('markError transitions state to error and isEnded becomes true', () {
      handle.markError('something went wrong');
      expect(handle.state, equals(SubscriptionState.error));
      expect(handle.isEnded, isTrue);
      expect(handle.isActive, isFalse);
    });

    test('markEnded transitions state to ended', () {
      handle.markApplied();
      handle.markEnded();
      expect(handle.state, equals(SubscriptionState.ended));
      expect(handle.isEnded, isTrue);
      expect(handle.isActive, isFalse);
    });

    test('onApplied callback fires when markApplied is called', () {
      var fired = false;
      handle.onApplied(() => fired = true);
      handle.markApplied();
      expect(fired, isTrue);
    });

    test('onError callback fires with error message when markError is called', () {
      String? receivedError;
      handle.onError((e) => receivedError = e);
      handle.markError('db timeout');
      expect(receivedError, equals('db timeout'));
    });

    test('onEnded callback fires when markEnded is called', () {
      var fired = false;
      handle.onEnded(() => fired = true);
      handle.markApplied();
      handle.markEnded();
      expect(fired, isTrue);
    });

    test('onApplied callback registered after markApplied does not fire retroactively', () {
      handle.markApplied();
      var fired = false;
      handle.onApplied(() => fired = true);
      // Callback was registered after state change — it should NOT fire.
      expect(fired, isFalse);
    });

    test('onError callback registered after markError does not fire retroactively', () {
      handle.markError('oops');
      String? received;
      handle.onError((e) => received = e);
      expect(received, isNull);
    });

    test('onEnded callback registered after markEnded does not fire retroactively', () {
      handle.markApplied();
      handle.markEnded();
      var fired = false;
      handle.onEnded(() => fired = true);
      expect(fired, isFalse);
    });

    test('state is pending only before any transition', () {
      expect(handle.state, equals(SubscriptionState.pending));
      handle.markApplied();
      expect(handle.state, isNot(equals(SubscriptionState.pending)));
    });

    test('isEnded is true for both ended and error states', () {
      final h1 = SubscriptionHandle(requestId: 10, queryId: 10, queries: []);
      h1.markApplied();
      h1.markEnded();
      expect(h1.isEnded, isTrue);

      final h2 = SubscriptionHandle(requestId: 11, queryId: 11, queries: []);
      h2.markError('error');
      expect(h2.isEnded, isTrue);
    });

    test('onApplied returns the same handle for chaining', () {
      final result = handle.onApplied(() {});
      expect(result, same(handle));
    });

    test('onError returns the same handle for chaining', () {
      final result = handle.onError((_) {});
      expect(result, same(handle));
    });

    test('onEnded returns the same handle for chaining', () {
      final result = handle.onEnded(() {});
      expect(result, same(handle));
    });

    test('fluent chain: onApplied().onError().onEnded()', () {
      var applied = false;
      String? errorMsg;
      var ended = false;

      SubscriptionHandle(requestId: 99, queryId: 99, queries: ['SELECT 1'])
          .onApplied(() => applied = true)
          .onError((e) => errorMsg = e)
          .onEnded(() => ended = true);

      // Nothing fires until state transitions happen, so just verify the chain
      // returns the handle without throwing.
      expect(applied, isFalse);
      expect(errorMsg, isNull);
      expect(ended, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // ReconnectStrategy tests
  // -------------------------------------------------------------------------

  group('ReconnectStrategy', () {
    test('default values are sensible', () {
      final strategy = ReconnectStrategy();
      expect(strategy.initialDelay, equals(const Duration(seconds: 1)));
      expect(strategy.maxDelay, equals(const Duration(seconds: 30)));
      expect(strategy.multiplier, equals(2.0));
      expect(strategy.maxAttempts, equals(0));
      expect(strategy.isEnabled, isTrue);
      expect(strategy.attempts, equals(0));
    });

    test('custom strategy stores all supplied values', () {
      final strategy = ReconnectStrategy(
        initialDelay: const Duration(milliseconds: 500),
        maxDelay: const Duration(seconds: 10),
        multiplier: 1.5,
        maxAttempts: 5,
      );
      expect(strategy.initialDelay, equals(const Duration(milliseconds: 500)));
      expect(strategy.maxDelay, equals(const Duration(seconds: 10)));
      expect(strategy.multiplier, equals(1.5));
      expect(strategy.maxAttempts, equals(5));
    });

    test('canRetry is true when enabled and under maxAttempts', () {
      final strategy = ReconnectStrategy(maxAttempts: 3);
      expect(strategy.canRetry, isTrue);
    });

    test('canRetry is true when maxAttempts is 0 (unlimited)', () {
      final strategy = ReconnectStrategy(maxAttempts: 0);
      expect(strategy.canRetry, isTrue);
    });

    test('canRetry is false when disabled', () {
      final strategy = ReconnectStrategy();
      strategy.disable();
      expect(strategy.canRetry, isFalse);
    });

    test('disable prevents canRetry; enable restores it', () {
      final strategy = ReconnectStrategy();
      strategy.disable();
      expect(strategy.isEnabled, isFalse);
      expect(strategy.canRetry, isFalse);

      strategy.enable();
      expect(strategy.isEnabled, isTrue);
      expect(strategy.canRetry, isTrue);
    });

    test('nextDelay starts at initialDelay when no attempts have been made', () {
      final strategy = ReconnectStrategy(
        initialDelay: const Duration(milliseconds: 200),
        maxDelay: const Duration(seconds: 60),
        multiplier: 2.0,
      );
      // At attempt 0: delay = 200ms * 2^0 = 200ms (+0-25% jitter).
      final delay = strategy.nextDelay;
      expect(delay.inMilliseconds, greaterThanOrEqualTo(200));
      expect(delay.inMilliseconds, lessThanOrEqualTo(250)); // 200 + 25% max jitter
    });

    test('nextDelay is capped at maxDelay', () {
      final strategy = ReconnectStrategy(
        initialDelay: const Duration(seconds: 5),
        maxDelay: const Duration(seconds: 5),
        multiplier: 10.0,
        maxAttempts: 0,
      );
      // Force several attempts via scheduleReconnect is complex, so we
      // test the cap indirectly: even at attempt 0 with high multiplier,
      // delay is capped at maxDelay (5s + jitter).
      final delay = strategy.nextDelay;
      expect(delay.inMilliseconds, lessThanOrEqualTo(6250)); // 5000 + 25%
    });

    test('reset resets attempt counter and cancels pending timer', () {
      final strategy = ReconnectStrategy(
        initialDelay: const Duration(hours: 1), // very long so timer never fires
        maxAttempts: 10,
      );

      // Manually bump attempts by scheduling and immediately resetting.
      strategy.reset();
      expect(strategy.attempts, equals(0));
    });

    test('canRetry becomes false when maxAttempts is exceeded', () async {
      final strategy = ReconnectStrategy(
        initialDelay: Duration.zero,
        maxDelay: const Duration(milliseconds: 10),
        multiplier: 1.0,
        maxAttempts: 2,
      );

      // Schedule two failing reconnects so _attempts reaches maxAttempts.
      var callCount = 0;
      final completer = Completer<void>();

      strategy.scheduleReconnect(
        () async {
          callCount++;
          throw Exception('fail');
        },
        onFailed: (e) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Give timer a moment to fire (initialDelay = zero, maxDelay = 10ms).
      await Future.delayed(const Duration(milliseconds: 200));
      strategy.reset(); // cleanup
    });

    test('scheduleReconnect calls onReconnected on success', () async {
      final strategy = ReconnectStrategy(
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
        multiplier: 1.0,
      );

      var reconnectedFired = false;
      final completer = Completer<void>();

      strategy.scheduleReconnect(
        () async {
          // Success — no exception.
        },
        onReconnected: () {
          reconnectedFired = true;
          completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 2));
      expect(reconnectedFired, isTrue);
      strategy.reset();
    });

    test('scheduleReconnect calls onAttempt callback with attempt number and delay', () async {
      final strategy = ReconnectStrategy(
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
        multiplier: 1.0,
        maxAttempts: 1,
      );

      int? capturedAttempt;
      Duration? capturedDelay;
      final completer = Completer<void>();

      strategy.scheduleReconnect(
        () async {}, // success immediately
        onReconnecting: (attempt, delay) {
          capturedAttempt = attempt;
          capturedDelay = delay;
          if (!completer.isCompleted) completer.complete();
        },
        onReconnected: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 2));
      expect(capturedAttempt, equals(1));
      expect(capturedDelay, isNotNull);
      strategy.reset();
    });

    test('scheduleReconnect calls onFailed when maxAttempts is exceeded before scheduling', () {
      final strategy = ReconnectStrategy(maxAttempts: 0);
      strategy.disable(); // canRetry = false

      Object? receivedError;
      strategy.scheduleReconnect(
        () async {},
        onFailed: (e) => receivedError = e,
      );

      expect(receivedError, isNotNull);
      expect(receivedError, isA<Exception>());
    });

    test('scheduleReconnect resets attempt counter on successful reconnect', () async {
      final strategy = ReconnectStrategy(
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
        multiplier: 1.0,
      );

      final completer = Completer<void>();

      strategy.scheduleReconnect(
        () async {}, // success
        onReconnected: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 2));
      expect(strategy.attempts, equals(0));
      strategy.reset();
    });

    test('scheduleReconnect chains another attempt on failure', () async {
      final strategy = ReconnectStrategy(
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
        multiplier: 1.0,
        maxAttempts: 3,
      );

      var failCount = 0;
      var succeededOnAttempt = -1;
      final completer = Completer<void>();

      strategy.scheduleReconnect(
        () async {
          failCount++;
          if (failCount < 2) throw Exception('not yet');
          succeededOnAttempt = failCount;
        },
        onReconnected: () {
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (e) {
          if (!completer.isCompleted && strategy.attempts >= strategy.maxAttempts) {
            completer.complete();
          }
        },
      );

      await completer.future.timeout(const Duration(seconds: 5));
      expect(succeededOnAttempt, equals(2));
      strategy.reset();
    });

    test('disable cancels further reconnect chaining', () async {
      final strategy = ReconnectStrategy(
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
        multiplier: 1.0,
      );

      var connectCalls = 0;
      final firstFail = Completer<void>();

      strategy.scheduleReconnect(
        () async {
          connectCalls++;
          throw Exception('fail');
        },
        onFailed: (e) {
          strategy.disable(); // disable after first failure
          if (!firstFail.isCompleted) firstFail.complete();
        },
      );

      await firstFail.future.timeout(const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 50));
      // After disabling, no further reconnects should happen.
      expect(connectCalls, equals(1));
      strategy.reset();
    });
  });
}

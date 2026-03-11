import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../identity.dart';
import '../protocol/client_messages.dart';
import '../protocol/server_messages.dart';
import '../protocol/types.dart';
import 'connection.dart';
import 'reconnect.dart';
import 'subscription.dart';
import 'table_cache.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Base class for events emitted by [SpacetimeDbClient].
sealed class SpacetimeEvent {}

/// Emitted when the WebSocket connection is established.
class ConnectedEvent extends SpacetimeEvent {}

/// Emitted when the WebSocket connection is lost.
class DisconnectedEvent extends SpacetimeEvent {
  /// The error or reason for disconnection, if available.
  final Object? error;
  DisconnectedEvent([this.error]);
}

/// Emitted when the server sends an identity/token pair for this connection.
class IdentityReceivedEvent extends SpacetimeEvent {
  final Identity identity;
  final Token token;
  final ConnectionId connectionId;
  IdentityReceivedEvent(this.identity, this.token, this.connectionId);
}

/// Emitted when a subscription's initial rows have been applied to caches.
class SubscriptionAppliedEvent extends SpacetimeEvent {
  final int queryId;
  SubscriptionAppliedEvent(this.queryId);
}

/// Emitted for every committed or failed transaction the client receives.
class TransactionUpdateEvent extends SpacetimeEvent {
  final TransactionUpdate update;
  TransactionUpdateEvent(this.update);
}

/// Emitted when a reducer call result is received.
class ReducerCallbackEvent extends SpacetimeEvent {
  final String reducerName;
  final Identity callerIdentity;
  final ConnectionId callerConnectionId;
  final UpdateStatus status;
  final String? errorMessage;
  final EnergyQuanta energyConsumed;
  final Uint8List args;
  ReducerCallbackEvent({
    required this.reducerName,
    required this.callerIdentity,
    required this.callerConnectionId,
    required this.status,
    this.errorMessage,
    required this.energyConsumed,
    required this.args,
  });
}

/// Emitted when a connection-level or protocol-level error occurs.
class ErrorEvent extends SpacetimeEvent {
  final Object error;
  ErrorEvent(this.error);
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// The main SpacetimeDB client.
///
/// Manages a single WebSocket connection to a SpacetimeDB database, handles
/// subscriptions, reducer calls, one-off queries, table caching with
/// insert/update/delete callbacks, and optional automatic reconnection.
///
/// Use [SpacetimeDbClient.builder] to construct an instance:
///
/// ```dart
/// final client = SpacetimeDbClient.builder()
///     .withUri('http://localhost:3000')
///     .withDatabase('my_module')
///     .withAutoReconnect(true)
///     .build();
///
/// client.registerTableCache(playerCache);
///
/// await client.connect();
/// client.subscribe(['SELECT * FROM Player']);
/// ```
class SpacetimeDbClient {
  final Uri _uri;
  final String _database;
  String? _token;

  Identity? _identity;
  ConnectionId? _connectionId;

  final SpacetimeConnection _connection = SpacetimeConnection();
  final ReconnectStrategy? _reconnectStrategy;

  int _nextRequestId = 1;
  int _nextQueryId = 1;

  // Subscription bookkeeping.
  final Map<int, SubscriptionHandle> _subscriptionsByRequestId = {};
  final Map<int, SubscriptionHandle> _subscriptionsByQueryId = {};
  final List<SubscriptionHandle> _activeSubscriptions = [];

  // Table caches keyed by table name.
  final Map<String, TableCache<dynamic>> _tableCaches = {};

  // Reducer-specific callbacks keyed by reducer name.
  final Map<String, List<void Function(ReducerCallbackEvent)>>
      _reducerCallbacks = {};

  // Broadcast event stream.
  final _eventController = StreamController<SpacetimeEvent>.broadcast();

  // Pending one-off queries keyed by hex message ID.
  final Map<String, Completer<OneOffQueryResponse>> _pendingOneOffQueries = {};

  // Pending reducer calls keyed by request ID.
  final Map<int, Completer<void>> _pendingReducerCalls = {};

  // ---- Public getters ----

  /// Stream of [SpacetimeEvent]s for reactive listeners.
  Stream<SpacetimeEvent> get events => _eventController.stream;

  /// The identity assigned to this client by the server, or `null` if not yet
  /// received.
  Identity? get identity => _identity;

  /// The connection ID for the current WebSocket session, or `null`.
  ConnectionId? get connectionId => _connectionId;

  /// The authentication token, or `null` if the client has not yet connected.
  String? get token => _token;

  /// Whether the WebSocket connection is currently open.
  bool get isConnected => _connection.isConnected;

  // ---- Direct callbacks (alternative to [events] stream) ----

  /// Called when the WebSocket connection is established.
  void Function()? onConnect;

  /// Called when the WebSocket connection is lost.
  void Function(Object? error)? onDisconnect;

  /// Called when the server provides identity and token information.
  void Function(Identity identity, Token token, ConnectionId connectionId)?
      onIdentityReceived;

  /// Called before each reconnect attempt with the attempt number and delay.
  void Function(int attempt, Duration delay)? onReconnecting;

  /// Called after a successful reconnect.
  void Function()? onReconnected;

  /// Called when reconnection ultimately fails (max attempts exceeded).
  void Function(Object error)? onReconnectFailed;

  // ---- Construction ----

  SpacetimeDbClient._({
    required Uri uri,
    required String database,
    String? token,
    ReconnectStrategy? reconnectStrategy,
  })  : _uri = uri,
        _database = database,
        _token = token,
        _reconnectStrategy = reconnectStrategy;

  /// Returns a [SpacetimeDbClientBuilder] for fluent construction.
  static SpacetimeDbClientBuilder builder() => SpacetimeDbClientBuilder();

  // ---- Table cache registration ----

  /// Registers a [TableCache] so the client can populate it from subscription
  /// and transaction messages.
  void registerTableCache<T>(TableCache<T> cache) {
    _tableCaches[cache.tableName] = cache;
  }

  /// Returns the [TableCache] for the given [tableName], or `null` if no cache
  /// has been registered for that table.
  TableCache<T>? getTableCache<T>(String tableName) =>
      _tableCaches[tableName] as TableCache<T>?;

  // ---- Connection lifecycle ----

  /// Opens the WebSocket connection and begins listening for server messages.
  Future<void> connect() async {
    final path = '/v1/database/$_database/subscribe';
    final uri = _uri.replace(path: path);

    await _connection.connect(uri: uri, token: _token);
    _listenToConnection();

    _eventController.add(ConnectedEvent());
    onConnect?.call();
  }

  /// Closes the connection and disables automatic reconnection.
  Future<void> disconnect() async {
    _reconnectStrategy?.disable();
    await _connection.close();
  }

  /// Releases all resources (stream controllers, WebSocket).
  ///
  /// After calling this the client instance must not be reused.
  void dispose() {
    _reconnectStrategy?.disable();
    _connection.dispose();
    _eventController.close();
  }

  // ---- Subscriptions ----

  /// Subscribes to the given SQL [queries].
  ///
  /// Returns a [SubscriptionHandle] that can be used to register lifecycle
  /// callbacks and to unsubscribe later.
  SubscriptionHandle subscribe(List<String> queries) {
    final requestId = _nextRequestId++;
    final queryId = _nextQueryId++;

    final handle = SubscriptionHandle(
      requestId: requestId,
      queryId: queryId,
      queries: queries,
    );

    _subscriptionsByRequestId[requestId] = handle;
    _subscriptionsByQueryId[queryId] = handle;

    for (final query in queries) {
      _connection.send(SubscribeSingle(
        query: query,
        requestId: requestId,
        queryId: queryId,
      ));
    }

    return handle;
  }

  /// Unsubscribes from a previously active subscription.
  void unsubscribe(SubscriptionHandle handle) {
    final requestId = _nextRequestId++;
    _subscriptionsByRequestId[requestId] = handle;
    _connection.send(UnsubscribeMsg(
      requestId: requestId,
      queryId: handle.queryId,
    ));
  }

  // ---- Reducer calls ----

  /// Calls a named reducer with BSATN-encoded arguments.
  ///
  /// The returned [Future] completes when the server confirms the reducer call.
  /// It completes with an error if the reducer fails or runs out of energy.
  Future<void> callReducer(String name, Uint8List args) {
    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pendingReducerCalls[requestId] = completer;

    _connection.send(CallReducer(
      reducer: name,
      args: args,
      requestId: requestId,
    ));

    return completer.future;
  }

  /// Registers a callback invoked whenever the reducer named [reducerName]
  /// completes (successfully or with an error).
  void onReducer(
    String reducerName,
    void Function(ReducerCallbackEvent) callback,
  ) {
    _reducerCallbacks.putIfAbsent(reducerName, () => []).add(callback);
  }

  // ---- One-off queries ----

  /// Executes a one-off SQL query that is not tied to a subscription.
  ///
  /// Returns a [Future] that resolves with the query response or rejects if
  /// the server reports an error.
  Future<OneOffQueryResponse> oneOffQuery(String sql) {
    // Generate a random 16-byte message ID.
    final messageId = Uint8List(16);
    final random = Random.secure();
    for (var i = 0; i < 16; i++) {
      messageId[i] = random.nextInt(256);
    }

    final hex = _bytesToHex(messageId);
    final completer = Completer<OneOffQueryResponse>();
    _pendingOneOffQueries[hex] = completer;

    _connection.send(OneOffQuery(
      messageId: messageId,
      queryString: sql,
    ));

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Internal: message handling
  // ---------------------------------------------------------------------------

  void _listenToConnection() {
    _connection.messages.listen(_handleMessage);
    _connection.errors.listen((error) {
      _eventController.add(ErrorEvent(error));
      if (error == 'Connection closed') {
        _handleDisconnect();
      }
    });
  }

  void _handleMessage(ServerMessage msg) {
    switch (msg) {
      case IdentityToken():
        _handleIdentityToken(msg);
      case SubscribeApplied():
        _handleSubscribeApplied(msg);
      case InitialSubscription():
        _handleInitialSubscription(msg);
      case TransactionUpdate():
        _handleTransactionUpdate(msg);
      case TransactionUpdateLight():
        _handleTransactionUpdateLight(msg);
      case UnsubscribeApplied():
        _handleUnsubscribeApplied(msg);
      case SubscriptionError():
        _handleSubscriptionError(msg);
      case OneOffQueryResponse():
        _handleOneOffQueryResponse(msg);
      case SubscribeMultiApplied():
        _handleSubscribeMultiApplied(msg);
      case UnsubscribeMultiApplied():
        _handleUnsubscribeMultiApplied(msg);
      case ProcedureResult():
        _handleProcedureResult(msg);
    }
  }

  void _handleIdentityToken(IdentityToken msg) {
    _identity = msg.identity;
    _token = msg.token;
    _connectionId = msg.connectionId;
    final token = Token(msg.token);
    _eventController.add(
      IdentityReceivedEvent(msg.identity, token, msg.connectionId),
    );
    onIdentityReceived?.call(msg.identity, token, msg.connectionId);
  }

  void _handleSubscribeApplied(SubscribeApplied msg) {
    _applySubscribeRows(msg.rows);

    final handle = _subscriptionsByRequestId[msg.requestId];
    if (handle != null) {
      if (!_activeSubscriptions.contains(handle)) {
        _activeSubscriptions.add(handle);
      }
      handle.markApplied();
    }
    _eventController.add(SubscriptionAppliedEvent(msg.queryId));
  }

  void _handleInitialSubscription(InitialSubscription msg) {
    _applyDatabaseUpdate(msg.databaseUpdate);

    final handle = _subscriptionsByRequestId[msg.requestId];
    if (handle != null) {
      if (!_activeSubscriptions.contains(handle)) {
        _activeSubscriptions.add(handle);
      }
      handle.markApplied();
    }
  }

  void _handleTransactionUpdate(TransactionUpdate msg) {
    if (msg.status is Committed) {
      final committed = msg.status as Committed;
      _applyDatabaseUpdate(committed.databaseUpdate);
    }

    // Fire reducer-specific callbacks.
    final reducerName = msg.reducerCall.reducerName;
    final callbacks = _reducerCallbacks[reducerName];
    if (callbacks != null) {
      final event = ReducerCallbackEvent(
        reducerName: reducerName,
        callerIdentity: msg.callerIdentity,
        callerConnectionId: msg.callerConnectionId,
        status: msg.status,
        errorMessage:
            msg.status is Failed ? (msg.status as Failed).errorMessage : null,
        energyConsumed: msg.energyQuantaUsed,
        args: msg.reducerCall.args,
      );
      for (final cb in callbacks) {
        cb(event);
      }
    }

    // Resolve the pending reducer call future.
    final completer = _pendingReducerCalls.remove(msg.reducerCall.requestId);
    if (completer != null) {
      if (msg.status is Committed) {
        completer.complete();
      } else if (msg.status is Failed) {
        completer.completeError(
          Exception((msg.status as Failed).errorMessage),
        );
      } else {
        completer.completeError(Exception('Reducer out of energy'));
      }
    }

    _eventController.add(TransactionUpdateEvent(msg));
  }

  void _handleUnsubscribeApplied(UnsubscribeApplied msg) {
    final handle = _subscriptionsByRequestId.remove(msg.requestId);
    if (handle != null) {
      _activeSubscriptions.remove(handle);
      _subscriptionsByQueryId.remove(handle.queryId);
      handle.markEnded();
    }
  }

  void _handleSubscriptionError(SubscriptionError msg) {
    if (msg.requestId != null) {
      final handle = _subscriptionsByRequestId.remove(msg.requestId);
      if (handle != null) {
        _subscriptionsByQueryId.remove(handle.queryId);
        handle.markError(msg.error);
      }
    }
    _eventController.add(ErrorEvent(Exception(msg.error)));
  }

  void _handleOneOffQueryResponse(OneOffQueryResponse msg) {
    final hex = _bytesToHex(msg.messageId);
    final completer = _pendingOneOffQueries.remove(hex);
    if (completer != null) {
      if (msg.isError) {
        completer.completeError(Exception(msg.error));
      } else {
        completer.complete(msg);
      }
    }
  }

  void _handleTransactionUpdateLight(TransactionUpdateLight msg) {
    _applyDatabaseUpdate(msg.update);

    // Resolve the pending reducer call future if any.
    final completer = _pendingReducerCalls.remove(msg.requestId);
    completer?.complete();
  }

  void _handleSubscribeMultiApplied(SubscribeMultiApplied msg) {
    _applyDatabaseUpdate(msg.update);

    final handle = _subscriptionsByRequestId[msg.requestId];
    if (handle != null) {
      if (!_activeSubscriptions.contains(handle)) {
        _activeSubscriptions.add(handle);
      }
      handle.markApplied();
    }
    _eventController.add(SubscriptionAppliedEvent(msg.queryId));
  }

  void _handleUnsubscribeMultiApplied(UnsubscribeMultiApplied msg) {
    final handle = _subscriptionsByRequestId.remove(msg.requestId);
    if (handle != null) {
      _activeSubscriptions.remove(handle);
      _subscriptionsByQueryId.remove(handle.queryId);
      handle.markEnded();
    }
  }

  void _handleProcedureResult(ProcedureResult msg) {
    if (msg.status is ProcedureCommitted) {
      final committed = msg.status as ProcedureCommitted;
      _applyDatabaseUpdate(committed.databaseUpdate);
    }

    // Resolve the pending reducer/procedure call future.
    final completer = _pendingReducerCalls.remove(msg.requestId);
    if (completer != null) {
      if (msg.status is ProcedureCommitted) {
        completer.complete();
      } else if (msg.status is ProcedureFailed) {
        completer.completeError(
          Exception((msg.status as ProcedureFailed).errorMessage),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: cache mutation helpers
  // ---------------------------------------------------------------------------

  void _applySubscribeRows(SubscribeRows rows) {
    _applyTableUpdate(rows.tableRows);
  }

  void _applyDatabaseUpdate(DatabaseUpdate update) {
    for (final tableUpdate in update.tables) {
      _applyTableUpdate(tableUpdate);
    }
  }

  void _applyTableUpdate(TableUpdate tableUpdate) {
    final cache = _tableCaches[tableUpdate.tableName];
    if (cache == null) return;

    for (final compUpdate in tableUpdate.updates) {
      final queryUpdate = compUpdate.resolve();

      final insertBytes = queryUpdate.inserts.extractRows();
      final deleteBytes = queryUpdate.deletes.extractRows();

      cache.applyRawChanges(insertBytes, deleteBytes);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: reconnection
  // ---------------------------------------------------------------------------

  void _handleDisconnect() {
    onDisconnect?.call(null);
    _eventController.add(DisconnectedEvent());

    if (_reconnectStrategy != null && _reconnectStrategy!.canRetry) {
      _reconnectStrategy!.scheduleReconnect(
        _reconnect,
        onReconnecting: onReconnecting,
        onReconnected: () {
          onReconnected?.call();
          _resubscribe();
        },
        onFailed: (error) {
          onReconnectFailed?.call(error);
          _eventController.add(ErrorEvent(error));
        },
      );
    }
  }

  Future<void> _reconnect() async {
    final path = '/v1/database/$_database/subscribe';
    final uri = _uri.replace(path: path);

    await _connection.connect(uri: uri, token: _token);
    _listenToConnection();

    _eventController.add(ConnectedEvent());
    onConnect?.call();
  }

  void _resubscribe() {
    for (final handle in _activeSubscriptions) {
      for (final query in handle.queries) {
        _connection.send(SubscribeSingle(
          query: query,
          requestId: handle.requestId,
          queryId: handle.queryId,
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

// ---------------------------------------------------------------------------
// Builder
// ---------------------------------------------------------------------------

/// Fluent builder for [SpacetimeDbClient].
///
/// ```dart
/// final client = SpacetimeDbClient.builder()
///     .withUri('http://localhost:3000')
///     .withDatabase('my_module')
///     .withToken(savedToken)
///     .withAutoReconnect(true)
///     .build();
/// ```
class SpacetimeDbClientBuilder {
  Uri? _uri;
  String? _database;
  String? _token;
  bool _autoReconnect = false;
  Duration _reconnectInitialDelay = const Duration(seconds: 1);
  Duration _reconnectMaxDelay = const Duration(seconds: 30);
  int _maxReconnectAttempts = 0;

  /// Sets the base URI of the SpacetimeDB server.
  SpacetimeDbClientBuilder withUri(String uri) {
    _uri = Uri.parse(uri);
    return this;
  }

  /// Sets the database (module) name to connect to.
  SpacetimeDbClientBuilder withDatabase(String db) {
    _database = db;
    return this;
  }

  /// Sets an existing authentication token for reconnecting as the same
  /// identity.
  SpacetimeDbClientBuilder withToken(String? token) {
    _token = token;
    return this;
  }

  /// Enables or disables automatic reconnection on disconnect.
  SpacetimeDbClientBuilder withAutoReconnect(bool enabled) {
    _autoReconnect = enabled;
    return this;
  }

  /// Configures the exponential-backoff delays for reconnection.
  SpacetimeDbClientBuilder withReconnectBackoff(
    Duration initial,
    Duration max,
  ) {
    _reconnectInitialDelay = initial;
    _reconnectMaxDelay = max;
    return this;
  }

  /// Sets the maximum number of reconnect attempts (`0` = unlimited).
  SpacetimeDbClientBuilder withMaxReconnectAttempts(int max) {
    _maxReconnectAttempts = max;
    return this;
  }

  /// Builds the [SpacetimeDbClient] instance.
  ///
  /// Throws [ArgumentError] if required fields ([withUri], [withDatabase])
  /// have not been set.
  SpacetimeDbClient build() {
    if (_uri == null) {
      throw ArgumentError('URI is required. Call withUri() before build().');
    }
    if (_database == null) {
      throw ArgumentError(
        'Database name is required. Call withDatabase() before build().',
      );
    }

    return SpacetimeDbClient._(
      uri: _uri!,
      database: _database!,
      token: _token,
      reconnectStrategy: _autoReconnect
          ? ReconnectStrategy(
              initialDelay: _reconnectInitialDelay,
              maxDelay: _reconnectMaxDelay,
              maxAttempts: _maxReconnectAttempts,
            )
          : null,
    );
  }
}

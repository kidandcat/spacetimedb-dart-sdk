import 'dart:io';
import 'dart:typed_data';

import '../bsatn/bsatn.dart';
import '../identity.dart';
import 'types.dart';

/// Base class for all server-to-client messages (v1 protocol).
///
/// Server messages are prefixed with a 1-byte compression tag, followed by
/// the BSATN-encoded sum type. The compression byte indicates:
/// - 0: no compression
/// - 1: Brotli (not supported)
/// - 2: Gzip
sealed class ServerMessage {
  const ServerMessage();

  /// Decodes a server message from raw bytes (including the compression prefix).
  ///
  /// The first byte is the compression tag:
  /// - 0: uncompressed BSATN follows
  /// - 1: Brotli-compressed BSATN (throws [UnsupportedError])
  /// - 2: Gzip-compressed BSATN
  ///
  /// The remaining bytes (after decompression) are the BSATN sum type with a
  /// u8 tag identifying the message variant.
  static ServerMessage decode(Uint8List rawBytes) {
    if (rawBytes.isEmpty) {
      throw BsatnDecodeException('Empty server message');
    }

    final compressionTag = rawBytes[0];
    Uint8List decompressed;

    switch (compressionTag) {
      case 0:
        decompressed = Uint8List.sublistView(rawBytes, 1);
        break;
      case 1:
        throw UnsupportedError(
          'Brotli decompression is not supported. '
          'Configure the server to use compression=none or gzip.',
        );
      case 2:
        decompressed = Uint8List.fromList(
          gzip.decode(Uint8List.sublistView(rawBytes, 1)),
        );
        break;
      default:
        throw BsatnDecodeException(
          'Unknown compression tag: $compressionTag',
        );
    }

    final decoder = BsatnDecoder(decompressed);
    final tag = decoder.readSumTag();

    switch (tag) {
      case 0:
        return InitialSubscription._decode(decoder);
      case 1:
        return TransactionUpdate._decode(decoder);
      case 2:
        return TransactionUpdateLight._decode(decoder);
      case 3:
        return IdentityToken._decode(decoder);
      case 4:
        return OneOffQueryResponse._decode(decoder);
      case 5:
        return SubscribeApplied._decode(decoder);
      case 6:
        return UnsubscribeApplied._decode(decoder);
      case 7:
        return SubscriptionError._decode(decoder);
      case 8:
        return SubscribeMultiApplied._decode(decoder);
      case 9:
        return UnsubscribeMultiApplied._decode(decoder);
      case 10:
        return ProcedureResult._decode(decoder);
      default:
        throw BsatnDecodeException('Unknown server message tag: $tag');
    }
  }
}

/// Server response to the initial subscription, containing the current
/// state of all subscribed tables (tag 0).
///
/// Fields:
/// - database_update: DatabaseUpdate
/// - request_id: u32
/// - total_host_execution_duration: TimeDuration (i64 nanoseconds)
class InitialSubscription extends ServerMessage {
  final DatabaseUpdate databaseUpdate;
  final int requestId;
  final TimeDuration totalHostExecutionDuration;

  const InitialSubscription({
    required this.databaseUpdate,
    required this.requestId,
    required this.totalHostExecutionDuration,
  });

  /// Duration in microseconds (convenience getter for backward compatibility).
  int get totalHostExecutionDurationMicros =>
      totalHostExecutionDuration.microseconds;

  static InitialSubscription _decode(BsatnDecoder decoder) {
    final databaseUpdate = DatabaseUpdate.readBsatn(decoder);
    final requestId = decoder.readU32();
    final totalHostExecutionDuration = TimeDuration.readBsatn(decoder);
    return InitialSubscription(
      databaseUpdate: databaseUpdate,
      requestId: requestId,
      totalHostExecutionDuration: totalHostExecutionDuration,
    );
  }

  @override
  String toString() =>
      'InitialSubscription(requestId: $requestId, '
      'duration: $totalHostExecutionDuration, '
      '$databaseUpdate)';
}

/// Server notification about a committed or failed transaction (tag 1).
///
/// Fields:
/// - status: UpdateStatus
/// - timestamp: Timestamp (i64 nanoseconds)
/// - caller_identity: Identity
/// - caller_connection_id: ConnectionId
/// - reducer_call: ReducerCallInfo
/// - energy_quanta_used: EnergyQuanta
/// - total_host_execution_duration: TimeDuration (i64 nanoseconds)
class TransactionUpdate extends ServerMessage {
  final UpdateStatus status;
  final Timestamp timestamp;
  final Identity callerIdentity;
  final ConnectionId callerConnectionId;
  final ReducerCallInfo reducerCall;
  final EnergyQuanta energyQuantaUsed;
  final TimeDuration totalHostExecutionDuration;

  const TransactionUpdate({
    required this.status,
    required this.timestamp,
    required this.callerIdentity,
    required this.callerConnectionId,
    required this.reducerCall,
    required this.energyQuantaUsed,
    required this.totalHostExecutionDuration,
  });

  /// Duration in microseconds (convenience getter for backward compatibility).
  int get totalHostExecutionDurationMicros =>
      totalHostExecutionDuration.microseconds;

  static TransactionUpdate _decode(BsatnDecoder decoder) {
    final status = UpdateStatus.readBsatn(decoder);
    final timestamp = Timestamp.readBsatn(decoder);
    final callerIdentity = Identity.readBsatn(decoder);
    final callerConnectionId = ConnectionId.readBsatn(decoder);
    final reducerCall = ReducerCallInfo.readBsatn(decoder);
    final energyQuantaUsed = EnergyQuanta.readBsatn(decoder);
    final totalHostExecutionDuration = TimeDuration.readBsatn(decoder);
    return TransactionUpdate(
      status: status,
      timestamp: timestamp,
      callerIdentity: callerIdentity,
      callerConnectionId: callerConnectionId,
      reducerCall: reducerCall,
      energyQuantaUsed: energyQuantaUsed,
      totalHostExecutionDuration: totalHostExecutionDuration,
    );
  }

  @override
  String toString() =>
      'TransactionUpdate(reducer: ${reducerCall.reducerName}, '
      'status: $status, '
      'duration: $totalHostExecutionDuration)';
}

/// Lightweight transaction update with only request ID and database update (tag 2).
///
/// Sent instead of [TransactionUpdate] when the caller used
/// [CallReducerFlags.noSuccessNotify] or similar optimizations.
///
/// Fields:
/// - request_id: u32
/// - update: DatabaseUpdate
class TransactionUpdateLight extends ServerMessage {
  final int requestId;
  final DatabaseUpdate update;

  const TransactionUpdateLight({
    required this.requestId,
    required this.update,
  });

  static TransactionUpdateLight _decode(BsatnDecoder decoder) {
    final requestId = decoder.readU32();
    final update = DatabaseUpdate.readBsatn(decoder);
    return TransactionUpdateLight(
      requestId: requestId,
      update: update,
    );
  }

  @override
  String toString() =>
      'TransactionUpdateLight(requestId: $requestId, $update)';
}

/// Server response containing the client's identity and auth token (tag 3).
class IdentityToken extends ServerMessage {
  final Identity identity;
  final String token;
  final ConnectionId connectionId;

  const IdentityToken({
    required this.identity,
    required this.token,
    required this.connectionId,
  });

  static IdentityToken _decode(BsatnDecoder decoder) {
    final identity = Identity.readBsatn(decoder);
    final token = decoder.readString();
    final connectionId = ConnectionId.readBsatn(decoder);
    return IdentityToken(
      identity: identity,
      token: token,
      connectionId: connectionId,
    );
  }

  @override
  String toString() =>
      'IdentityToken(identity: $identity, connectionId: $connectionId)';
}

/// Server response to a one-off query (tag 4).
///
/// Fields:
/// - `message_id`: `Box<[u8]>` (u32 length prefix + raw bytes)
/// - `error`: `Option<Box<str>>`
/// - `tables`: `Box<[OneOffTable]>`
/// - `total_host_execution_duration`: TimeDuration (i64 nanoseconds)
class OneOffQueryResponse extends ServerMessage {
  final Uint8List messageId;
  final String? error;
  final List<OneOffTable> tables;
  final TimeDuration totalHostExecutionDuration;

  const OneOffQueryResponse({
    required this.messageId,
    required this.error,
    required this.tables,
    required this.totalHostExecutionDuration,
  });

  /// Returns true if the query completed without errors.
  bool get isSuccess => error == null;

  /// Returns true if the query returned an error.
  bool get isError => error != null;

  static OneOffQueryResponse _decode(BsatnDecoder decoder) {
    final messageId = decoder.readBytes();

    // error: Option<Box<str>>
    final hasError = decoder.readOption();
    final error = hasError ? decoder.readString() : null;

    final tableCount = decoder.readArrayHeader();
    final tables = <OneOffTable>[];
    for (var i = 0; i < tableCount; i++) {
      tables.add(OneOffTable.readBsatn(decoder));
    }

    final totalHostExecutionDuration = TimeDuration.readBsatn(decoder);

    return OneOffQueryResponse(
      messageId: messageId,
      error: error,
      tables: tables,
      totalHostExecutionDuration: totalHostExecutionDuration,
    );
  }

  @override
  String toString() =>
      'OneOffQueryResponse(error: ${error ?? 'none'}, '
      '${tables.length} tables, '
      'duration: $totalHostExecutionDuration)';
}

/// Server confirmation that a single subscription query was applied (tag 5).
///
/// Fields:
/// - request_id: u32
/// - total_host_execution_duration_micros: u64 (plain microseconds)
/// - query_id: QueryId { id: u32 }
/// - rows: SubscribeRows
class SubscribeApplied extends ServerMessage {
  final int requestId;
  final int totalHostExecutionDurationMicros;
  final int queryId;
  final SubscribeRows rows;

  const SubscribeApplied({
    required this.requestId,
    required this.totalHostExecutionDurationMicros,
    required this.queryId,
    required this.rows,
  });

  static SubscribeApplied _decode(BsatnDecoder decoder) {
    final requestId = decoder.readU32();
    final totalHostExecutionDurationMicros = decoder.readU64();
    final queryId = decoder.readU32();
    final rows = SubscribeRows.readBsatn(decoder);
    return SubscribeApplied(
      requestId: requestId,
      totalHostExecutionDurationMicros: totalHostExecutionDurationMicros,
      queryId: queryId,
      rows: rows,
    );
  }

  @override
  String toString() =>
      'SubscribeApplied(requestId: $requestId, queryId: $queryId, '
      'duration: ${totalHostExecutionDurationMicros}us)';
}

/// Server confirmation that a subscription was removed (tag 6).
///
/// Fields:
/// - request_id: u32
/// - total_host_execution_duration_micros: u64 (plain microseconds)
/// - query_id: QueryId { id: u32 }
/// - rows: SubscribeRows
class UnsubscribeApplied extends ServerMessage {
  final int requestId;
  final int totalHostExecutionDurationMicros;
  final int queryId;
  final SubscribeRows rows;

  const UnsubscribeApplied({
    required this.requestId,
    required this.totalHostExecutionDurationMicros,
    required this.queryId,
    required this.rows,
  });

  static UnsubscribeApplied _decode(BsatnDecoder decoder) {
    final requestId = decoder.readU32();
    final totalHostExecutionDurationMicros = decoder.readU64();
    final queryId = decoder.readU32();
    final rows = SubscribeRows.readBsatn(decoder);
    return UnsubscribeApplied(
      requestId: requestId,
      totalHostExecutionDurationMicros: totalHostExecutionDurationMicros,
      queryId: queryId,
      rows: rows,
    );
  }

  @override
  String toString() =>
      'UnsubscribeApplied(requestId: $requestId, queryId: $queryId, '
      'duration: ${totalHostExecutionDurationMicros}us)';
}

/// Server notification of a subscription error (tag 7).
///
/// Fields:
/// - `total_host_execution_duration_micros`: u64 (plain microseconds)
/// - `request_id`: `Option<u32>`
/// - `query_id`: `Option<u32>`
/// - `table_id`: `Option<u32>`
/// - `error`: `Box<str>`
class SubscriptionError extends ServerMessage {
  final int totalHostExecutionDurationMicros;
  final int? requestId;
  final int? queryId;
  final int? tableId;
  final String error;

  const SubscriptionError({
    required this.totalHostExecutionDurationMicros,
    required this.requestId,
    required this.queryId,
    required this.tableId,
    required this.error,
  });

  static SubscriptionError _decode(BsatnDecoder decoder) {
    final totalHostExecutionDurationMicros = decoder.readU64();

    // request_id: Option<u32>
    final hasRequestId = decoder.readOption();
    final requestId = hasRequestId ? decoder.readU32() : null;

    // query_id: Option<u32>
    final hasQueryId = decoder.readOption();
    final queryId = hasQueryId ? decoder.readU32() : null;

    // table_id: Option<u32>
    final hasTableId = decoder.readOption();
    final tableId = hasTableId ? decoder.readU32() : null;

    final error = decoder.readString();

    return SubscriptionError(
      totalHostExecutionDurationMicros: totalHostExecutionDurationMicros,
      requestId: requestId,
      queryId: queryId,
      tableId: tableId,
      error: error,
    );
  }

  @override
  String toString() =>
      'SubscriptionError(error: $error, requestId: $requestId, '
      'queryId: $queryId, tableId: $tableId, '
      'duration: ${totalHostExecutionDurationMicros}us)';
}

/// Server confirmation that a multi-query subscription was applied (tag 8).
///
/// Fields:
/// - request_id: u32
/// - total_host_execution_duration_micros: u64 (plain microseconds)
/// - query_id: QueryId { id: u32 }
/// - update: DatabaseUpdate
class SubscribeMultiApplied extends ServerMessage {
  final int requestId;
  final int totalHostExecutionDurationMicros;
  final int queryId;
  final DatabaseUpdate update;

  const SubscribeMultiApplied({
    required this.requestId,
    required this.totalHostExecutionDurationMicros,
    required this.queryId,
    required this.update,
  });

  static SubscribeMultiApplied _decode(BsatnDecoder decoder) {
    final requestId = decoder.readU32();
    final totalHostExecutionDurationMicros = decoder.readU64();
    final queryId = decoder.readU32();
    final update = DatabaseUpdate.readBsatn(decoder);
    return SubscribeMultiApplied(
      requestId: requestId,
      totalHostExecutionDurationMicros: totalHostExecutionDurationMicros,
      queryId: queryId,
      update: update,
    );
  }

  @override
  String toString() =>
      'SubscribeMultiApplied(requestId: $requestId, queryId: $queryId, '
      'duration: ${totalHostExecutionDurationMicros}us)';
}

/// Server confirmation that a multi-query subscription was removed (tag 9).
///
/// Fields:
/// - request_id: u32
/// - total_host_execution_duration_micros: u64 (plain microseconds)
/// - query_id: QueryId { id: u32 }
/// - update: DatabaseUpdate
class UnsubscribeMultiApplied extends ServerMessage {
  final int requestId;
  final int totalHostExecutionDurationMicros;
  final int queryId;
  final DatabaseUpdate update;

  const UnsubscribeMultiApplied({
    required this.requestId,
    required this.totalHostExecutionDurationMicros,
    required this.queryId,
    required this.update,
  });

  static UnsubscribeMultiApplied _decode(BsatnDecoder decoder) {
    final requestId = decoder.readU32();
    final totalHostExecutionDurationMicros = decoder.readU64();
    final queryId = decoder.readU32();
    final update = DatabaseUpdate.readBsatn(decoder);
    return UnsubscribeMultiApplied(
      requestId: requestId,
      totalHostExecutionDurationMicros: totalHostExecutionDurationMicros,
      queryId: queryId,
      update: update,
    );
  }

  @override
  String toString() =>
      'UnsubscribeMultiApplied(requestId: $requestId, queryId: $queryId, '
      'duration: ${totalHostExecutionDurationMicros}us)';
}

/// Server result of a procedure call (tag 10).
///
/// Fields:
/// - status: ProcedureStatus
/// - timestamp: Timestamp (i64 nanoseconds)
/// - total_host_execution_duration: TimeDuration (i64 nanoseconds)
/// - request_id: u32
class ProcedureResult extends ServerMessage {
  final ProcedureStatus status;
  final Timestamp timestamp;
  final TimeDuration totalHostExecutionDuration;
  final int requestId;

  const ProcedureResult({
    required this.status,
    required this.timestamp,
    required this.totalHostExecutionDuration,
    required this.requestId,
  });

  static ProcedureResult _decode(BsatnDecoder decoder) {
    final status = ProcedureStatus.readBsatn(decoder);
    final timestamp = Timestamp.readBsatn(decoder);
    final totalHostExecutionDuration = TimeDuration.readBsatn(decoder);
    final requestId = decoder.readU32();
    return ProcedureResult(
      status: status,
      timestamp: timestamp,
      totalHostExecutionDuration: totalHostExecutionDuration,
      requestId: requestId,
    );
  }

  @override
  String toString() =>
      'ProcedureResult(requestId: $requestId, status: $status, '
      'duration: $totalHostExecutionDuration)';
}

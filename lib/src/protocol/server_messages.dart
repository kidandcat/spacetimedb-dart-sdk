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
      default:
        throw BsatnDecodeException('Unknown server message tag: $tag');
    }
  }
}

/// Server response to the initial subscription, containing the current
/// state of all subscribed tables (tag 0).
class InitialSubscription extends ServerMessage {
  final DatabaseUpdate databaseUpdate;
  final int requestId;
  final int totalHostExecutionDurationMicros;

  const InitialSubscription({
    required this.databaseUpdate,
    required this.requestId,
    required this.totalHostExecutionDurationMicros,
  });

  static InitialSubscription _decode(BsatnDecoder decoder) {
    final databaseUpdate = DatabaseUpdate.readBsatn(decoder);
    final requestId = decoder.readU32();
    final totalHostExecutionDurationMicros = decoder.readI64();
    return InitialSubscription(
      databaseUpdate: databaseUpdate,
      requestId: requestId,
      totalHostExecutionDurationMicros: totalHostExecutionDurationMicros,
    );
  }

  @override
  String toString() =>
      'InitialSubscription(requestId: $requestId, '
      'duration: ${totalHostExecutionDurationMicros}us, '
      '$databaseUpdate)';
}

/// Server notification about a committed or failed transaction (tag 1).
class TransactionUpdate extends ServerMessage {
  final UpdateStatus status;
  final Timestamp timestamp;
  final Identity callerIdentity;
  final ConnectionId callerConnectionId;
  final ReducerCallInfo reducerCall;
  final EnergyQuanta energyQuantaUsed;
  final int totalHostExecutionDurationMicros;

  const TransactionUpdate({
    required this.status,
    required this.timestamp,
    required this.callerIdentity,
    required this.callerConnectionId,
    required this.reducerCall,
    required this.energyQuantaUsed,
    required this.totalHostExecutionDurationMicros,
  });

  static TransactionUpdate _decode(BsatnDecoder decoder) {
    final status = UpdateStatus.readBsatn(decoder);
    final timestamp = Timestamp.readBsatn(decoder);
    final callerIdentity = Identity.readBsatn(decoder);
    final callerConnectionId = ConnectionId.readBsatn(decoder);
    final reducerCall = ReducerCallInfo.readBsatn(decoder);
    final energyQuantaUsed = EnergyQuanta.readBsatn(decoder);
    final totalHostExecutionDurationMicros = decoder.readI64();
    return TransactionUpdate(
      status: status,
      timestamp: timestamp,
      callerIdentity: callerIdentity,
      callerConnectionId: callerConnectionId,
      reducerCall: reducerCall,
      energyQuantaUsed: energyQuantaUsed,
      totalHostExecutionDurationMicros: totalHostExecutionDurationMicros,
    );
  }

  @override
  String toString() =>
      'TransactionUpdate(reducer: ${reducerCall.reducerName}, '
      'status: $status, '
      'duration: ${totalHostExecutionDurationMicros}us)';
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
class OneOffQueryResponse extends ServerMessage {
  final Uint8List messageId;
  final String error;
  final List<OneOffTable> tables;

  const OneOffQueryResponse({
    required this.messageId,
    required this.error,
    required this.tables,
  });

  /// Returns true if the query completed without errors.
  bool get isSuccess => error.isEmpty;

  /// Returns true if the query returned an error.
  bool get isError => error.isNotEmpty;

  static OneOffQueryResponse _decode(BsatnDecoder decoder) {
    final messageId = decoder.readBytes();
    final error = decoder.readString();
    final tableCount = decoder.readArrayHeader();
    final tables = <OneOffTable>[];
    for (var i = 0; i < tableCount; i++) {
      tables.add(OneOffTable.readBsatn(decoder));
    }
    return OneOffQueryResponse(
      messageId: messageId,
      error: error,
      tables: tables,
    );
  }

  @override
  String toString() =>
      'OneOffQueryResponse(error: ${error.isEmpty ? 'none' : error}, '
      '${tables.length} tables)';
}

/// Server confirmation that a single subscription query was applied (tag 5).
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

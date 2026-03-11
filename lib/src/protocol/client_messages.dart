import 'dart:typed_data';

import '../bsatn/bsatn.dart';

/// Flags controlling the server's response behavior for reducer calls.
enum CallReducerFlags {
  /// The server sends a full TransactionUpdate on success.
  fullUpdate(0),

  /// The server skips the success notification (only notifies on failure).
  noSuccessNotify(1);

  final int value;
  const CallReducerFlags(this.value);
}

/// Base class for all client-to-server messages (v1 protocol).
///
/// Client messages are BSATN-encoded sum types with a u8 tag. There is no
/// compression prefix on client messages (unlike server messages).
///
/// Subprotocol: `v1.bsatn.spacetimedb`
sealed class ClientMessage {
  const ClientMessage();

  /// Serializes this message to BSATN bytes.
  void writeBsatn(BsatnEncoder encoder);

  /// Convenience method to encode this message to a byte array.
  Uint8List toBytes() {
    final encoder = BsatnEncoder();
    writeBsatn(encoder);
    return encoder.toBytes();
  }
}

/// Calls a reducer on the server (tag 0).
///
/// BSATN layout:
/// ```
/// tag(0) | reducer: String | args: Bytes | request_id: u32 | flags: u8
/// ```
class CallReducer extends ClientMessage {
  /// The name of the reducer to call.
  final String reducer;

  /// BSATN-encoded reducer arguments.
  final Uint8List args;

  /// Client-assigned request ID for correlating responses.
  final int requestId;

  /// Flags controlling the server's response behavior.
  final CallReducerFlags flags;

  const CallReducer({
    required this.reducer,
    required this.args,
    required this.requestId,
    this.flags = CallReducerFlags.fullUpdate,
  });

  @override
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeSumTag(0);
    encoder.writeString(reducer);
    encoder.writeBytes(args);
    encoder.writeU32(requestId);
    encoder.writeU8(flags.value);
  }

  @override
  String toString() =>
      'CallReducer(reducer: $reducer, requestId: $requestId, '
      'flags: $flags, ${args.length} arg bytes)';
}

/// Executes a one-off SQL query (tag 2).
///
/// BSATN layout:
/// ```
/// tag(2) | message_id: Bytes (u32 length + 16 random bytes) | query_string: String
/// ```
class OneOffQuery extends ClientMessage {
  /// A 16-byte random identifier for correlating the response.
  final Uint8List messageId;

  /// The SQL query string to execute.
  final String queryString;

  OneOffQuery({required this.messageId, required this.queryString}) {
    if (messageId.length != 16) {
      throw ArgumentError(
        'OneOffQuery messageId must be 16 bytes, got ${messageId.length}',
      );
    }
  }

  @override
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeSumTag(2);
    encoder.writeBytes(messageId);
    encoder.writeString(queryString);
  }

  @override
  String toString() => 'OneOffQuery(queryString: $queryString)';
}

/// Subscribes to a single query (tag 3).
///
/// BSATN layout:
/// ```
/// tag(3) | query: String | request_id: u32 | query_id: QueryId { id: u32 }
/// ```
class SubscribeSingle extends ClientMessage {
  /// The SQL subscription query.
  final String query;

  /// Client-assigned request ID for correlating responses.
  final int requestId;

  /// Client-assigned query ID for identifying this subscription.
  final int queryId;

  const SubscribeSingle({
    required this.query,
    required this.requestId,
    required this.queryId,
  });

  @override
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeSumTag(3);
    encoder.writeString(query);
    encoder.writeU32(requestId);
    encoder.writeU32(queryId);
  }

  @override
  String toString() =>
      'SubscribeSingle(query: $query, requestId: $requestId, '
      'queryId: $queryId)';
}

/// Unsubscribes from a query (tag 5).
///
/// BSATN layout:
/// ```
/// tag(5) | request_id: u32 | query_id: QueryId { id: u32 }
/// ```
class UnsubscribeMsg extends ClientMessage {
  /// Client-assigned request ID for correlating responses.
  final int requestId;

  /// The query ID of the subscription to cancel.
  final int queryId;

  const UnsubscribeMsg({required this.requestId, required this.queryId});

  @override
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeSumTag(5);
    encoder.writeU32(requestId);
    encoder.writeU32(queryId);
  }

  @override
  String toString() =>
      'UnsubscribeMsg(requestId: $requestId, queryId: $queryId)';
}

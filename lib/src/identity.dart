import 'dart:typed_data';

import 'bsatn/bsatn.dart';

/// A SpacetimeDB identity (32 bytes / U256).
///
/// Each user in SpacetimeDB is identified by a unique 256-bit identity.
/// Identities are serialized as 32 raw bytes in BSATN (a product type
/// wrapping a single U256 field).
class Identity {
  /// The raw 32-byte identity data.
  final Uint8List data;

  /// Creates an [Identity] from exactly 32 bytes.
  ///
  /// Throws [ArgumentError] if [data] is not exactly 32 bytes long.
  Identity(this.data) {
    if (data.length != 32) {
      throw ArgumentError('Identity must be 32 bytes, got ${data.length}');
    }
  }

  /// Creates a zero identity (32 zero bytes).
  factory Identity.zero() => Identity(Uint8List(32));

  /// Creates an [Identity] from a 64-character hexadecimal string.
  ///
  /// Throws [ArgumentError] if [hex] is not exactly 64 characters.
  /// Throws [FormatException] if [hex] contains non-hex characters.
  factory Identity.fromHex(String hex) {
    if (hex.length != 64) {
      throw ArgumentError('Identity hex must be 64 chars, got ${hex.length}');
    }
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return Identity(bytes);
  }

  /// Returns the identity as a 64-character lowercase hex string.
  String toHex() {
    final sb = StringBuffer();
    for (final b in data) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Returns true if this is the zero identity.
  bool get isZero => data.every((b) => b == 0);

  /// Writes this identity to a BSATN encoder as 32 raw bytes.
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeRawBytes(data);
  }

  /// Reads an identity from a BSATN decoder (32 raw bytes).
  static Identity readBsatn(BsatnDecoder decoder) {
    return Identity(decoder.readRawBytes(32));
  }

  @override
  bool operator ==(Object other) =>
      other is Identity && _bytesEqual(data, other.data);

  @override
  int get hashCode => Object.hashAll(data);

  @override
  String toString() => 'Identity(${toHex()})';
}

/// A SpacetimeDB connection ID (16 bytes / U128).
///
/// Each active WebSocket connection is assigned a unique 128-bit connection ID.
/// Connection IDs are serialized as 16 raw bytes in BSATN.
class ConnectionId {
  /// The raw 16-byte connection ID data.
  final Uint8List data;

  /// Creates a [ConnectionId] from exactly 16 bytes.
  ///
  /// Throws [ArgumentError] if [data] is not exactly 16 bytes long.
  ConnectionId(this.data) {
    if (data.length != 16) {
      throw ArgumentError('ConnectionId must be 16 bytes, got ${data.length}');
    }
  }

  /// Creates a zero connection ID (16 zero bytes).
  factory ConnectionId.zero() => ConnectionId(Uint8List(16));

  /// Creates a [ConnectionId] from a 32-character hexadecimal string.
  ///
  /// Throws [ArgumentError] if [hex] is not exactly 32 characters.
  /// Throws [FormatException] if [hex] contains non-hex characters.
  factory ConnectionId.fromHex(String hex) {
    if (hex.length != 32) {
      throw ArgumentError(
        'ConnectionId hex must be 32 chars, got ${hex.length}',
      );
    }
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return ConnectionId(bytes);
  }

  /// Returns the connection ID as a 32-character lowercase hex string.
  String toHex() {
    final sb = StringBuffer();
    for (final b in data) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Returns true if this is the zero connection ID.
  bool get isZero => data.every((b) => b == 0);

  /// Writes this connection ID to a BSATN encoder as 16 raw bytes.
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeRawBytes(data);
  }

  /// Reads a connection ID from a BSATN decoder (16 raw bytes).
  static ConnectionId readBsatn(BsatnDecoder decoder) {
    return ConnectionId(decoder.readRawBytes(16));
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionId && _bytesEqual(data, other.data);

  @override
  int get hashCode => Object.hashAll(data);

  @override
  String toString() => 'ConnectionId(${toHex()})';
}

/// Authentication token (JWT string wrapper).
///
/// Wraps the JWT token string received from the SpacetimeDB server during
/// the identity/token handshake.
class Token {
  /// The raw JWT token string.
  final String value;

  Token(this.value);

  /// Returns true if the token string is empty.
  bool get isEmpty => value.isEmpty;

  @override
  bool operator ==(Object other) => other is Token && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Token(${value.length > 10 ? '${value.substring(0, 10)}...' : value})';
}

/// SpacetimeDB timestamp (nanoseconds since Unix epoch).
///
/// Timestamps are serialized as a signed 64-bit integer (i64) in BSATN,
/// representing nanoseconds since the Unix epoch.
class Timestamp {
  /// Nanoseconds since Unix epoch (can be negative for dates before 1970).
  final int nanosecondsSinceEpoch;

  Timestamp(this.nanosecondsSinceEpoch);

  /// Creates a [Timestamp] representing the current time.
  factory Timestamp.now() =>
      Timestamp(DateTime.now().microsecondsSinceEpoch * 1000);

  /// Creates a [Timestamp] from a [DateTime].
  factory Timestamp.fromDateTime(DateTime dt) =>
      Timestamp(dt.microsecondsSinceEpoch * 1000);

  /// Converts this timestamp to a [DateTime].
  ///
  /// Note: Dart's DateTime only has microsecond precision, so the sub-microsecond
  /// portion of the nanosecond timestamp is truncated.
  DateTime toDateTime() =>
      DateTime.fromMicrosecondsSinceEpoch(nanosecondsSinceEpoch ~/ 1000);

  /// Returns the timestamp as microseconds since epoch (lossy conversion).
  int get microsecondsSinceEpoch => nanosecondsSinceEpoch ~/ 1000;

  /// Writes this timestamp to a BSATN encoder as an i64 (nanoseconds).
  void writeBsatn(BsatnEncoder encoder) =>
      encoder.writeI64(nanosecondsSinceEpoch);

  /// Reads a timestamp from a BSATN decoder (i64 nanoseconds).
  static Timestamp readBsatn(BsatnDecoder decoder) =>
      Timestamp(decoder.readI64());

  @override
  bool operator ==(Object other) =>
      other is Timestamp &&
      nanosecondsSinceEpoch == other.nanosecondsSinceEpoch;

  @override
  int get hashCode => nanosecondsSinceEpoch.hashCode;

  @override
  String toString() => 'Timestamp($nanosecondsSinceEpoch ns)';
}

/// Compares two byte arrays for element-wise equality.
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

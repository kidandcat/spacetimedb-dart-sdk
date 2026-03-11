import 'dart:convert';
import 'dart:typed_data';

import 'types.dart';

/// Encodes values into the BSATN binary format.
///
/// BSATN (Binary SpacetimeDB Algebraic Type Notation) is SpacetimeDB's
/// wire format. All multi-byte integers are encoded as little-endian.
///
/// Usage:
/// ```dart
/// final encoder = BsatnEncoder();
/// encoder.writeU32(42);
/// encoder.writeString('hello');
/// final bytes = encoder.toBytes();
/// ```
class BsatnEncoder {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// Writes a boolean value as a single byte (0 = false, 1 = true).
  void writeBool(bool v) => _builder.addByte(v ? 1 : 0);

  /// Writes an unsigned 8-bit integer.
  void writeU8(int v) => _builder.addByte(v & 0xFF);

  /// Writes a signed 8-bit integer.
  void writeI8(int v) => _builder.addByte(v & 0xFF);

  /// Writes an unsigned 16-bit integer in little-endian byte order.
  void writeU16(int v) {
    final bd = ByteData(2);
    bd.setUint16(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes a signed 16-bit integer in little-endian byte order.
  void writeI16(int v) {
    final bd = ByteData(2);
    bd.setInt16(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes an unsigned 32-bit integer in little-endian byte order.
  void writeU32(int v) {
    final bd = ByteData(4);
    bd.setUint32(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes a signed 32-bit integer in little-endian byte order.
  void writeI32(int v) {
    final bd = ByteData(4);
    bd.setInt32(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes an unsigned 64-bit integer in little-endian byte order.
  ///
  /// On native Dart, [int] is a 64-bit signed integer. Values larger than
  /// 2^63 - 1 cannot be represented and should use [BigInt] directly.
  void writeU64(int v) {
    final bd = ByteData(8);
    bd.setUint64(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes a signed 64-bit integer in little-endian byte order.
  void writeI64(int v) {
    final bd = ByteData(8);
    bd.setInt64(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes a [U128] as 16 little-endian bytes.
  void writeU128(U128 v) => _builder.add(v.toLeBytes());

  /// Writes an [I128] as 16 little-endian bytes in two's complement.
  void writeI128(I128 v) => _builder.add(v.toLeBytes());

  /// Writes a [U256] as 32 little-endian bytes.
  void writeU256(U256 v) => _builder.add(v.toLeBytes());

  /// Writes an [I256] as 32 little-endian bytes in two's complement.
  void writeI256(I256 v) => _builder.add(v.toLeBytes());

  /// Writes a 32-bit IEEE 754 floating-point value in little-endian byte order.
  void writeF32(double v) {
    final bd = ByteData(4);
    bd.setFloat32(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes a 64-bit IEEE 754 floating-point value in little-endian byte order.
  void writeF64(double v) {
    final bd = ByteData(8);
    bd.setFloat64(0, v, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Writes a UTF-8 string, prefixed by its byte length as a U32.
  void writeString(String s) {
    final bytes = utf8.encode(s);
    writeU32(bytes.length);
    _builder.add(bytes);
  }

  /// Writes a byte array, prefixed by its length as a U32.
  void writeBytes(Uint8List bytes) {
    writeU32(bytes.length);
    _builder.add(bytes);
  }

  /// Writes raw bytes without any length prefix.
  void writeRawBytes(Uint8List bytes) {
    _builder.add(bytes);
  }

  /// Writes the length header for an array (encoded as U32).
  void writeArrayHeader(int length) => writeU32(length);

  /// Writes a sum-type discriminant tag (encoded as U8).
  void writeSumTag(int tag) => writeU8(tag);

  /// Writes an Option::None tag (tag = 1 in BSATN).
  void writeOptionNone() => writeSumTag(1);

  /// Writes an Option::Some tag (tag = 0 in BSATN).
  ///
  /// The caller must write the contained value immediately after this call.
  void writeOptionSome() => writeSumTag(0);

  /// Returns the accumulated bytes as a [Uint8List].
  ///
  /// After calling this, the encoder should not be reused.
  Uint8List toBytes() => _builder.toBytes();

  /// Returns the number of bytes written so far.
  int get length => _builder.length;
}

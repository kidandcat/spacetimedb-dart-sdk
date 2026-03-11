import 'dart:convert';
import 'dart:typed_data';

import 'types.dart';

/// Exception thrown when BSATN decoding fails.
class BsatnDecodeException implements Exception {
  final String message;
  BsatnDecodeException(this.message);

  @override
  String toString() => 'BsatnDecodeException: $message';
}

/// Decodes values from the BSATN binary format.
///
/// BSATN (Binary SpacetimeDB Algebraic Type Notation) is SpacetimeDB's
/// wire format. All multi-byte integers are decoded as little-endian.
///
/// Usage:
/// ```dart
/// final decoder = BsatnDecoder(bytes);
/// final value = decoder.readU32();
/// final name = decoder.readString();
/// ```
class BsatnDecoder {
  final Uint8List _data;
  int _offset = 0;

  BsatnDecoder(this._data);

  /// Returns the current read offset.
  int get offset => _offset;

  /// Returns the total number of bytes in the buffer.
  int get length => _data.length;

  /// Returns the number of bytes remaining to be read.
  int get remaining => _data.length - _offset;

  /// Returns true if there are no more bytes to read.
  bool get isEmpty => _offset >= _data.length;

  void _checkAvailable(int count) {
    if (_offset + count > _data.length) {
      throw BsatnDecodeException(
        'Buffer underflow: need $count bytes at offset $_offset, '
        'but only ${_data.length - _offset} bytes remain',
      );
    }
  }

  /// Reads a boolean value from a single byte (0 = false, 1 = true).
  bool readBool() {
    _checkAvailable(1);
    final v = _data[_offset++];
    if (v > 1) {
      throw BsatnDecodeException('Invalid bool value: $v');
    }
    return v == 1;
  }

  /// Reads an unsigned 8-bit integer.
  int readU8() {
    _checkAvailable(1);
    return _data[_offset++];
  }

  /// Reads a signed 8-bit integer.
  int readI8() {
    _checkAvailable(1);
    final v = _data[_offset++];
    return v >= 128 ? v - 256 : v;
  }

  /// Reads an unsigned 16-bit integer in little-endian byte order.
  int readU16() {
    _checkAvailable(2);
    final bd = ByteData.sublistView(_data, _offset, _offset + 2);
    _offset += 2;
    return bd.getUint16(0, Endian.little);
  }

  /// Reads a signed 16-bit integer in little-endian byte order.
  int readI16() {
    _checkAvailable(2);
    final bd = ByteData.sublistView(_data, _offset, _offset + 2);
    _offset += 2;
    return bd.getInt16(0, Endian.little);
  }

  /// Reads an unsigned 32-bit integer in little-endian byte order.
  int readU32() {
    _checkAvailable(4);
    final bd = ByteData.sublistView(_data, _offset, _offset + 4);
    _offset += 4;
    return bd.getUint32(0, Endian.little);
  }

  /// Reads a signed 32-bit integer in little-endian byte order.
  int readI32() {
    _checkAvailable(4);
    final bd = ByteData.sublistView(_data, _offset, _offset + 4);
    _offset += 4;
    return bd.getInt32(0, Endian.little);
  }

  /// Reads an unsigned 64-bit integer in little-endian byte order.
  int readU64() {
    _checkAvailable(8);
    final bd = ByteData.sublistView(_data, _offset, _offset + 8);
    _offset += 8;
    return bd.getUint64(0, Endian.little);
  }

  /// Reads a signed 64-bit integer in little-endian byte order.
  int readI64() {
    _checkAvailable(8);
    final bd = ByteData.sublistView(_data, _offset, _offset + 8);
    _offset += 8;
    return bd.getInt64(0, Endian.little);
  }

  /// Reads a [U128] from 16 little-endian bytes.
  U128 readU128() {
    _checkAvailable(16);
    final bytes = Uint8List.sublistView(_data, _offset, _offset + 16);
    _offset += 16;
    return U128.fromLeBytes(bytes);
  }

  /// Reads an [I128] from 16 little-endian bytes in two's complement.
  I128 readI128() {
    _checkAvailable(16);
    final bytes = Uint8List.sublistView(_data, _offset, _offset + 16);
    _offset += 16;
    return I128.fromLeBytes(bytes);
  }

  /// Reads a [U256] from 32 little-endian bytes.
  U256 readU256() {
    _checkAvailable(32);
    final bytes = Uint8List.sublistView(_data, _offset, _offset + 32);
    _offset += 32;
    return U256.fromLeBytes(bytes);
  }

  /// Reads an [I256] from 32 little-endian bytes in two's complement.
  I256 readI256() {
    _checkAvailable(32);
    final bytes = Uint8List.sublistView(_data, _offset, _offset + 32);
    _offset += 32;
    return I256.fromLeBytes(bytes);
  }

  /// Reads a 32-bit IEEE 754 floating-point value in little-endian byte order.
  double readF32() {
    _checkAvailable(4);
    final bd = ByteData.sublistView(_data, _offset, _offset + 4);
    _offset += 4;
    return bd.getFloat32(0, Endian.little);
  }

  /// Reads a 64-bit IEEE 754 floating-point value in little-endian byte order.
  double readF64() {
    _checkAvailable(8);
    final bd = ByteData.sublistView(_data, _offset, _offset + 8);
    _offset += 8;
    return bd.getFloat64(0, Endian.little);
  }

  /// Reads a UTF-8 string prefixed by its byte length as a U32.
  String readString() {
    final length = readU32();
    _checkAvailable(length);
    final bytes = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return utf8.decode(bytes);
  }

  /// Reads a byte array prefixed by its length as a U32.
  Uint8List readBytes() {
    final length = readU32();
    _checkAvailable(length);
    final bytes = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(bytes);
  }

  /// Reads exactly [count] raw bytes without any length prefix.
  Uint8List readRawBytes(int count) {
    _checkAvailable(count);
    final bytes = Uint8List.sublistView(_data, _offset, _offset + count);
    _offset += count;
    return Uint8List.fromList(bytes);
  }

  /// Reads an array length header (U32) and returns the element count.
  int readArrayHeader() => readU32();

  /// Reads a sum-type discriminant tag (U8).
  int readSumTag() => readU8();

  /// Reads an Option tag and returns true if Some (tag 0), false if None (tag 1).
  ///
  /// If the return value is true, the caller must read the contained value
  /// immediately after.
  bool readOption() {
    final tag = readSumTag();
    if (tag == 0) return true; // Some
    if (tag == 1) return false; // None
    throw BsatnDecodeException('Invalid option tag: $tag (expected 0 or 1)');
  }
}

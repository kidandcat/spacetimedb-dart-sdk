import 'dart:typed_data';

/// The maximum value boundary for a 128-bit unsigned integer (2^128).
final _maxU128 = BigInt.one << 128;

/// The maximum value boundary for a 256-bit unsigned integer (2^256).
final _maxU256 = BigInt.one << 256;

/// The minimum value for a 128-bit signed integer (-2^127).
final _minI128 = -(BigInt.one << 127);

/// The maximum value for a 128-bit signed integer (2^127 - 1).
final _maxI128 = (BigInt.one << 127) - BigInt.one;

/// The minimum value for a 256-bit signed integer (-2^255).
final _minI256 = -(BigInt.one << 255);

/// The maximum value for a 256-bit signed integer (2^255 - 1).
final _maxI256 = (BigInt.one << 255) - BigInt.one;

/// Reads [byteCount] little-endian bytes into a [BigInt].
///
/// bytes[0] is the least significant byte.
BigInt _bigIntFromLeBytes(Uint8List bytes, int byteCount) {
  var result = BigInt.zero;
  for (var i = byteCount - 1; i >= 0; i--) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

/// Writes a non-negative [BigInt] as [byteCount] little-endian bytes.
Uint8List _bigIntToLeBytes(BigInt value, int byteCount) {
  final bytes = Uint8List(byteCount);
  var v = value;
  for (var i = 0; i < byteCount; i++) {
    bytes[i] = (v & BigInt.from(0xFF)).toInt();
    v >>= 8;
  }
  return bytes;
}

/// 128-bit unsigned integer, stored as 16 little-endian bytes.
///
/// Valid range: 0 to 2^128 - 1.
///
/// This type wraps a [BigInt] and provides conversions to/from little-endian
/// byte representations for BSATN serialization.
class U128 implements Comparable<U128> {
  /// The underlying [BigInt] value. Always in the range [0, 2^128).
  final BigInt value;

  /// Creates a [U128] from a [BigInt].
  ///
  /// Throws [ArgumentError] if [value] is negative or >= 2^128.
  U128(this.value) {
    if (value < BigInt.zero || value >= _maxU128) {
      throw ArgumentError('U128 out of range: $value');
    }
  }

  /// Creates a [U128] with value zero.
  factory U128.zero() => U128(BigInt.zero);

  /// Creates a [U128] from a Dart [int].
  ///
  /// Throws [ArgumentError] if [v] is negative.
  factory U128.fromInt(int v) => U128(BigInt.from(v));

  /// Decodes a [U128] from exactly 16 little-endian bytes.
  ///
  /// Throws [ArgumentError] if [bytes] does not have length 16.
  factory U128.fromLeBytes(Uint8List bytes) {
    if (bytes.length != 16) {
      throw ArgumentError('U128.fromLeBytes requires exactly 16 bytes, got ${bytes.length}');
    }
    return U128(_bigIntFromLeBytes(bytes, 16));
  }

  /// Encodes this value as 16 little-endian bytes.
  Uint8List toLeBytes() => _bigIntToLeBytes(value, 16);

  @override
  bool operator ==(Object other) => other is U128 && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '0x${value.toRadixString(16).padLeft(32, '0')}';

  @override
  int compareTo(U128 other) => value.compareTo(other.value);
}

/// 128-bit signed integer, stored as 16 little-endian bytes using two's
/// complement representation.
///
/// Valid range: -2^127 to 2^127 - 1.
class I128 implements Comparable<I128> {
  /// The underlying [BigInt] value. Always in the range [-2^127, 2^127).
  final BigInt value;

  /// Creates an [I128] from a [BigInt].
  ///
  /// Throws [ArgumentError] if [value] is outside the valid range.
  I128(this.value) {
    if (value < _minI128 || value > _maxI128) {
      throw ArgumentError('I128 out of range: $value');
    }
  }

  /// Creates an [I128] with value zero.
  factory I128.zero() => I128(BigInt.zero);

  /// Creates an [I128] from a Dart [int].
  factory I128.fromInt(int v) => I128(BigInt.from(v));

  /// Decodes an [I128] from exactly 16 little-endian bytes in two's
  /// complement representation.
  ///
  /// Throws [ArgumentError] if [bytes] does not have length 16.
  factory I128.fromLeBytes(Uint8List bytes) {
    if (bytes.length != 16) {
      throw ArgumentError('I128.fromLeBytes requires exactly 16 bytes, got ${bytes.length}');
    }
    var unsigned = _bigIntFromLeBytes(bytes, 16);
    // Convert from two's complement: if the high bit is set, subtract 2^128.
    if (unsigned >= (BigInt.one << 127)) {
      unsigned -= _maxU128;
    }
    return I128(unsigned);
  }

  /// Encodes this value as 16 little-endian bytes using two's complement.
  Uint8List toLeBytes() {
    // For negative values, add 2^128 to get the unsigned two's complement
    // representation.
    final unsigned = value < BigInt.zero ? value + _maxU128 : value;
    return _bigIntToLeBytes(unsigned, 16);
  }

  @override
  bool operator ==(Object other) => other is I128 && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();

  @override
  int compareTo(I128 other) => value.compareTo(other.value);
}

/// 256-bit unsigned integer, stored as 32 little-endian bytes.
///
/// Valid range: 0 to 2^256 - 1.
class U256 implements Comparable<U256> {
  /// The underlying [BigInt] value. Always in the range [0, 2^256).
  final BigInt value;

  /// Creates a [U256] from a [BigInt].
  ///
  /// Throws [ArgumentError] if [value] is negative or >= 2^256.
  U256(this.value) {
    if (value < BigInt.zero || value >= _maxU256) {
      throw ArgumentError('U256 out of range: $value');
    }
  }

  /// Creates a [U256] with value zero.
  factory U256.zero() => U256(BigInt.zero);

  /// Creates a [U256] from a Dart [int].
  ///
  /// Throws [ArgumentError] if [v] is negative.
  factory U256.fromInt(int v) => U256(BigInt.from(v));

  /// Decodes a [U256] from exactly 32 little-endian bytes.
  ///
  /// Throws [ArgumentError] if [bytes] does not have length 32.
  factory U256.fromLeBytes(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('U256.fromLeBytes requires exactly 32 bytes, got ${bytes.length}');
    }
    return U256(_bigIntFromLeBytes(bytes, 32));
  }

  /// Encodes this value as 32 little-endian bytes.
  Uint8List toLeBytes() => _bigIntToLeBytes(value, 32);

  @override
  bool operator ==(Object other) => other is U256 && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '0x${value.toRadixString(16).padLeft(64, '0')}';

  @override
  int compareTo(U256 other) => value.compareTo(other.value);
}

/// 256-bit signed integer, stored as 32 little-endian bytes using two's
/// complement representation.
///
/// Valid range: -2^255 to 2^255 - 1.
class I256 implements Comparable<I256> {
  /// The underlying [BigInt] value. Always in the range [-2^255, 2^255).
  final BigInt value;

  /// Creates an [I256] from a [BigInt].
  ///
  /// Throws [ArgumentError] if [value] is outside the valid range.
  I256(this.value) {
    if (value < _minI256 || value > _maxI256) {
      throw ArgumentError('I256 out of range: $value');
    }
  }

  /// Creates an [I256] with value zero.
  factory I256.zero() => I256(BigInt.zero);

  /// Creates an [I256] from a Dart [int].
  factory I256.fromInt(int v) => I256(BigInt.from(v));

  /// Decodes an [I256] from exactly 32 little-endian bytes in two's
  /// complement representation.
  ///
  /// Throws [ArgumentError] if [bytes] does not have length 32.
  factory I256.fromLeBytes(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('I256.fromLeBytes requires exactly 32 bytes, got ${bytes.length}');
    }
    var unsigned = _bigIntFromLeBytes(bytes, 32);
    // Convert from two's complement: if the high bit is set, subtract 2^256.
    if (unsigned >= (BigInt.one << 255)) {
      unsigned -= _maxU256;
    }
    return I256(unsigned);
  }

  /// Encodes this value as 32 little-endian bytes using two's complement.
  Uint8List toLeBytes() {
    final unsigned = value < BigInt.zero ? value + _maxU256 : value;
    return _bigIntToLeBytes(unsigned, 32);
  }

  @override
  bool operator ==(Object other) => other is I256 && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();

  @override
  int compareTo(I256 other) => value.compareTo(other.value);
}

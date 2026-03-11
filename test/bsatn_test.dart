import 'dart:typed_data';

import 'package:spacetimedb_sdk/src/bsatn/bsatn.dart';
import 'package:test/test.dart';

void main() {
  group('U128', () {
    test('zero', () {
      final v = U128.zero();
      expect(v.value, BigInt.zero);
      expect(v.toLeBytes(), Uint8List(16));
    });

    test('fromInt', () {
      final v = U128.fromInt(255);
      expect(v.value, BigInt.from(255));
    });

    test('round-trip through LE bytes', () {
      final original = U128(BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', radix: 16));
      final bytes = original.toLeBytes();
      expect(bytes.length, 16);
      final decoded = U128.fromLeBytes(bytes);
      expect(decoded, original);
    });

    test('LE byte order', () {
      final v = U128(BigInt.from(0x0102));
      final bytes = v.toLeBytes();
      expect(bytes[0], 0x02); // least significant byte first
      expect(bytes[1], 0x01);
      for (var i = 2; i < 16; i++) {
        expect(bytes[i], 0);
      }
    });

    test('rejects negative', () {
      expect(() => U128(-BigInt.one), throwsArgumentError);
    });

    test('rejects overflow', () {
      expect(() => U128(BigInt.one << 128), throwsArgumentError);
    });

    test('fromLeBytes rejects wrong length', () {
      expect(() => U128.fromLeBytes(Uint8List(15)), throwsArgumentError);
    });

    test('compareTo', () {
      expect(U128.fromInt(1).compareTo(U128.fromInt(2)), isNegative);
      expect(U128.fromInt(2).compareTo(U128.fromInt(2)), isZero);
      expect(U128.fromInt(3).compareTo(U128.fromInt(2)), isPositive);
    });

    test('equality and hashCode', () {
      final a = U128.fromInt(42);
      final b = U128.fromInt(42);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(U128.fromInt(43)));
    });
  });

  group('I128', () {
    test('zero', () {
      final v = I128.zero();
      expect(v.value, BigInt.zero);
    });

    test('positive round-trip', () {
      final original = I128(BigInt.from(12345));
      final decoded = I128.fromLeBytes(original.toLeBytes());
      expect(decoded, original);
    });

    test('negative round-trip', () {
      final original = I128(BigInt.from(-1));
      final bytes = original.toLeBytes();
      // -1 in two's complement should be all 0xFF bytes
      for (var i = 0; i < 16; i++) {
        expect(bytes[i], 0xFF);
      }
      final decoded = I128.fromLeBytes(bytes);
      expect(decoded, original);
    });

    test('min value round-trip', () {
      final min = I128(-(BigInt.one << 127));
      final decoded = I128.fromLeBytes(min.toLeBytes());
      expect(decoded, min);
    });

    test('max value round-trip', () {
      final max = I128((BigInt.one << 127) - BigInt.one);
      final decoded = I128.fromLeBytes(max.toLeBytes());
      expect(decoded, max);
    });

    test('rejects out of range', () {
      expect(() => I128(BigInt.one << 127), throwsArgumentError);
      expect(() => I128(-(BigInt.one << 127) - BigInt.one), throwsArgumentError);
    });

    test('fromInt', () {
      final v = I128.fromInt(-100);
      expect(v.value, BigInt.from(-100));
    });

    test('hashCode and toString', () {
      final v = I128(BigInt.from(42));
      expect(v.hashCode, BigInt.from(42).hashCode);
      expect(v.toString(), '42');
    });

    test('compareTo', () {
      final a = I128(BigInt.from(-10));
      final b = I128(BigInt.from(10));
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      expect(a.compareTo(a), 0);
    });

    test('fromLeBytes rejects wrong length', () {
      expect(() => I128.fromLeBytes(Uint8List(15)), throwsArgumentError);
    });
  });

  group('U256', () {
    test('zero', () {
      final v = U256.zero();
      expect(v.value, BigInt.zero);
      expect(v.toLeBytes(), Uint8List(32));
    });

    test('round-trip max value', () {
      final max = U256((BigInt.one << 256) - BigInt.one);
      final decoded = U256.fromLeBytes(max.toLeBytes());
      expect(decoded, max);
    });

    test('rejects overflow', () {
      expect(() => U256(BigInt.one << 256), throwsArgumentError);
    });

    test('fromLeBytes rejects wrong length', () {
      expect(() => U256.fromLeBytes(Uint8List(31)), throwsArgumentError);
    });

    test('fromInt', () {
      final v = U256.fromInt(999);
      expect(v.value, BigInt.from(999));
    });

    test('hashCode and toString', () {
      final v = U256(BigInt.from(255));
      expect(v.hashCode, BigInt.from(255).hashCode);
      expect(v.toString(), contains('ff'));
    });

    test('compareTo', () {
      final a = U256(BigInt.from(1));
      final b = U256(BigInt.from(2));
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
    });
  });

  group('I256', () {
    test('negative round-trip', () {
      final v = I256(BigInt.from(-42));
      final decoded = I256.fromLeBytes(v.toLeBytes());
      expect(decoded, v);
    });

    test('min value round-trip', () {
      final min = I256(-(BigInt.one << 255));
      final decoded = I256.fromLeBytes(min.toLeBytes());
      expect(decoded, min);
    });

    test('max value round-trip', () {
      final max = I256((BigInt.one << 255) - BigInt.one);
      final decoded = I256.fromLeBytes(max.toLeBytes());
      expect(decoded, max);
    });

    test('rejects out of range', () {
      expect(() => I256(BigInt.one << 255), throwsArgumentError);
    });

    test('zero', () {
      final v = I256.zero();
      expect(v.value, BigInt.zero);
    });

    test('fromInt', () {
      final v = I256.fromInt(-500);
      expect(v.value, BigInt.from(-500));
    });

    test('fromLeBytes rejects wrong length', () {
      expect(() => I256.fromLeBytes(Uint8List(31)), throwsArgumentError);
    });

    test('hashCode and toString', () {
      final v = I256(BigInt.from(-42));
      expect(v.hashCode, BigInt.from(-42).hashCode);
      expect(v.toString(), '-42');
    });

    test('compareTo', () {
      final a = I256(BigInt.from(-10));
      final b = I256(BigInt.from(10));
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
    });
  });

  group('BsatnEncoder + BsatnDecoder symmetry', () {
    test('bool', () {
      final enc = BsatnEncoder();
      enc.writeBool(true);
      enc.writeBool(false);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readBool(), true);
      expect(dec.readBool(), false);
      expect(dec.remaining, 0);
    });

    test('u8 / i8', () {
      final enc = BsatnEncoder();
      enc.writeU8(0);
      enc.writeU8(255);
      enc.writeI8(-128);
      enc.writeI8(127);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readU8(), 0);
      expect(dec.readU8(), 255);
      expect(dec.readI8(), -128);
      expect(dec.readI8(), 127);
      expect(dec.remaining, 0);
    });

    test('u16 / i16', () {
      final enc = BsatnEncoder();
      enc.writeU16(0);
      enc.writeU16(65535);
      enc.writeI16(-32768);
      enc.writeI16(32767);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readU16(), 0);
      expect(dec.readU16(), 65535);
      expect(dec.readI16(), -32768);
      expect(dec.readI16(), 32767);
      expect(dec.remaining, 0);
    });

    test('u32 / i32', () {
      final enc = BsatnEncoder();
      enc.writeU32(0);
      enc.writeU32(0xFFFFFFFF);
      enc.writeI32(-2147483648);
      enc.writeI32(2147483647);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readU32(), 0);
      expect(dec.readU32(), 0xFFFFFFFF);
      expect(dec.readI32(), -2147483648);
      expect(dec.readI32(), 2147483647);
      expect(dec.remaining, 0);
    });

    test('u64 / i64', () {
      final enc = BsatnEncoder();
      enc.writeU64(0);
      enc.writeI64(-1);
      enc.writeI64(9223372036854775807); // max signed 64-bit
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readU64(), 0);
      expect(dec.readI64(), -1);
      expect(dec.readI64(), 9223372036854775807);
      expect(dec.remaining, 0);
    });

    test('u128 / i128', () {
      final enc = BsatnEncoder();
      final u = U128(BigInt.parse('123456789ABCDEF0123456789ABCDEF0', radix: 16));
      final i = I128(BigInt.from(-999));
      enc.writeU128(u);
      enc.writeI128(i);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readU128(), u);
      expect(dec.readI128(), i);
      expect(dec.remaining, 0);
    });

    test('u256 / i256', () {
      final enc = BsatnEncoder();
      final u = U256(BigInt.from(42));
      final i = I256(BigInt.from(-42));
      enc.writeU256(u);
      enc.writeI256(i);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readU256(), u);
      expect(dec.readI256(), i);
      expect(dec.remaining, 0);
    });

    test('f32', () {
      final enc = BsatnEncoder();
      enc.writeF32(3.14);
      enc.writeF32(-0.0);
      enc.writeF32(double.infinity);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readF32(), closeTo(3.14, 0.001));
      expect(dec.readF32(), -0.0);
      expect(dec.readF32(), double.infinity);
      expect(dec.remaining, 0);
    });

    test('f64', () {
      final enc = BsatnEncoder();
      enc.writeF64(3.141592653589793);
      enc.writeF64(double.negativeInfinity);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readF64(), 3.141592653589793);
      expect(dec.readF64(), double.negativeInfinity);
      expect(dec.remaining, 0);
    });

    test('string', () {
      final enc = BsatnEncoder();
      enc.writeString('');
      enc.writeString('hello world');
      enc.writeString('emoji: \u{1F600}'); // multi-byte UTF-8
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readString(), '');
      expect(dec.readString(), 'hello world');
      expect(dec.readString(), 'emoji: \u{1F600}');
      expect(dec.remaining, 0);
    });

    test('bytes', () {
      final enc = BsatnEncoder();
      enc.writeBytes(Uint8List(0));
      enc.writeBytes(Uint8List.fromList([1, 2, 3]));
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readBytes(), Uint8List(0));
      expect(dec.readBytes(), Uint8List.fromList([1, 2, 3]));
      expect(dec.remaining, 0);
    });

    test('raw bytes', () {
      final enc = BsatnEncoder();
      enc.writeRawBytes(Uint8List.fromList([0xDE, 0xAD]));
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readRawBytes(2), Uint8List.fromList([0xDE, 0xAD]));
      expect(dec.remaining, 0);
    });

    test('array header', () {
      final enc = BsatnEncoder();
      enc.writeArrayHeader(3);
      for (var i = 0; i < 3; i++) {
        enc.writeU32(i);
      }
      final dec = BsatnDecoder(enc.toBytes());
      final len = dec.readArrayHeader();
      expect(len, 3);
      for (var i = 0; i < len; i++) {
        expect(dec.readU32(), i);
      }
      expect(dec.remaining, 0);
    });

    test('option some/none', () {
      final enc = BsatnEncoder();
      enc.writeOptionSome();
      enc.writeU32(42);
      enc.writeOptionNone();
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readOption(), true); // Some
      expect(dec.readU32(), 42);
      expect(dec.readOption(), false); // None
      expect(dec.remaining, 0);
    });

    test('sum tag', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(0);
      enc.writeSumTag(255);
      final dec = BsatnDecoder(enc.toBytes());
      expect(dec.readSumTag(), 0);
      expect(dec.readSumTag(), 255);
      expect(dec.remaining, 0);
    });
  });

  group('BsatnDecoder error cases', () {
    test('read past end throws', () {
      final dec = BsatnDecoder(Uint8List(0));
      expect(() => dec.readU8(), throwsA(isA<BsatnDecodeException>()));
    });

    test('invalid bool throws', () {
      final dec = BsatnDecoder(Uint8List.fromList([2]));
      expect(() => dec.readBool(), throwsA(isA<BsatnDecodeException>()));
    });

    test('invalid option tag throws', () {
      final dec = BsatnDecoder(Uint8List.fromList([5]));
      expect(() => dec.readOption(), throwsA(isA<BsatnDecodeException>()));
    });

    test('truncated string throws', () {
      // String header says 100 bytes, but buffer only has the 4-byte header
      final enc = BsatnEncoder();
      enc.writeU32(100);
      final dec = BsatnDecoder(enc.toBytes());
      expect(() => dec.readString(), throwsA(isA<BsatnDecodeException>()));
    });

    test('truncated u32 throws', () {
      final dec = BsatnDecoder(Uint8List.fromList([1, 2])); // only 2 bytes
      expect(() => dec.readU32(), throwsA(isA<BsatnDecodeException>()));
    });
  });

  group('BsatnDecoder with offset ByteData', () {
    test('decoding from a sublist view with non-zero offset', () {
      // Create a larger buffer, encode data in the middle, and decode from
      // a sublist view to test that _bufferOffset is handled correctly.
      final padding = Uint8List(10); // 10 bytes of padding
      final enc = BsatnEncoder();
      enc.writeU32(0xDEADBEEF);
      enc.writeString('test');
      enc.writeI128(I128(BigInt.from(-1)));
      final payload = enc.toBytes();

      // Create combined buffer: [padding | payload | padding]
      final combined = Uint8List(padding.length + payload.length + padding.length);
      combined.setRange(0, padding.length, padding);
      combined.setRange(padding.length, padding.length + payload.length, payload);
      combined.setRange(padding.length + payload.length, combined.length, padding);

      // Create a view into the middle (the payload portion)
      final payloadView = Uint8List.sublistView(
        combined,
        padding.length,
        padding.length + payload.length,
      );

      final dec = BsatnDecoder(payloadView);
      expect(dec.readU32(), 0xDEADBEEF);
      expect(dec.readString(), 'test');
      expect(dec.readI128(), I128(BigInt.from(-1)));
      expect(dec.remaining, 0);
    });
  });

  group('BsatnEncoder length tracking', () {
    test('length reflects written bytes', () {
      final enc = BsatnEncoder();
      expect(enc.length, 0);
      enc.writeBool(true);
      expect(enc.length, 1);
      enc.writeU32(0);
      expect(enc.length, 5);
      enc.writeString('hi');
      expect(enc.length, 5 + 4 + 2); // 4-byte length prefix + 2 bytes of "hi"
    });
  });

  group('LE byte order verification', () {
    test('u16 is little-endian', () {
      final enc = BsatnEncoder();
      enc.writeU16(0x0102);
      final bytes = enc.toBytes();
      expect(bytes[0], 0x02); // low byte first
      expect(bytes[1], 0x01);
    });

    test('u32 is little-endian', () {
      final enc = BsatnEncoder();
      enc.writeU32(0x01020304);
      final bytes = enc.toBytes();
      expect(bytes[0], 0x04);
      expect(bytes[1], 0x03);
      expect(bytes[2], 0x02);
      expect(bytes[3], 0x01);
    });

    test('i32 negative is little-endian two\'s complement', () {
      final enc = BsatnEncoder();
      enc.writeI32(-1);
      final bytes = enc.toBytes();
      for (var i = 0; i < 4; i++) {
        expect(bytes[i], 0xFF);
      }
    });
  });
}

import 'dart:typed_data';

import 'package:spacetimedb_sdk/spacetimedb.dart';
import 'package:test/test.dart';

/// Helper to build a [Uint8List] of [length] bytes all set to [value].
Uint8List filledBytes(int length, int value) =>
    Uint8List(length)..fillRange(0, length, value);

/// Helper to encode a value with [BsatnEncoder] and return the bytes.
Uint8List encodeWith(void Function(BsatnEncoder) fn) {
  final enc = BsatnEncoder();
  fn(enc);
  return enc.toBytes();
}

void main() {
  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------
  group('Identity', () {
    group('construction', () {
      test('accepts exactly 32 bytes', () {
        final data = Uint8List(32);
        final id = Identity(data);
        expect(id.data, data);
      });

      test('rejects data shorter than 32 bytes', () {
        expect(() => Identity(Uint8List(31)), throwsArgumentError);
      });

      test('rejects data longer than 32 bytes', () {
        expect(() => Identity(Uint8List(33)), throwsArgumentError);
      });

      test('rejects empty bytes', () {
        expect(() => Identity(Uint8List(0)), throwsArgumentError);
      });

      test('zero() creates 32 zero bytes', () {
        final id = Identity.zero();
        expect(id.data.length, 32);
        expect(id.data.every((b) => b == 0), isTrue);
      });
    });

    group('fromHex', () {
      test('parses valid 64-char hex string', () {
        const hex = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
        final id = Identity.fromHex(hex);
        expect(id.data[0], 0xDE);
        expect(id.data[1], 0xAD);
        expect(id.data[2], 0xBE);
        expect(id.data[3], 0xEF);
      });

      test('round-trips through toHex', () {
        const hex = '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
        expect(Identity.fromHex(hex).toHex(), hex);
      });

      test('rejects hex string shorter than 64 chars', () {
        expect(() => Identity.fromHex('deadbeef'), throwsArgumentError);
      });

      test('rejects hex string longer than 64 chars', () {
        final long = 'a' * 66;
        expect(() => Identity.fromHex(long), throwsArgumentError);
      });

      test('rejects non-hex characters', () {
        final invalid = 'z' * 64;
        expect(() => Identity.fromHex(invalid), throwsFormatException);
      });
    });

    group('toHex', () {
      test('zero identity produces 64 zeros', () {
        expect(Identity.zero().toHex(), '0' * 64);
      });

      test('produces lowercase hex', () {
        final data = filledBytes(32, 0xAB);
        final id = Identity(data);
        expect(id.toHex(), 'ab' * 32);
      });

      test('single byte 0x0F pads to two characters', () {
        final data = Uint8List(32);
        data[0] = 0x0F;
        expect(Identity(data).toHex().substring(0, 2), '0f');
      });
    });

    group('isZero', () {
      test('zero identity returns true', () {
        expect(Identity.zero().isZero, isTrue);
      });

      test('non-zero identity returns false', () {
        final data = Uint8List(32);
        data[0] = 1;
        expect(Identity(data).isZero, isFalse);
      });

      test('only last byte non-zero returns false', () {
        final data = Uint8List(32);
        data[31] = 1;
        expect(Identity(data).isZero, isFalse);
      });
    });

    group('equality', () {
      test('two identities with same bytes are equal', () {
        final a = Identity(filledBytes(32, 0x42));
        final b = Identity(filledBytes(32, 0x42));
        expect(a, equals(b));
      });

      test('two identities with different bytes are not equal', () {
        final a = Identity(filledBytes(32, 0x01));
        final b = Identity(filledBytes(32, 0x02));
        expect(a, isNot(equals(b)));
      });

      test('identity is not equal to a non-Identity object', () {
        final id = Identity.zero();
        expect(id == 'not an identity', isFalse);
      });

      test('zero identity equals zero identity', () {
        expect(Identity.zero(), equals(Identity.zero()));
      });
    });

    group('hashCode', () {
      test('equal identities have same hashCode', () {
        final a = Identity(filledBytes(32, 0x99));
        final b = Identity(filledBytes(32, 0x99));
        expect(a.hashCode, b.hashCode);
      });

      test('different identities typically have different hashCodes', () {
        final a = Identity(filledBytes(32, 0x11));
        final b = Identity(filledBytes(32, 0x22));
        // This is not guaranteed, but holds for non-pathological cases.
        expect(a.hashCode, isNot(b.hashCode));
      });
    });

    group('toString', () {
      test('format includes hex representation', () {
        final id = Identity.zero();
        expect(id.toString(), 'Identity(${'0' * 64})');
      });

      test('non-zero identity toString', () {
        final data = Uint8List(32);
        data[0] = 0xFF;
        final id = Identity(data);
        expect(id.toString(), startsWith('Identity(ff'));
      });
    });

    group('BSATN round-trip', () {
      test('writeBsatn / readBsatn round-trip with zero', () {
        final original = Identity.zero();
        final bytes = encodeWith(original.writeBsatn);
        expect(bytes.length, 32);
        final decoded = Identity.readBsatn(BsatnDecoder(bytes));
        expect(decoded, original);
      });

      test('writeBsatn / readBsatn round-trip with arbitrary bytes', () {
        final data = Uint8List.fromList(List.generate(32, (i) => i));
        final original = Identity(data);
        final bytes = encodeWith(original.writeBsatn);
        expect(bytes.length, 32);
        final decoded = Identity.readBsatn(BsatnDecoder(bytes));
        expect(decoded, original);
      });

      test('writeBsatn / readBsatn round-trip with all-0xFF bytes', () {
        final original = Identity(filledBytes(32, 0xFF));
        final decoded =
            Identity.readBsatn(BsatnDecoder(encodeWith(original.writeBsatn)));
        expect(decoded, original);
      });

      test('readBsatn throws when buffer is too short', () {
        final short = Uint8List(16); // only 16 bytes, need 32
        expect(
          () => Identity.readBsatn(BsatnDecoder(short)),
          throwsA(isA<BsatnDecodeException>()),
        );
      });

      test('writeBsatn produces exactly 32 bytes', () {
        final id = Identity(filledBytes(32, 0xAB));
        final bytes = encodeWith(id.writeBsatn);
        expect(bytes.length, 32);
      });

      test('decoder position advances after readBsatn', () {
        final id = Identity(filledBytes(32, 0x01));
        final enc = BsatnEncoder();
        id.writeBsatn(enc);
        enc.writeU8(0xAA); // sentinel byte after the identity
        final dec = BsatnDecoder(enc.toBytes());
        Identity.readBsatn(dec);
        expect(dec.readU8(), 0xAA);
        expect(dec.remaining, 0);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // ConnectionId
  // ---------------------------------------------------------------------------
  group('ConnectionId', () {
    group('construction', () {
      test('accepts exactly 16 bytes', () {
        final data = Uint8List(16);
        final cid = ConnectionId(data);
        expect(cid.data, data);
      });

      test('rejects data shorter than 16 bytes', () {
        expect(() => ConnectionId(Uint8List(15)), throwsArgumentError);
      });

      test('rejects data longer than 16 bytes', () {
        expect(() => ConnectionId(Uint8List(17)), throwsArgumentError);
      });

      test('rejects empty bytes', () {
        expect(() => ConnectionId(Uint8List(0)), throwsArgumentError);
      });

      test('zero() creates 16 zero bytes', () {
        final cid = ConnectionId.zero();
        expect(cid.data.length, 16);
        expect(cid.data.every((b) => b == 0), isTrue);
      });
    });

    group('fromHex', () {
      test('parses valid 32-char hex string', () {
        const hex = 'deadbeefdeadbeefdeadbeefdeadbeef';
        final cid = ConnectionId.fromHex(hex);
        expect(cid.data[0], 0xDE);
        expect(cid.data[1], 0xAD);
        expect(cid.data[2], 0xBE);
        expect(cid.data[3], 0xEF);
      });

      test('round-trips through toHex', () {
        const hex = '0102030405060708090a0b0c0d0e0f10';
        expect(ConnectionId.fromHex(hex).toHex(), hex);
      });

      test('rejects hex string shorter than 32 chars', () {
        expect(() => ConnectionId.fromHex('deadbeef'), throwsArgumentError);
      });

      test('rejects hex string longer than 32 chars', () {
        final long = 'a' * 34;
        expect(() => ConnectionId.fromHex(long), throwsArgumentError);
      });

      test('rejects non-hex characters', () {
        final invalid = 'z' * 32;
        expect(() => ConnectionId.fromHex(invalid), throwsFormatException);
      });
    });

    group('toHex', () {
      test('zero connection ID produces 32 zeros', () {
        expect(ConnectionId.zero().toHex(), '0' * 32);
      });

      test('produces lowercase hex', () {
        final data = filledBytes(16, 0xCD);
        final cid = ConnectionId(data);
        expect(cid.toHex(), 'cd' * 16);
      });

      test('single byte 0x0F pads to two characters', () {
        final data = Uint8List(16);
        data[0] = 0x0F;
        expect(ConnectionId(data).toHex().substring(0, 2), '0f');
      });
    });

    group('isZero', () {
      test('zero connection ID returns true', () {
        expect(ConnectionId.zero().isZero, isTrue);
      });

      test('non-zero connection ID returns false', () {
        final data = Uint8List(16);
        data[0] = 1;
        expect(ConnectionId(data).isZero, isFalse);
      });

      test('only last byte non-zero returns false', () {
        final data = Uint8List(16);
        data[15] = 1;
        expect(ConnectionId(data).isZero, isFalse);
      });
    });

    group('equality', () {
      test('two ConnectionIds with same bytes are equal', () {
        final a = ConnectionId(filledBytes(16, 0x42));
        final b = ConnectionId(filledBytes(16, 0x42));
        expect(a, equals(b));
      });

      test('two ConnectionIds with different bytes are not equal', () {
        final a = ConnectionId(filledBytes(16, 0x01));
        final b = ConnectionId(filledBytes(16, 0x02));
        expect(a, isNot(equals(b)));
      });

      test('ConnectionId is not equal to a non-ConnectionId object', () {
        final cid = ConnectionId.zero();
        expect(cid == 'not a connection id', isFalse);
      });

      test('zero ConnectionId equals zero ConnectionId', () {
        expect(ConnectionId.zero(), equals(ConnectionId.zero()));
      });
    });

    group('hashCode', () {
      test('equal ConnectionIds have same hashCode', () {
        final a = ConnectionId(filledBytes(16, 0x77));
        final b = ConnectionId(filledBytes(16, 0x77));
        expect(a.hashCode, b.hashCode);
      });

      test('different ConnectionIds typically have different hashCodes', () {
        final a = ConnectionId(filledBytes(16, 0x11));
        final b = ConnectionId(filledBytes(16, 0x22));
        expect(a.hashCode, isNot(b.hashCode));
      });
    });

    group('toString', () {
      test('format includes hex representation', () {
        final cid = ConnectionId.zero();
        expect(cid.toString(), 'ConnectionId(${'0' * 32})');
      });

      test('non-zero ConnectionId toString', () {
        final data = Uint8List(16);
        data[0] = 0xFF;
        final cid = ConnectionId(data);
        expect(cid.toString(), startsWith('ConnectionId(ff'));
      });
    });

    group('BSATN round-trip', () {
      test('writeBsatn / readBsatn round-trip with zero', () {
        final original = ConnectionId.zero();
        final bytes = encodeWith(original.writeBsatn);
        expect(bytes.length, 16);
        final decoded = ConnectionId.readBsatn(BsatnDecoder(bytes));
        expect(decoded, original);
      });

      test('writeBsatn / readBsatn round-trip with arbitrary bytes', () {
        final data = Uint8List.fromList(List.generate(16, (i) => i * 16));
        final original = ConnectionId(data);
        final bytes = encodeWith(original.writeBsatn);
        expect(bytes.length, 16);
        final decoded = ConnectionId.readBsatn(BsatnDecoder(bytes));
        expect(decoded, original);
      });

      test('writeBsatn / readBsatn round-trip with all-0xFF bytes', () {
        final original = ConnectionId(filledBytes(16, 0xFF));
        final decoded = ConnectionId.readBsatn(
          BsatnDecoder(encodeWith(original.writeBsatn)),
        );
        expect(decoded, original);
      });

      test('readBsatn throws when buffer is too short', () {
        final short = Uint8List(8); // only 8 bytes, need 16
        expect(
          () => ConnectionId.readBsatn(BsatnDecoder(short)),
          throwsA(isA<BsatnDecodeException>()),
        );
      });

      test('writeBsatn produces exactly 16 bytes', () {
        final cid = ConnectionId(filledBytes(16, 0xAB));
        final bytes = encodeWith(cid.writeBsatn);
        expect(bytes.length, 16);
      });

      test('decoder position advances after readBsatn', () {
        final cid = ConnectionId(filledBytes(16, 0x01));
        final enc = BsatnEncoder();
        cid.writeBsatn(enc);
        enc.writeU8(0xBB); // sentinel byte after the connection ID
        final dec = BsatnDecoder(enc.toBytes());
        ConnectionId.readBsatn(dec);
        expect(dec.readU8(), 0xBB);
        expect(dec.remaining, 0);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Token
  // ---------------------------------------------------------------------------
  group('Token', () {
    test('stores the token value', () {
      const raw = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9';
      final token = Token(raw);
      expect(token.value, raw);
    });

    test('isEmpty returns true for empty token', () {
      expect(Token('').isEmpty, isTrue);
    });

    test('isEmpty returns false for non-empty token', () {
      expect(Token('abc').isEmpty, isFalse);
    });

    test('equality: same value', () {
      expect(Token('abc'), equals(Token('abc')));
    });

    test('equality: different values', () {
      expect(Token('abc'), isNot(equals(Token('xyz'))));
    });

    test('hashCode: equal tokens', () {
      expect(Token('abc').hashCode, Token('abc').hashCode);
    });

    test('toString truncates long tokens', () {
      final long = 'a' * 20;
      final s = Token(long).toString();
      expect(s, contains('...'));
      expect(s.length, lessThan(long.length + 10));
    });

    test('toString shows short tokens in full', () {
      final short = Token('short').toString();
      expect(short, contains('short'));
      expect(short, isNot(contains('...')));
    });
  });

  // ---------------------------------------------------------------------------
  // Timestamp
  // ---------------------------------------------------------------------------
  group('Timestamp', () {
    group('construction', () {
      test('stores nanoseconds since epoch', () {
        const ns = 1000000000; // 1 second
        final ts = Timestamp(ns);
        expect(ts.nanosecondsSinceEpoch, ns);
      });

      test('accepts zero', () {
        final ts = Timestamp(0);
        expect(ts.nanosecondsSinceEpoch, 0);
      });

      test('accepts negative values (pre-epoch dates)', () {
        final ts = Timestamp(-1);
        expect(ts.nanosecondsSinceEpoch, -1);
      });

      test('now() returns a recent timestamp', () {
        final before = DateTime.now().microsecondsSinceEpoch * 1000;
        final ts = Timestamp.now();
        final after = DateTime.now().microsecondsSinceEpoch * 1000;
        expect(ts.nanosecondsSinceEpoch, greaterThanOrEqualTo(before));
        expect(ts.nanosecondsSinceEpoch, lessThanOrEqualTo(after));
      });
    });

    group('fromDateTime', () {
      test('converts DateTime to nanoseconds (microseconds * 1000)', () {
        final dt = DateTime.fromMicrosecondsSinceEpoch(1000000); // 1 second
        final ts = Timestamp.fromDateTime(dt);
        expect(ts.nanosecondsSinceEpoch, 1000000 * 1000);
      });

      test('epoch DateTime gives zero nanoseconds', () {
        final epoch = DateTime.fromMicrosecondsSinceEpoch(0);
        final ts = Timestamp.fromDateTime(epoch);
        expect(ts.nanosecondsSinceEpoch, 0);
      });

      test('UTC and local DateTime produce the same nanoseconds', () {
        final dtUtc = DateTime.utc(2024, 1, 15, 12, 30, 0);
        final dtLocal = dtUtc.toLocal();
        expect(
          Timestamp.fromDateTime(dtUtc).nanosecondsSinceEpoch,
          Timestamp.fromDateTime(dtLocal).nanosecondsSinceEpoch,
        );
      });
    });

    group('toDateTime', () {
      test('converts nanoseconds back to DateTime (truncates sub-microsecond)', () {
        // 1500000 ns = 1500 us = 1.5 ms. Sub-microsecond portion truncated.
        final ts = Timestamp(1500000);
        final dt = ts.toDateTime();
        expect(dt.microsecondsSinceEpoch, 1500);
      });

      test('round-trip DateTime -> Timestamp -> DateTime is lossless at microsecond precision', () {
        final original = DateTime.fromMicrosecondsSinceEpoch(1234567890);
        final roundTripped = Timestamp.fromDateTime(original).toDateTime();
        expect(roundTripped.microsecondsSinceEpoch, original.microsecondsSinceEpoch);
      });

      test('zero nanoseconds gives epoch DateTime', () {
        final dt = Timestamp(0).toDateTime();
        expect(dt.microsecondsSinceEpoch, 0);
      });

      test('sub-microsecond nanoseconds are truncated', () {
        // 999 ns < 1000 ns (1 us), so toDateTime gives epoch
        final ts = Timestamp(999);
        expect(ts.toDateTime().microsecondsSinceEpoch, 0);
      });
    });

    group('microsecondsSinceEpoch getter', () {
      test('divides nanoseconds by 1000 (truncating)', () {
        expect(Timestamp(1000000).microsecondsSinceEpoch, 1000);
      });

      test('truncates sub-microsecond nanoseconds', () {
        expect(Timestamp(1999).microsecondsSinceEpoch, 1);
      });

      test('zero nanoseconds gives zero microseconds', () {
        expect(Timestamp(0).microsecondsSinceEpoch, 0);
      });

      test('negative nanoseconds', () {
        // -1000 ns = -1 us (Dart integer division truncates toward zero)
        expect(Timestamp(-1000).microsecondsSinceEpoch, -1);
      });
    });

    group('equality', () {
      test('same nanoseconds are equal', () {
        expect(Timestamp(42), equals(Timestamp(42)));
      });

      test('different nanoseconds are not equal', () {
        expect(Timestamp(1), isNot(equals(Timestamp(2))));
      });

      test('Timestamp is not equal to a non-Timestamp object', () {
        expect(Timestamp(0) == 0, isFalse);
      });
    });

    group('hashCode', () {
      test('equal timestamps have same hashCode', () {
        expect(Timestamp(100).hashCode, Timestamp(100).hashCode);
      });

      test('different timestamps typically have different hashCodes', () {
        expect(Timestamp(1).hashCode, isNot(Timestamp(2).hashCode));
      });
    });

    group('toString', () {
      test('includes nanoseconds value and "ns" suffix', () {
        expect(Timestamp(123456789).toString(), 'Timestamp(123456789 ns)');
      });

      test('zero timestamp', () {
        expect(Timestamp(0).toString(), 'Timestamp(0 ns)');
      });

      test('negative timestamp', () {
        expect(Timestamp(-1).toString(), 'Timestamp(-1 ns)');
      });
    });

    group('BSATN round-trip', () {
      test('writeBsatn / readBsatn round-trip with zero', () {
        final original = Timestamp(0);
        final bytes = encodeWith(original.writeBsatn);
        expect(bytes.length, 8); // i64 = 8 bytes
        final decoded = Timestamp.readBsatn(BsatnDecoder(bytes));
        expect(decoded, original);
      });

      test('writeBsatn / readBsatn round-trip with positive value', () {
        final original = Timestamp(1700000000000000000); // ~2023 in ns
        final decoded = Timestamp.readBsatn(
          BsatnDecoder(encodeWith(original.writeBsatn)),
        );
        expect(decoded, original);
      });

      test('writeBsatn / readBsatn round-trip with negative value', () {
        final original = Timestamp(-1000000000); // 1 second before epoch
        final decoded = Timestamp.readBsatn(
          BsatnDecoder(encodeWith(original.writeBsatn)),
        );
        expect(decoded, original);
      });

      test('writeBsatn / readBsatn round-trip with max i64', () {
        final original = Timestamp(9223372036854775807); // max signed 64-bit
        final decoded = Timestamp.readBsatn(
          BsatnDecoder(encodeWith(original.writeBsatn)),
        );
        expect(decoded, original);
      });

      test('writeBsatn produces exactly 8 bytes', () {
        final bytes = encodeWith(Timestamp(42).writeBsatn);
        expect(bytes.length, 8);
      });

      test('readBsatn throws when buffer is too short', () {
        final short = Uint8List(4); // only 4 bytes, need 8
        expect(
          () => Timestamp.readBsatn(BsatnDecoder(short)),
          throwsA(isA<BsatnDecodeException>()),
        );
      });

      test('decoder position advances after readBsatn', () {
        final ts = Timestamp(123456789);
        final enc = BsatnEncoder();
        ts.writeBsatn(enc);
        enc.writeU8(0xCC); // sentinel byte after timestamp
        final dec = BsatnDecoder(enc.toBytes());
        Timestamp.readBsatn(dec);
        expect(dec.readU8(), 0xCC);
        expect(dec.remaining, 0);
      });

      test('serializes nanoseconds as i64 little-endian', () {
        // 1 second = 1,000,000,000 ns = 0x3B9ACA00
        final ts = Timestamp(0x3B9ACA00);
        final bytes = encodeWith(ts.writeBsatn);
        // Little-endian bytes for 0x3B9ACA00:
        // 0x00, 0xCA, 0x9A, 0x3B, 0x00, 0x00, 0x00, 0x00
        expect(bytes[0], 0x00);
        expect(bytes[1], 0xCA);
        expect(bytes[2], 0x9A);
        expect(bytes[3], 0x3B);
        for (var i = 4; i < 8; i++) {
          expect(bytes[i], 0x00);
        }
      });
    });

    group('fromDateTime and toDateTime consistency', () {
      test('known date round-trip preserves microsecondsSinceEpoch', () {
        // 2024-06-15 00:00:00 UTC
        final dt = DateTime.utc(2024, 6, 15);
        final ts = Timestamp.fromDateTime(dt);
        final result = ts.toDateTime();
        // Compare via microsecondsSinceEpoch to avoid timezone-sensitive field
        // checks (toDateTime returns local time on some platforms).
        expect(result.microsecondsSinceEpoch, dt.microsecondsSinceEpoch);
      });
    });
  });
}

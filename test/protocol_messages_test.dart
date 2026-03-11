import 'dart:io';
import 'dart:typed_data';

import 'package:spacetimedb_sdk/spacetimedb.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Prepends a compression byte (0x00 = none) to a BSATN-encoded payload so
/// that [ServerMessage.decode] can consume it.
Uint8List _withNoCompression(Uint8List payload) {
  final out = Uint8List(1 + payload.length);
  out[0] = 0x00;
  out.setRange(1, out.length, payload);
  return out;
}

/// Builds an empty [BsatnRowList] using [FixedSizeHint] with size 0.
BsatnRowList _emptyRowList() {
  return BsatnRowList(
    sizeHint: const FixedSizeHint(0),
    rowsData: Uint8List(0),
  );
}

/// Builds an empty [DatabaseUpdate] (zero tables).
DatabaseUpdate _emptyDatabaseUpdate() {
  return const DatabaseUpdate(tables: []);
}

/// Encodes a [DatabaseUpdate] into BSATN bytes.
Uint8List _encodeDatabaseUpdate(DatabaseUpdate update) {
  final enc = BsatnEncoder();
  update.writeBsatn(enc);
  return enc.toBytes();
}

/// Encodes a [TableUpdate] into BSATN bytes.
Uint8List _encodeTableUpdate(TableUpdate update) {
  final enc = BsatnEncoder();
  update.writeBsatn(enc);
  return enc.toBytes();
}

/// Encodes a [SubscribeRows] into BSATN bytes.
Uint8List _encodeSubscribeRows(SubscribeRows rows) {
  final enc = BsatnEncoder();
  rows.writeBsatn(enc);
  return enc.toBytes();
}

// ---------------------------------------------------------------------------
// client_messages.dart tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // CLIENT MESSAGES
  // =========================================================================
  group('ClientMessage – CallReducer (tag 0)', () {
    test('writes correct tag byte', () {
      final msg = CallReducer(
        reducer: 'my_reducer',
        args: Uint8List(0),
        requestId: 1,
      );
      final bytes = msg.toBytes();
      expect(bytes[0], 0, reason: 'first byte must be tag 0');
    });

    test('encodes reducer name as BSATN string', () {
      const reducerName = 'some_reducer';
      final msg = CallReducer(
        reducer: reducerName,
        args: Uint8List(0),
        requestId: 7,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      expect(dec.readSumTag(), 0);
      expect(dec.readString(), reducerName);
    });

    test('encodes args as BSATN bytes', () {
      final args = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final msg = CallReducer(
        reducer: 'r',
        args: args,
        requestId: 0,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag(); // tag
      dec.readString(); // reducer name
      expect(dec.readBytes(), args);
    });

    test('encodes requestId as u32', () {
      const reqId = 0xDEADBEEF;
      final msg = CallReducer(
        reducer: 'r',
        args: Uint8List(0),
        requestId: reqId,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      dec.readString();
      dec.readBytes();
      expect(dec.readU32(), reqId);
    });

    test('encodes flags as u8 – fullUpdate (0)', () {
      final msg = CallReducer(
        reducer: 'r',
        args: Uint8List(0),
        requestId: 1,
        flags: CallReducerFlags.fullUpdate,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      dec.readString();
      dec.readBytes();
      dec.readU32();
      expect(dec.readU8(), 0);
    });

    test('encodes flags as u8 – noSuccessNotify (1)', () {
      final msg = CallReducer(
        reducer: 'r',
        args: Uint8List(0),
        requestId: 1,
        flags: CallReducerFlags.noSuccessNotify,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      dec.readString();
      dec.readBytes();
      dec.readU32();
      expect(dec.readU8(), 1);
    });

    test('full round-trip with all fields', () {
      final args = Uint8List.fromList([1, 2, 3]);
      final msg = CallReducer(
        reducer: 'test_reducer',
        args: args,
        requestId: 42,
        flags: CallReducerFlags.noSuccessNotify,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      expect(dec.readSumTag(), 0);
      expect(dec.readString(), 'test_reducer');
      expect(dec.readBytes(), args);
      expect(dec.readU32(), 42);
      expect(dec.readU8(), 1);
      expect(dec.remaining, 0);
    });

    test('toString contains reducer name and requestId', () {
      final msg = CallReducer(
        reducer: 'do_something',
        args: Uint8List(0),
        requestId: 99,
      );
      expect(msg.toString(), contains('do_something'));
      expect(msg.toString(), contains('99'));
    });
  });

  // -------------------------------------------------------------------------
  group('ClientMessage – Subscribe (tag 1)', () {
    test('writes correct tag byte', () {
      final msg = Subscribe(queryStrings: ['SELECT * FROM t'], requestId: 0);
      expect(msg.toBytes()[0], 1);
    });

    test('encodes empty query list', () {
      final msg = Subscribe(queryStrings: [], requestId: 0);
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      expect(dec.readArrayHeader(), 0);
      expect(dec.readU32(), 0);
      expect(dec.remaining, 0);
    });

    test('encodes multiple queries and requestId', () {
      final queries = ['SELECT * FROM a', 'SELECT * FROM b'];
      final msg = Subscribe(queryStrings: queries, requestId: 13);
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      final count = dec.readArrayHeader();
      expect(count, 2);
      for (var i = 0; i < count; i++) {
        expect(dec.readString(), queries[i]);
      }
      expect(dec.readU32(), 13);
      expect(dec.remaining, 0);
    });

    test('toString shows query count and requestId', () {
      final msg = Subscribe(
          queryStrings: ['q1', 'q2', 'q3'], requestId: 7);
      expect(msg.toString(), contains('3'));
      expect(msg.toString(), contains('7'));
    });
  });

  // -------------------------------------------------------------------------
  group('ClientMessage – OneOffQuery (tag 2)', () {
    test('writes correct tag byte', () {
      final msg = OneOffQuery(
        messageId: Uint8List.fromList([1, 2, 3, 4]),
        queryString: 'SELECT 1',
      );
      expect(msg.toBytes()[0], 2);
    });

    test('encodes messageId as BSATN bytes and queryString as string', () {
      final msgId = Uint8List.fromList([0xAA, 0xBB]);
      final query = 'SELECT * FROM items';
      final msg = OneOffQuery(messageId: msgId, queryString: query);
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      expect(dec.readBytes(), msgId);
      expect(dec.readString(), query);
      expect(dec.remaining, 0);
    });

    test('encodes empty messageId', () {
      final msg = OneOffQuery(
        messageId: Uint8List(0),
        queryString: 'SELECT 1',
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      expect(dec.readBytes(), Uint8List(0));
      expect(dec.readString(), 'SELECT 1');
      expect(dec.remaining, 0);
    });

    test('toString contains queryString', () {
      final msg = OneOffQuery(
        messageId: Uint8List(0),
        queryString: 'SELECT id FROM users',
      );
      expect(msg.toString(), contains('SELECT id FROM users'));
    });
  });

  // -------------------------------------------------------------------------
  group('ClientMessage – SubscribeSingle (tag 3)', () {
    test('writes correct tag byte', () {
      final msg = SubscribeSingle(
        query: 'SELECT * FROM t',
        requestId: 1,
        queryId: 1,
      );
      expect(msg.toBytes()[0], 3);
    });

    test('encodes query, requestId, queryId', () {
      final msg = SubscribeSingle(
        query: 'SELECT id FROM players',
        requestId: 100,
        queryId: 200,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      expect(dec.readSumTag(), 3);
      expect(dec.readString(), 'SELECT id FROM players');
      expect(dec.readU32(), 100);
      expect(dec.readU32(), 200);
      expect(dec.remaining, 0);
    });

    test('toString contains query, requestId, queryId', () {
      final msg = SubscribeSingle(
        query: 'SELECT 1',
        requestId: 5,
        queryId: 10,
      );
      final s = msg.toString();
      expect(s, contains('SELECT 1'));
      expect(s, contains('5'));
      expect(s, contains('10'));
    });
  });

  // -------------------------------------------------------------------------
  group('ClientMessage – SubscribeMulti (tag 4)', () {
    test('writes correct tag byte', () {
      final msg = SubscribeMulti(
        queryStrings: [],
        requestId: 0,
        queryId: 0,
      );
      expect(msg.toBytes()[0], 4);
    });

    test('encodes queries, requestId, queryId', () {
      final queries = ['SELECT * FROM a', 'SELECT * FROM b', 'SELECT * FROM c'];
      final msg = SubscribeMulti(
        queryStrings: queries,
        requestId: 50,
        queryId: 99,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      expect(dec.readSumTag(), 4);
      final count = dec.readArrayHeader();
      expect(count, 3);
      for (var i = 0; i < count; i++) {
        expect(dec.readString(), queries[i]);
      }
      expect(dec.readU32(), 50);
      expect(dec.readU32(), 99);
      expect(dec.remaining, 0);
    });

    test('encodes empty query list', () {
      final msg = SubscribeMulti(
        queryStrings: [],
        requestId: 1,
        queryId: 2,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      expect(dec.readArrayHeader(), 0);
      expect(dec.readU32(), 1);
      expect(dec.readU32(), 2);
      expect(dec.remaining, 0);
    });

    test('toString contains query count, requestId, queryId', () {
      final msg = SubscribeMulti(
        queryStrings: ['q1', 'q2'],
        requestId: 3,
        queryId: 4,
      );
      final s = msg.toString();
      expect(s, contains('2'));
      expect(s, contains('3'));
      expect(s, contains('4'));
    });
  });

  // -------------------------------------------------------------------------
  group('ClientMessage – UnsubscribeMsg (tag 5)', () {
    test('writes correct tag byte', () {
      final msg = UnsubscribeMsg(requestId: 0, queryId: 0);
      expect(msg.toBytes()[0], 5);
    });

    test('encodes requestId and queryId', () {
      final msg = UnsubscribeMsg(requestId: 77, queryId: 88);
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      expect(dec.readSumTag(), 5);
      expect(dec.readU32(), 77);
      expect(dec.readU32(), 88);
      expect(dec.remaining, 0);
    });

    test('toString contains requestId and queryId', () {
      final msg = UnsubscribeMsg(requestId: 12, queryId: 34);
      final s = msg.toString();
      expect(s, contains('12'));
      expect(s, contains('34'));
    });
  });

  // -------------------------------------------------------------------------
  group('ClientMessage – UnsubscribeMulti (tag 6)', () {
    test('writes correct tag byte', () {
      final msg = UnsubscribeMulti(requestId: 0, queryId: 0);
      expect(msg.toBytes()[0], 6);
    });

    test('encodes requestId and queryId', () {
      final msg = UnsubscribeMulti(requestId: 1001, queryId: 2002);
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      expect(dec.readSumTag(), 6);
      expect(dec.readU32(), 1001);
      expect(dec.readU32(), 2002);
      expect(dec.remaining, 0);
    });

    test('toString contains requestId and queryId', () {
      final msg = UnsubscribeMulti(requestId: 55, queryId: 66);
      final s = msg.toString();
      expect(s, contains('55'));
      expect(s, contains('66'));
    });
  });

  // -------------------------------------------------------------------------
  group('ClientMessage – CallProcedure (tag 7)', () {
    test('writes correct tag byte', () {
      final msg = CallProcedure(
        procedure: 'proc',
        args: Uint8List(0),
        requestId: 0,
      );
      expect(msg.toBytes()[0], 7);
    });

    test('full round-trip with all fields', () {
      final args = Uint8List.fromList([10, 20, 30]);
      final msg = CallProcedure(
        procedure: 'update_record',
        args: args,
        requestId: 999,
        flags: CallReducerFlags.noSuccessNotify,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      expect(dec.readSumTag(), 7);
      expect(dec.readString(), 'update_record');
      expect(dec.readBytes(), args);
      expect(dec.readU32(), 999);
      expect(dec.readU8(), 1); // noSuccessNotify
      expect(dec.remaining, 0);
    });

    test('default flags is fullUpdate (0)', () {
      final msg = CallProcedure(
        procedure: 'p',
        args: Uint8List(0),
        requestId: 0,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      dec.readString();
      dec.readBytes();
      dec.readU32();
      expect(dec.readU8(), 0);
    });

    test('encodes procedure name and args independently', () {
      final args = Uint8List.fromList([0xFF]);
      final msg = CallProcedure(
        procedure: 'hello_proc',
        args: args,
        requestId: 5,
      );
      final bytes = msg.toBytes();
      final dec = BsatnDecoder(bytes);
      dec.readSumTag();
      expect(dec.readString(), 'hello_proc');
      expect(dec.readBytes(), args);
    });

    test('toString contains procedure name and requestId', () {
      final msg = CallProcedure(
        procedure: 'do_work',
        args: Uint8List(0),
        requestId: 123,
      );
      expect(msg.toString(), contains('do_work'));
      expect(msg.toString(), contains('123'));
    });
  });

  // =========================================================================
  // SERVER MESSAGES
  // =========================================================================

  group('ServerMessage.decode – IdentityToken (tag 3)', () {
    Uint8List _buildPayload() {
      final enc = BsatnEncoder();
      enc.writeSumTag(3); // IdentityToken tag

      // identity: 32 raw bytes
      final identityBytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        identityBytes[i] = i;
      }
      enc.writeRawBytes(identityBytes);

      // token: string
      enc.writeString('jwt_token_here');

      // connectionId: 16 raw bytes
      final connIdBytes = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        connIdBytes[i] = i + 100;
      }
      enc.writeRawBytes(connIdBytes);

      return enc.toBytes();
    }

    test('decodes as IdentityToken', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<IdentityToken>());
    });

    test('identity bytes are correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as IdentityToken;
      for (var i = 0; i < 32; i++) {
        expect(msg.identity.data[i], i);
      }
    });

    test('token string is correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as IdentityToken;
      expect(msg.token, 'jwt_token_here');
    });

    test('connectionId bytes are correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as IdentityToken;
      for (var i = 0; i < 16; i++) {
        expect(msg.connectionId.data[i], i + 100);
      }
    });

    test('toString contains identity and connectionId', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as IdentityToken;
      final s = msg.toString();
      expect(s, contains('IdentityToken'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – InitialSubscription (tag 0)', () {
    Uint8List _buildPayload({int requestId = 42, int durationNs = 5000000}) {
      final enc = BsatnEncoder();
      enc.writeSumTag(0); // InitialSubscription tag

      // databaseUpdate: empty (0 tables)
      _emptyDatabaseUpdate().writeBsatn(enc);

      // requestId: u32
      enc.writeU32(requestId);

      // totalHostExecutionDuration: i64 nanoseconds
      enc.writeI64(durationNs);

      return enc.toBytes();
    }

    test('decodes as InitialSubscription', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<InitialSubscription>());
    });

    test('requestId is correct', () {
      final raw = _withNoCompression(_buildPayload(requestId: 77));
      final msg = ServerMessage.decode(raw) as InitialSubscription;
      expect(msg.requestId, 77);
    });

    test('totalHostExecutionDuration nanoseconds are correct', () {
      final raw = _withNoCompression(_buildPayload(durationNs: 1000000));
      final msg = ServerMessage.decode(raw) as InitialSubscription;
      expect(msg.totalHostExecutionDuration.nanoseconds, 1000000);
    });

    test('totalHostExecutionDurationMicros convenience getter', () {
      final raw = _withNoCompression(_buildPayload(durationNs: 2000000));
      final msg = ServerMessage.decode(raw) as InitialSubscription;
      expect(msg.totalHostExecutionDurationMicros, 2000);
    });

    test('databaseUpdate has zero tables', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as InitialSubscription;
      expect(msg.databaseUpdate.tables, isEmpty);
    });

    test('databaseUpdate with one table', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(0);

      // databaseUpdate with 1 table
      enc.writeArrayHeader(1);
      enc.writeU32(7); // tableId
      enc.writeString('players'); // tableName
      enc.writeU64(0); // numRows
      enc.writeArrayHeader(0); // 0 updates

      enc.writeU32(1); // requestId
      enc.writeI64(0); // duration

      final raw = _withNoCompression(enc.toBytes());
      final msg = ServerMessage.decode(raw) as InitialSubscription;
      expect(msg.databaseUpdate.tables.length, 1);
      expect(msg.databaseUpdate.tables[0].tableId, 7);
      expect(msg.databaseUpdate.tables[0].tableName, 'players');
    });

    test('toString contains requestId and duration', () {
      final raw = _withNoCompression(_buildPayload(requestId: 42));
      final msg = ServerMessage.decode(raw) as InitialSubscription;
      final s = msg.toString();
      expect(s, contains('InitialSubscription'));
      expect(s, contains('42'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – TransactionUpdateLight (tag 2)', () {
    Uint8List _buildPayload({int requestId = 10}) {
      final enc = BsatnEncoder();
      enc.writeSumTag(2); // TransactionUpdateLight tag
      enc.writeU32(requestId);
      _emptyDatabaseUpdate().writeBsatn(enc);
      return enc.toBytes();
    }

    test('decodes as TransactionUpdateLight', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<TransactionUpdateLight>());
    });

    test('requestId is correct', () {
      final raw = _withNoCompression(_buildPayload(requestId: 999));
      final msg = ServerMessage.decode(raw) as TransactionUpdateLight;
      expect(msg.requestId, 999);
    });

    test('update has zero tables', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdateLight;
      expect(msg.update.tables, isEmpty);
    });

    test('update with one table', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(2);
      enc.writeU32(5); // requestId

      // DatabaseUpdate with 1 table
      enc.writeArrayHeader(1);
      enc.writeU32(42); // tableId
      enc.writeString('scores'); // tableName
      enc.writeU64(10); // numRows
      enc.writeArrayHeader(0); // 0 updates

      final raw = _withNoCompression(enc.toBytes());
      final msg = ServerMessage.decode(raw) as TransactionUpdateLight;
      expect(msg.requestId, 5);
      expect(msg.update.tables.length, 1);
      expect(msg.update.tables[0].tableName, 'scores');
      expect(msg.update.tables[0].numRows, 10);
    });

    test('toString contains requestId', () {
      final raw = _withNoCompression(_buildPayload(requestId: 42));
      final msg = ServerMessage.decode(raw) as TransactionUpdateLight;
      expect(msg.toString(), contains('42'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – TransactionUpdate (tag 1)', () {
    Uint8List _buildPayload() {
      final enc = BsatnEncoder();
      enc.writeSumTag(1); // TransactionUpdate tag

      // status: Committed (tag 0) with empty DatabaseUpdate
      enc.writeSumTag(0);
      _emptyDatabaseUpdate().writeBsatn(enc);

      // timestamp: i64 nanoseconds
      enc.writeI64(1700000000000000000);

      // callerIdentity: 32 raw bytes
      enc.writeRawBytes(Uint8List(32));

      // callerConnectionId: 16 raw bytes
      enc.writeRawBytes(Uint8List(16));

      // reducerCall: reducerName, reducerId, args, requestId
      enc.writeString('my_reducer');
      enc.writeU32(1); // reducerId
      enc.writeBytes(Uint8List(0)); // args
      enc.writeU32(42); // requestId

      // energyQuantaUsed: U128 (16 bytes)
      enc.writeU128(U128.zero());

      // totalHostExecutionDuration: i64 nanoseconds
      enc.writeI64(3000000);

      return enc.toBytes();
    }

    test('decodes as TransactionUpdate', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<TransactionUpdate>());
    });

    test('status is Committed', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.status, isA<Committed>());
    });

    test('committed database update has zero tables', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      final committed = msg.status as Committed;
      expect(committed.databaseUpdate.tables, isEmpty);
    });

    test('timestamp is correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.timestamp.nanosecondsSinceEpoch, 1700000000000000000);
    });

    test('callerIdentity is zero identity', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.callerIdentity.isZero, isTrue);
    });

    test('callerConnectionId is zero', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.callerConnectionId.isZero, isTrue);
    });

    test('reducerCall fields are correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.reducerCall.reducerName, 'my_reducer');
      expect(msg.reducerCall.reducerId, 1);
      expect(msg.reducerCall.requestId, 42);
    });

    test('totalHostExecutionDuration is correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.totalHostExecutionDuration.nanoseconds, 3000000);
    });

    test('totalHostExecutionDurationMicros convenience getter', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.totalHostExecutionDurationMicros, 3000);
    });

    test('status Failed decodes error message', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(1);

      // status: Failed (tag 1)
      enc.writeSumTag(1);
      enc.writeString('reducer panicked');

      // timestamp
      enc.writeI64(0);
      // callerIdentity (32 bytes)
      enc.writeRawBytes(Uint8List(32));
      // callerConnectionId (16 bytes)
      enc.writeRawBytes(Uint8List(16));
      // reducerCall
      enc.writeString('bad_reducer');
      enc.writeU32(0);
      enc.writeBytes(Uint8List(0));
      enc.writeU32(0);
      // energyQuantaUsed
      enc.writeU128(U128.zero());
      // totalHostExecutionDuration
      enc.writeI64(0);

      final raw = _withNoCompression(enc.toBytes());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.status, isA<Failed>());
      expect((msg.status as Failed).errorMessage, 'reducer panicked');
    });

    test('status OutOfEnergy decodes correctly', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(1);

      // status: OutOfEnergy (tag 2)
      enc.writeSumTag(2);

      enc.writeI64(0);
      enc.writeRawBytes(Uint8List(32));
      enc.writeRawBytes(Uint8List(16));
      enc.writeString('reducer');
      enc.writeU32(0);
      enc.writeBytes(Uint8List(0));
      enc.writeU32(0);
      enc.writeU128(U128.zero());
      enc.writeI64(0);

      final raw = _withNoCompression(enc.toBytes());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      expect(msg.status, isA<OutOfEnergy>());
    });

    test('toString contains reducer name and status', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as TransactionUpdate;
      final s = msg.toString();
      expect(s, contains('TransactionUpdate'));
      expect(s, contains('my_reducer'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – OneOffQueryResponse (tag 4)', () {
    Uint8List _buildPayload({
      List<int> msgId = const [1, 2, 3, 4],
      String? error,
      int durationNs = 100000,
    }) {
      final enc = BsatnEncoder();
      enc.writeSumTag(4); // OneOffQueryResponse tag

      // messageId: bytes
      enc.writeBytes(Uint8List.fromList(msgId));

      // error: Option<String>
      if (error != null) {
        enc.writeOptionSome();
        enc.writeString(error);
      } else {
        enc.writeOptionNone();
      }

      // tables: empty array
      enc.writeArrayHeader(0);

      // totalHostExecutionDuration: i64 nanoseconds
      enc.writeI64(durationNs);

      return enc.toBytes();
    }

    test('decodes as OneOffQueryResponse', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<OneOffQueryResponse>());
    });

    test('messageId is correct', () {
      final raw = _withNoCompression(_buildPayload(msgId: [9, 8, 7]));
      final msg = ServerMessage.decode(raw) as OneOffQueryResponse;
      expect(msg.messageId, Uint8List.fromList([9, 8, 7]));
    });

    test('error is null when None', () {
      final raw = _withNoCompression(_buildPayload(error: null));
      final msg = ServerMessage.decode(raw) as OneOffQueryResponse;
      expect(msg.error, isNull);
      expect(msg.isSuccess, isTrue);
      expect(msg.isError, isFalse);
    });

    test('error is set when Some', () {
      final raw =
          _withNoCompression(_buildPayload(error: 'table does not exist'));
      final msg = ServerMessage.decode(raw) as OneOffQueryResponse;
      expect(msg.error, 'table does not exist');
      expect(msg.isError, isTrue);
      expect(msg.isSuccess, isFalse);
    });

    test('tables list is empty', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as OneOffQueryResponse;
      expect(msg.tables, isEmpty);
    });

    test('tables list with one table', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(4);
      enc.writeBytes(Uint8List.fromList([0x01]));
      enc.writeOptionNone(); // no error
      enc.writeArrayHeader(1); // 1 table
      // OneOffTable: tableName + BsatnRowList
      enc.writeString('result_table');
      // BsatnRowList: RowSizeHint (FixedSizeHint tag=0, size=0) + rowsData
      enc.writeSumTag(0); // FixedSizeHint
      enc.writeU16(0); // size
      enc.writeBytes(Uint8List(0)); // rowsData
      enc.writeI64(0); // duration

      final raw = _withNoCompression(enc.toBytes());
      final msg = ServerMessage.decode(raw) as OneOffQueryResponse;
      expect(msg.tables.length, 1);
      expect(msg.tables[0].tableName, 'result_table');
    });

    test('totalHostExecutionDuration is correct', () {
      final raw =
          _withNoCompression(_buildPayload(durationNs: 500000));
      final msg = ServerMessage.decode(raw) as OneOffQueryResponse;
      expect(msg.totalHostExecutionDuration.nanoseconds, 500000);
    });

    test('toString contains table count and error info', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as OneOffQueryResponse;
      expect(msg.toString(), contains('OneOffQueryResponse'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – SubscribeApplied (tag 5)', () {
    Uint8List _buildPayload({
      int requestId = 1,
      int durationMicros = 1234,
      int queryId = 10,
    }) {
      final enc = BsatnEncoder();
      enc.writeSumTag(5); // SubscribeApplied tag

      enc.writeU32(requestId);
      enc.writeU64(durationMicros);
      enc.writeU32(queryId);

      // SubscribeRows: tableId + tableName + TableUpdate
      enc.writeU32(100); // tableId
      enc.writeString('my_table'); // tableName
      // TableUpdate: tableId + tableName + numRows + updates
      enc.writeU32(100);
      enc.writeString('my_table');
      enc.writeU64(0); // numRows
      enc.writeArrayHeader(0); // 0 updates

      return enc.toBytes();
    }

    test('decodes as SubscribeApplied', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<SubscribeApplied>());
    });

    test('requestId is correct', () {
      final raw = _withNoCompression(_buildPayload(requestId: 555));
      final msg = ServerMessage.decode(raw) as SubscribeApplied;
      expect(msg.requestId, 555);
    });

    test('totalHostExecutionDurationMicros is correct', () {
      final raw = _withNoCompression(_buildPayload(durationMicros: 9876));
      final msg = ServerMessage.decode(raw) as SubscribeApplied;
      expect(msg.totalHostExecutionDurationMicros, 9876);
    });

    test('queryId is correct', () {
      final raw = _withNoCompression(_buildPayload(queryId: 42));
      final msg = ServerMessage.decode(raw) as SubscribeApplied;
      expect(msg.queryId, 42);
    });

    test('rows tableId and tableName are correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as SubscribeApplied;
      expect(msg.rows.tableId, 100);
      expect(msg.rows.tableName, 'my_table');
    });

    test('toString contains requestId and queryId', () {
      final raw = _withNoCompression(_buildPayload(requestId: 1, queryId: 10));
      final msg = ServerMessage.decode(raw) as SubscribeApplied;
      final s = msg.toString();
      expect(s, contains('SubscribeApplied'));
      expect(s, contains('1'));
      expect(s, contains('10'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – UnsubscribeApplied (tag 6)', () {
    Uint8List _buildPayload({
      int requestId = 2,
      int durationMicros = 500,
      int queryId = 20,
    }) {
      final enc = BsatnEncoder();
      enc.writeSumTag(6); // UnsubscribeApplied tag

      enc.writeU32(requestId);
      enc.writeU64(durationMicros);
      enc.writeU32(queryId);

      // SubscribeRows
      enc.writeU32(200); // tableId
      enc.writeString('other_table'); // tableName
      // TableUpdate
      enc.writeU32(200);
      enc.writeString('other_table');
      enc.writeU64(0);
      enc.writeArrayHeader(0);

      return enc.toBytes();
    }

    test('decodes as UnsubscribeApplied', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<UnsubscribeApplied>());
    });

    test('requestId is correct', () {
      final raw = _withNoCompression(_buildPayload(requestId: 777));
      final msg = ServerMessage.decode(raw) as UnsubscribeApplied;
      expect(msg.requestId, 777);
    });

    test('totalHostExecutionDurationMicros is correct', () {
      final raw = _withNoCompression(_buildPayload(durationMicros: 1111));
      final msg = ServerMessage.decode(raw) as UnsubscribeApplied;
      expect(msg.totalHostExecutionDurationMicros, 1111);
    });

    test('queryId is correct', () {
      final raw = _withNoCompression(_buildPayload(queryId: 88));
      final msg = ServerMessage.decode(raw) as UnsubscribeApplied;
      expect(msg.queryId, 88);
    });

    test('rows tableId and tableName are correct', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as UnsubscribeApplied;
      expect(msg.rows.tableId, 200);
      expect(msg.rows.tableName, 'other_table');
    });

    test('toString contains requestId and queryId', () {
      final raw =
          _withNoCompression(_buildPayload(requestId: 2, queryId: 20));
      final msg = ServerMessage.decode(raw) as UnsubscribeApplied;
      final s = msg.toString();
      expect(s, contains('UnsubscribeApplied'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – SubscriptionError (tag 7)', () {
    Uint8List _buildPayload({
      int durationMicros = 100,
      int? requestId,
      int? queryId,
      int? tableId,
      String error = 'syntax error',
    }) {
      final enc = BsatnEncoder();
      enc.writeSumTag(7); // SubscriptionError tag

      enc.writeU64(durationMicros);

      // requestId: Option<u32>
      if (requestId != null) {
        enc.writeOptionSome();
        enc.writeU32(requestId);
      } else {
        enc.writeOptionNone();
      }

      // queryId: Option<u32>
      if (queryId != null) {
        enc.writeOptionSome();
        enc.writeU32(queryId);
      } else {
        enc.writeOptionNone();
      }

      // tableId: Option<u32>
      if (tableId != null) {
        enc.writeOptionSome();
        enc.writeU32(tableId);
      } else {
        enc.writeOptionNone();
      }

      // error: String
      enc.writeString(error);

      return enc.toBytes();
    }

    test('decodes as SubscriptionError', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<SubscriptionError>());
    });

    test('totalHostExecutionDurationMicros is correct', () {
      final raw = _withNoCompression(_buildPayload(durationMicros: 9999));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.totalHostExecutionDurationMicros, 9999);
    });

    test('requestId is null when None', () {
      final raw = _withNoCompression(_buildPayload(requestId: null));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.requestId, isNull);
    });

    test('requestId is set when Some', () {
      final raw = _withNoCompression(_buildPayload(requestId: 333));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.requestId, 333);
    });

    test('queryId is null when None', () {
      final raw = _withNoCompression(_buildPayload(queryId: null));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.queryId, isNull);
    });

    test('queryId is set when Some', () {
      final raw = _withNoCompression(_buildPayload(queryId: 444));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.queryId, 444);
    });

    test('tableId is null when None', () {
      final raw = _withNoCompression(_buildPayload(tableId: null));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.tableId, isNull);
    });

    test('tableId is set when Some', () {
      final raw = _withNoCompression(_buildPayload(tableId: 555));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.tableId, 555);
    });

    test('error string is correct', () {
      final raw = _withNoCompression(
          _buildPayload(error: 'table "foo" does not exist'));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.error, 'table "foo" does not exist');
    });

    test('all optional fields set simultaneously', () {
      final raw = _withNoCompression(_buildPayload(
        durationMicros: 1,
        requestId: 11,
        queryId: 22,
        tableId: 33,
        error: 'oh no',
      ));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.requestId, 11);
      expect(msg.queryId, 22);
      expect(msg.tableId, 33);
      expect(msg.error, 'oh no');
    });

    test('toString contains error message', () {
      final raw = _withNoCompression(_buildPayload(error: 'bad query'));
      final msg = ServerMessage.decode(raw) as SubscriptionError;
      expect(msg.toString(), contains('bad query'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – SubscribeMultiApplied (tag 8)', () {
    Uint8List _buildPayload({
      int requestId = 3,
      int durationMicros = 200,
      int queryId = 30,
    }) {
      final enc = BsatnEncoder();
      enc.writeSumTag(8);
      enc.writeU32(requestId);
      enc.writeU64(durationMicros);
      enc.writeU32(queryId);
      _emptyDatabaseUpdate().writeBsatn(enc);
      return enc.toBytes();
    }

    test('decodes as SubscribeMultiApplied', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<SubscribeMultiApplied>());
    });

    test('requestId is correct', () {
      final raw = _withNoCompression(_buildPayload(requestId: 111));
      final msg = ServerMessage.decode(raw) as SubscribeMultiApplied;
      expect(msg.requestId, 111);
    });

    test('totalHostExecutionDurationMicros is correct', () {
      final raw = _withNoCompression(_buildPayload(durationMicros: 300));
      final msg = ServerMessage.decode(raw) as SubscribeMultiApplied;
      expect(msg.totalHostExecutionDurationMicros, 300);
    });

    test('queryId is correct', () {
      final raw = _withNoCompression(_buildPayload(queryId: 77));
      final msg = ServerMessage.decode(raw) as SubscribeMultiApplied;
      expect(msg.queryId, 77);
    });

    test('update has zero tables', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as SubscribeMultiApplied;
      expect(msg.update.tables, isEmpty);
    });

    test('toString contains requestId and queryId', () {
      final raw = _withNoCompression(_buildPayload(requestId: 3, queryId: 30));
      final msg = ServerMessage.decode(raw) as SubscribeMultiApplied;
      expect(msg.toString(), contains('SubscribeMultiApplied'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – UnsubscribeMultiApplied (tag 9)', () {
    Uint8List _buildPayload({
      int requestId = 4,
      int durationMicros = 250,
      int queryId = 40,
    }) {
      final enc = BsatnEncoder();
      enc.writeSumTag(9);
      enc.writeU32(requestId);
      enc.writeU64(durationMicros);
      enc.writeU32(queryId);
      _emptyDatabaseUpdate().writeBsatn(enc);
      return enc.toBytes();
    }

    test('decodes as UnsubscribeMultiApplied', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<UnsubscribeMultiApplied>());
    });

    test('requestId is correct', () {
      final raw = _withNoCompression(_buildPayload(requestId: 222));
      final msg = ServerMessage.decode(raw) as UnsubscribeMultiApplied;
      expect(msg.requestId, 222);
    });

    test('totalHostExecutionDurationMicros is correct', () {
      final raw = _withNoCompression(_buildPayload(durationMicros: 700));
      final msg = ServerMessage.decode(raw) as UnsubscribeMultiApplied;
      expect(msg.totalHostExecutionDurationMicros, 700);
    });

    test('queryId is correct', () {
      final raw = _withNoCompression(_buildPayload(queryId: 99));
      final msg = ServerMessage.decode(raw) as UnsubscribeMultiApplied;
      expect(msg.queryId, 99);
    });

    test('update has zero tables', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as UnsubscribeMultiApplied;
      expect(msg.update.tables, isEmpty);
    });

    test('toString contains requestId and queryId', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw) as UnsubscribeMultiApplied;
      expect(msg.toString(), contains('UnsubscribeMultiApplied'));
    });
  });

  // -------------------------------------------------------------------------
  group('ServerMessage.decode – ProcedureResult (tag 10)', () {
    Uint8List _buildPayload({
      bool committed = true,
      String? errorMsg,
      int requestId = 5,
      int durationNs = 1000000,
      int timestampNs = 0,
    }) {
      final enc = BsatnEncoder();
      enc.writeSumTag(10);

      // status: ProcedureCommitted(tag 0) or ProcedureFailed(tag 1)
      if (committed) {
        enc.writeSumTag(0);
        _emptyDatabaseUpdate().writeBsatn(enc);
      } else {
        enc.writeSumTag(1);
        enc.writeString(errorMsg ?? 'procedure error');
      }

      // timestamp: i64 nanoseconds
      enc.writeI64(timestampNs);

      // totalHostExecutionDuration: i64 nanoseconds
      enc.writeI64(durationNs);

      // requestId: u32
      enc.writeU32(requestId);

      return enc.toBytes();
    }

    test('decodes as ProcedureResult', () {
      final raw = _withNoCompression(_buildPayload());
      final msg = ServerMessage.decode(raw);
      expect(msg, isA<ProcedureResult>());
    });

    test('status is ProcedureCommitted', () {
      final raw = _withNoCompression(_buildPayload(committed: true));
      final msg = ServerMessage.decode(raw) as ProcedureResult;
      expect(msg.status, isA<ProcedureCommitted>());
    });

    test('status is ProcedureFailed', () {
      final raw = _withNoCompression(
          _buildPayload(committed: false, errorMsg: 'proc failed'));
      final msg = ServerMessage.decode(raw) as ProcedureResult;
      expect(msg.status, isA<ProcedureFailed>());
      expect((msg.status as ProcedureFailed).errorMessage, 'proc failed');
    });

    test('requestId is correct', () {
      final raw = _withNoCompression(_buildPayload(requestId: 888));
      final msg = ServerMessage.decode(raw) as ProcedureResult;
      expect(msg.requestId, 888);
    });

    test('totalHostExecutionDuration nanoseconds are correct', () {
      final raw = _withNoCompression(_buildPayload(durationNs: 2500000));
      final msg = ServerMessage.decode(raw) as ProcedureResult;
      expect(msg.totalHostExecutionDuration.nanoseconds, 2500000);
    });

    test('timestamp nanoseconds are correct', () {
      final raw = _withNoCompression(
          _buildPayload(timestampNs: 1000000000));
      final msg = ServerMessage.decode(raw) as ProcedureResult;
      expect(msg.timestamp.nanosecondsSinceEpoch, 1000000000);
    });

    test('toString contains requestId and status', () {
      final raw = _withNoCompression(_buildPayload(requestId: 5));
      final msg = ServerMessage.decode(raw) as ProcedureResult;
      final s = msg.toString();
      expect(s, contains('ProcedureResult'));
      expect(s, contains('5'));
    });
  });

  // =========================================================================
  // ERROR CASES
  // =========================================================================
  group('ServerMessage.decode – error cases', () {
    test('empty bytes throws BsatnDecodeException', () {
      expect(
        () => ServerMessage.decode(Uint8List(0)),
        throwsA(isA<BsatnDecodeException>()),
      );
    });

    test('Brotli compression tag throws UnsupportedError', () {
      final raw = Uint8List.fromList([1, 0]); // compression=1 (Brotli)
      expect(
        () => ServerMessage.decode(raw),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('gzip compression tag decodes correctly', () {
      // Build a valid IdentityToken BSATN payload (without compression prefix)
      final enc = BsatnEncoder();
      enc.writeSumTag(3); // IdentityToken tag

      // identity: 32 raw bytes
      final identityBytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        identityBytes[i] = i;
      }
      enc.writeRawBytes(identityBytes);

      // token: string
      enc.writeString('gzip_test_token');

      // connectionId: 16 raw bytes
      final connIdBytes = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        connIdBytes[i] = i + 50;
      }
      enc.writeRawBytes(connIdBytes);

      final payload = enc.toBytes();

      // Gzip-compress the payload
      final compressed = gzip.encode(payload);

      // Prepend compression tag 2 (gzip)
      final raw = Uint8List(1 + compressed.length);
      raw[0] = 2;
      raw.setRange(1, raw.length, compressed);

      final msg = ServerMessage.decode(raw);
      expect(msg, isA<IdentityToken>());

      final token = msg as IdentityToken;
      expect(token.token, 'gzip_test_token');
      for (var i = 0; i < 32; i++) {
        expect(token.identity.data[i], i);
      }
      for (var i = 0; i < 16; i++) {
        expect(token.connectionId.data[i], i + 50);
      }
    });

    test('unknown compression tag throws BsatnDecodeException', () {
      final raw = Uint8List.fromList([99, 0]); // unknown tag
      expect(
        () => ServerMessage.decode(raw),
        throwsA(isA<BsatnDecodeException>()),
      );
    });

    test('unknown server message tag throws BsatnDecodeException', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(255); // unknown tag
      final raw = _withNoCompression(enc.toBytes());
      expect(
        () => ServerMessage.decode(raw),
        throwsA(isA<BsatnDecodeException>()),
      );
    });

    test('truncated payload throws BsatnDecodeException', () {
      // Build a valid IdentityToken payload and truncate it
      final enc = BsatnEncoder();
      enc.writeSumTag(3);
      enc.writeRawBytes(Uint8List(10)); // only 10 of 32 needed bytes

      final raw = _withNoCompression(enc.toBytes());
      expect(
        () => ServerMessage.decode(raw),
        throwsA(isA<BsatnDecodeException>()),
      );
    });
  });

  // =========================================================================
  // SUPPORTING TYPES
  // =========================================================================
  group('DatabaseUpdate serialization round-trip', () {
    test('empty DatabaseUpdate', () {
      final original = _emptyDatabaseUpdate();
      final bytes = _encodeDatabaseUpdate(original);
      final dec = BsatnDecoder(bytes);
      final decoded = DatabaseUpdate.readBsatn(dec);
      expect(decoded.tables, isEmpty);
    });

    test('DatabaseUpdate with one table', () {
      final tableUpdate = TableUpdate(
        tableId: 5,
        tableName: 'test',
        numRows: 3,
        updates: [],
      );
      final original = DatabaseUpdate(tables: [tableUpdate]);
      final bytes = _encodeDatabaseUpdate(original);
      final dec = BsatnDecoder(bytes);
      final decoded = DatabaseUpdate.readBsatn(dec);
      expect(decoded.tables.length, 1);
      expect(decoded.tables[0].tableId, 5);
      expect(decoded.tables[0].tableName, 'test');
      expect(decoded.tables[0].numRows, 3);
    });
  });

  group('TableUpdate with CompressableQueryUpdate', () {
    test('UncompressedQueryUpdate round-trip', () {
      final rowList = _emptyRowList();
      final queryUpdate = QueryUpdate(deletes: rowList, inserts: rowList);
      final table = TableUpdate(
        tableId: 1,
        tableName: 't',
        numRows: 0,
        updates: [UncompressedQueryUpdate(queryUpdate)],
      );
      final bytes = _encodeTableUpdate(table);
      final dec = BsatnDecoder(bytes);
      final decoded = TableUpdate.readBsatn(dec);
      expect(decoded.updates.length, 1);
      expect(decoded.updates[0], isA<UncompressedQueryUpdate>());
    });

    test('resolveUpdates on UncompressedQueryUpdate', () {
      final rowList = _emptyRowList();
      final queryUpdate = QueryUpdate(deletes: rowList, inserts: rowList);
      final table = TableUpdate(
        tableId: 1,
        tableName: 't',
        numRows: 0,
        updates: [UncompressedQueryUpdate(queryUpdate)],
      );
      final resolved = table.resolveUpdates();
      expect(resolved.length, 1);
    });
  });

  group('SubscribeRows serialization round-trip', () {
    test('encodes and decodes correctly', () {
      final tableUpdate = TableUpdate(
        tableId: 42,
        tableName: 'items',
        numRows: 0,
        updates: [],
      );
      final rows = SubscribeRows(
        tableId: 42,
        tableName: 'items',
        tableRows: tableUpdate,
      );
      final bytes = _encodeSubscribeRows(rows);
      final dec = BsatnDecoder(bytes);
      final decoded = SubscribeRows.readBsatn(dec);
      expect(decoded.tableId, 42);
      expect(decoded.tableName, 'items');
      expect(decoded.tableRows.tableId, 42);
    });
  });

  group('BsatnRowList extraction', () {
    test('FixedSizeHint with empty rowsData returns empty list', () {
      final rl = BsatnRowList(
        sizeHint: const FixedSizeHint(4),
        rowsData: Uint8List(0),
      );
      expect(rl.extractRows(), isEmpty);
    });

    test('FixedSizeHint with size 0 returns empty list', () {
      final rl = BsatnRowList(
        sizeHint: const FixedSizeHint(0),
        rowsData: Uint8List.fromList([1, 2, 3]),
      );
      expect(rl.extractRows(), isEmpty);
    });

    test('FixedSizeHint splits rowsData into fixed-size chunks', () {
      final rl = BsatnRowList(
        sizeHint: const FixedSizeHint(2),
        rowsData: Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]),
      );
      final rows = rl.extractRows();
      expect(rows.length, 2);
      expect(rows[0], Uint8List.fromList([0xAA, 0xBB]));
      expect(rows[1], Uint8List.fromList([0xCC, 0xDD]));
    });

    test('RowOffsetsHint extracts rows by offset', () {
      final data = Uint8List.fromList([10, 20, 30, 40, 50]);
      final rl = BsatnRowList(
        sizeHint: RowOffsetsHint([0, 2]), // rows at [0,2) and [2,5)
        rowsData: data,
      );
      final rows = rl.extractRows();
      expect(rows.length, 2);
      expect(rows[0], Uint8List.fromList([10, 20]));
      expect(rows[1], Uint8List.fromList([30, 40, 50]));
    });
  });

  group('TimeDuration', () {
    test('zero duration', () {
      final d = TimeDuration.zero();
      expect(d.nanoseconds, 0);
      expect(d.microseconds, 0);
    });

    test('fromDuration round-trip', () {
      final duration = const Duration(milliseconds: 5);
      final td = TimeDuration.fromDuration(duration);
      expect(td.nanoseconds, 5000000);
      expect(td.toDuration(), const Duration(milliseconds: 5));
    });

    test('writeBsatn and readBsatn round-trip', () {
      final original = const TimeDuration(123456789);
      final enc = BsatnEncoder();
      original.writeBsatn(enc);
      final dec = BsatnDecoder(enc.toBytes());
      final decoded = TimeDuration.readBsatn(dec);
      expect(decoded.nanoseconds, original.nanoseconds);
    });
  });

  group('ReducerCallInfo serialization', () {
    test('round-trip', () {
      final args = Uint8List.fromList([1, 2, 3]);
      final info = ReducerCallInfo(
        reducerName: 'my_reducer',
        reducerId: 7,
        args: args,
        requestId: 99,
      );
      final enc = BsatnEncoder();
      info.writeBsatn(enc);
      final dec = BsatnDecoder(enc.toBytes());
      final decoded = ReducerCallInfo.readBsatn(dec);
      expect(decoded.reducerName, 'my_reducer');
      expect(decoded.reducerId, 7);
      expect(decoded.args, args);
      expect(decoded.requestId, 99);
    });
  });

  group('OneOffTable', () {
    test('readBsatn and writeBsatn round-trip', () {
      final rowList = _emptyRowList();
      final table = OneOffTable(tableName: 'my_results', rowList: rowList);
      final enc = BsatnEncoder();
      table.writeBsatn(enc);
      final dec = BsatnDecoder(enc.toBytes());
      final decoded = OneOffTable.readBsatn(dec);
      expect(decoded.tableName, 'my_results');
      expect(decoded.rows, isEmpty);
    });
  });

  group('UpdateStatus variants', () {
    test('Committed decodes with empty DatabaseUpdate', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(0);
      _emptyDatabaseUpdate().writeBsatn(enc);
      final dec = BsatnDecoder(enc.toBytes());
      final status = UpdateStatus.readBsatn(dec);
      expect(status, isA<Committed>());
      expect((status as Committed).databaseUpdate.tables, isEmpty);
    });

    test('Failed decodes error message', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(1);
      enc.writeString('something went wrong');
      final dec = BsatnDecoder(enc.toBytes());
      final status = UpdateStatus.readBsatn(dec);
      expect(status, isA<Failed>());
      expect((status as Failed).errorMessage, 'something went wrong');
    });

    test('OutOfEnergy decodes', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(2);
      final dec = BsatnDecoder(enc.toBytes());
      final status = UpdateStatus.readBsatn(dec);
      expect(status, isA<OutOfEnergy>());
    });

    test('unknown tag throws BsatnDecodeException', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(99);
      final dec = BsatnDecoder(enc.toBytes());
      expect(
        () => UpdateStatus.readBsatn(dec),
        throwsA(isA<BsatnDecodeException>()),
      );
    });
  });

  group('ProcedureStatus variants', () {
    test('ProcedureCommitted decodes', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(0);
      _emptyDatabaseUpdate().writeBsatn(enc);
      final dec = BsatnDecoder(enc.toBytes());
      final status = ProcedureStatus.readBsatn(dec);
      expect(status, isA<ProcedureCommitted>());
    });

    test('ProcedureFailed decodes error message', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(1);
      enc.writeString('proc error');
      final dec = BsatnDecoder(enc.toBytes());
      final status = ProcedureStatus.readBsatn(dec);
      expect(status, isA<ProcedureFailed>());
      expect((status as ProcedureFailed).errorMessage, 'proc error');
    });

    test('unknown tag throws BsatnDecodeException', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(42);
      final dec = BsatnDecoder(enc.toBytes());
      expect(
        () => ProcedureStatus.readBsatn(dec),
        throwsA(isA<BsatnDecodeException>()),
      );
    });
  });
}

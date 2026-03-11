import 'dart:io';
import 'dart:typed_data';

import 'package:spacetimedb_sdk/spacetimedb.dart';
import 'package:test/test.dart';

/// Helper: encode an object with [writeBsatn], return the bytes.
Uint8List encode(void Function(BsatnEncoder) write) {
  final enc = BsatnEncoder();
  write(enc);
  return enc.toBytes();
}

/// Helper: decode bytes produced by [encode].
T decode<T>(Uint8List bytes, T Function(BsatnDecoder) read) {
  return read(BsatnDecoder(bytes));
}

// ---------------------------------------------------------------------------
// Minimal QueryUpdate builders used throughout the tests.
// ---------------------------------------------------------------------------

/// Builds a simple [BsatnRowList] with [FixedSizeHint] and empty data.
BsatnRowList emptyFixedRowList({int size = 4}) =>
    BsatnRowList(sizeHint: FixedSizeHint(size), rowsData: Uint8List(0));

/// Builds a [BsatnRowList] with [FixedSizeHint] where rowsData contains
/// [count] rows of [rowSize] bytes each.
BsatnRowList fixedRowList(int rowSize, List<List<int>> rows) {
  final data = Uint8List.fromList(rows.expand((r) => r).toList());
  return BsatnRowList(sizeHint: FixedSizeHint(rowSize), rowsData: data);
}

/// Builds an empty [QueryUpdate].
QueryUpdate emptyQueryUpdate() => QueryUpdate(
      deletes: emptyFixedRowList(),
      inserts: emptyFixedRowList(),
    );

/// Builds an empty [TableUpdate].
TableUpdate emptyTableUpdate({int tableId = 1, String tableName = 'test'}) =>
    TableUpdate(
      tableId: tableId,
      tableName: tableName,
      numRows: 0,
      updates: [],
    );

/// Builds an empty [DatabaseUpdate].
DatabaseUpdate emptyDatabaseUpdate() =>
    DatabaseUpdate(tables: [emptyTableUpdate()]);

void main() {
  // -------------------------------------------------------------------------
  // TimeDuration
  // -------------------------------------------------------------------------
  group('TimeDuration', () {
    test('construction stores nanoseconds', () {
      const d = TimeDuration(1000);
      expect(d.nanoseconds, 1000);
    });

    test('zero factory', () {
      final d = TimeDuration.zero();
      expect(d.nanoseconds, 0);
    });

    test('fromDuration converts microseconds to nanoseconds', () {
      final d = TimeDuration.fromDuration(const Duration(microseconds: 5));
      expect(d.nanoseconds, 5000);
    });

    test('fromDuration with seconds', () {
      final d = TimeDuration.fromDuration(const Duration(seconds: 1));
      expect(d.nanoseconds, 1000000 * 1000); // 1e9
    });

    test('toDuration truncates to microseconds', () {
      // 1500 ns → 1 µs (truncated)
      const d = TimeDuration(1500);
      expect(d.toDuration(), const Duration(microseconds: 1));
    });

    test('toDuration round-trip for exact microsecond values', () {
      const original = Duration(microseconds: 123456);
      final d = TimeDuration.fromDuration(original);
      expect(d.toDuration(), original);
    });

    test('microseconds getter', () {
      const d = TimeDuration(7000);
      expect(d.microseconds, 7);
    });

    test('microseconds getter truncates', () {
      const d = TimeDuration(999);
      expect(d.microseconds, 0);
    });

    test('writeBsatn / readBsatn round-trip (positive)', () {
      const original = TimeDuration(9876543210);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, TimeDuration.readBsatn);
      expect(decoded.nanoseconds, original.nanoseconds);
    });

    test('writeBsatn / readBsatn round-trip (zero)', () {
      final original = TimeDuration.zero();
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, TimeDuration.readBsatn);
      expect(decoded.nanoseconds, 0);
    });

    test('writeBsatn / readBsatn round-trip (negative nanoseconds)', () {
      const original = TimeDuration(-1);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, TimeDuration.readBsatn);
      expect(decoded.nanoseconds, -1);
    });

    test('toString', () {
      expect(const TimeDuration(42).toString(), 'TimeDuration(42ns)');
    });
  });

  // -------------------------------------------------------------------------
  // EnergyQuanta
  // -------------------------------------------------------------------------
  group('EnergyQuanta', () {
    test('construction stores quanta', () {
      final q = EnergyQuanta(U128.fromInt(100));
      expect(q.quanta, U128.fromInt(100));
    });

    test('zero factory', () {
      final q = EnergyQuanta.zero();
      expect(q.quanta, U128.zero());
    });

    test('writeBsatn / readBsatn round-trip (zero)', () {
      final original = EnergyQuanta.zero();
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, EnergyQuanta.readBsatn);
      expect(decoded.quanta, original.quanta);
    });

    test('writeBsatn / readBsatn round-trip (large value)', () {
      final original = EnergyQuanta(
        U128(BigInt.parse('DEADBEEFCAFEBABE0011223344556677', radix: 16)),
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, EnergyQuanta.readBsatn);
      expect(decoded.quanta, original.quanta);
    });

    test('toString', () {
      final q = EnergyQuanta(U128.fromInt(0));
      expect(q.toString(), startsWith('EnergyQuanta('));
    });
  });

  // -------------------------------------------------------------------------
  // ReducerCallInfo
  // -------------------------------------------------------------------------
  group('ReducerCallInfo', () {
    test('construction stores all fields', () {
      final args = Uint8List.fromList([1, 2, 3]);
      final info = ReducerCallInfo(
        reducerName: 'my_reducer',
        reducerId: 7,
        args: args,
        requestId: 99,
      );
      expect(info.reducerName, 'my_reducer');
      expect(info.reducerId, 7);
      expect(info.requestId, 99);
    });

    test('writeBsatn / readBsatn round-trip', () {
      final args = Uint8List.fromList([10, 20, 30]);
      final original = ReducerCallInfo(
        reducerName: 'do_thing',
        reducerId: 42,
        args: args,
        requestId: 1001,
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, ReducerCallInfo.readBsatn);

      expect(decoded.reducerName, original.reducerName);
      expect(decoded.reducerId, original.reducerId);
      expect(decoded.args, original.args);
      expect(decoded.requestId, original.requestId);
    });

    test('writeBsatn / readBsatn with empty args', () {
      final original = ReducerCallInfo(
        reducerName: '',
        reducerId: 0,
        args: Uint8List(0),
        requestId: 0,
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, ReducerCallInfo.readBsatn);
      expect(decoded.reducerName, '');
      expect(decoded.args, Uint8List(0));
    });

    test('toString', () {
      final info = ReducerCallInfo(
        reducerName: 'foo',
        reducerId: 1,
        args: Uint8List(0),
        requestId: 2,
      );
      expect(info.toString(), contains('foo'));
      expect(info.toString(), contains('1'));
      expect(info.toString(), contains('2'));
    });
  });

  // -------------------------------------------------------------------------
  // RowSizeHint: FixedSizeHint
  // -------------------------------------------------------------------------
  group('FixedSizeHint', () {
    test('stores size', () {
      const hint = FixedSizeHint(16);
      expect(hint.size, 16);
    });

    test('writeBsatn / readBsatn round-trip', () {
      const original = FixedSizeHint(8);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, RowSizeHint.readBsatn);
      expect(decoded, isA<FixedSizeHint>());
      expect((decoded as FixedSizeHint).size, 8);
    });

    test('toString', () {
      expect(const FixedSizeHint(4).toString(), 'FixedSizeHint(4)');
    });
  });

  // -------------------------------------------------------------------------
  // RowSizeHint: RowOffsetsHint
  // -------------------------------------------------------------------------
  group('RowOffsetsHint', () {
    test('stores offsets', () {
      final hint = RowOffsetsHint([0, 4, 8]);
      expect(hint.offsets, [0, 4, 8]);
    });

    test('writeBsatn / readBsatn round-trip (non-empty)', () {
      final original = RowOffsetsHint([0, 10, 25]);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, RowSizeHint.readBsatn);
      expect(decoded, isA<RowOffsetsHint>());
      expect((decoded as RowOffsetsHint).offsets, [0, 10, 25]);
    });

    test('writeBsatn / readBsatn round-trip (empty offsets)', () {
      final original = RowOffsetsHint([]);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, RowSizeHint.readBsatn);
      expect(decoded, isA<RowOffsetsHint>());
      expect((decoded as RowOffsetsHint).offsets, isEmpty);
    });

    test('toString', () {
      expect(RowOffsetsHint([0, 1, 2]).toString(), 'RowOffsetsHint(3 rows)');
    });

    test('unknown RowSizeHint tag throws', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(99); // unknown tag
      final bytes = enc.toBytes();
      expect(
        () => decode(bytes, RowSizeHint.readBsatn),
        throwsA(isA<BsatnDecodeException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // BsatnRowList
  // -------------------------------------------------------------------------
  group('BsatnRowList', () {
    test('extractRows returns empty list when rowsData is empty', () {
      final list = BsatnRowList(
        sizeHint: FixedSizeHint(4),
        rowsData: Uint8List(0),
      );
      expect(list.extractRows(), isEmpty);
    });

    test('extractRows with FixedSizeHint splits correctly', () {
      // Three 4-byte rows: [1,0,0,0], [2,0,0,0], [3,0,0,0]
      final data = Uint8List.fromList([1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]);
      final list = BsatnRowList(sizeHint: FixedSizeHint(4), rowsData: data);
      final rows = list.extractRows();
      expect(rows.length, 3);
      expect(rows[0], Uint8List.fromList([1, 0, 0, 0]));
      expect(rows[1], Uint8List.fromList([2, 0, 0, 0]));
      expect(rows[2], Uint8List.fromList([3, 0, 0, 0]));
    });

    test('extractRows with FixedSizeHint size 0 returns empty', () {
      final list = BsatnRowList(
        sizeHint: const FixedSizeHint(0),
        rowsData: Uint8List.fromList([1, 2, 3]),
      );
      expect(list.extractRows(), isEmpty);
    });

    test('extractRows with RowOffsetsHint splits correctly', () {
      // Two rows: bytes 0-2 and 3-5
      final data = Uint8List.fromList([10, 11, 12, 20, 21, 22]);
      final list = BsatnRowList(
        sizeHint: RowOffsetsHint([0, 3]),
        rowsData: data,
      );
      final rows = list.extractRows();
      expect(rows.length, 2);
      expect(rows[0], Uint8List.fromList([10, 11, 12]));
      expect(rows[1], Uint8List.fromList([20, 21, 22]));
    });

    test('extractRows with RowOffsetsHint single row uses full buffer', () {
      final data = Uint8List.fromList([5, 6, 7, 8]);
      final list = BsatnRowList(
        sizeHint: RowOffsetsHint([0]),
        rowsData: data,
      );
      final rows = list.extractRows();
      expect(rows.length, 1);
      expect(rows[0], Uint8List.fromList([5, 6, 7, 8]));
    });

    test('extractRows with empty RowOffsetsHint returns empty', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final list = BsatnRowList(
        sizeHint: RowOffsetsHint([]),
        rowsData: data,
      );
      expect(list.extractRows(), isEmpty);
    });

    test('writeBsatn / readBsatn round-trip with FixedSizeHint', () {
      final original = BsatnRowList(
        sizeHint: const FixedSizeHint(2),
        rowsData: Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]),
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, BsatnRowList.readBsatn);
      expect(decoded.sizeHint, isA<FixedSizeHint>());
      expect((decoded.sizeHint as FixedSizeHint).size, 2);
      expect(decoded.rowsData, original.rowsData);
    });

    test('writeBsatn / readBsatn round-trip with RowOffsetsHint', () {
      final original = BsatnRowList(
        sizeHint: RowOffsetsHint([0, 3]),
        rowsData: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, BsatnRowList.readBsatn);
      expect(decoded.sizeHint, isA<RowOffsetsHint>());
      expect((decoded.sizeHint as RowOffsetsHint).offsets, [0, 3]);
      expect(decoded.rowsData, original.rowsData);
    });

    test('toString', () {
      final list = BsatnRowList(
        sizeHint: const FixedSizeHint(4),
        rowsData: Uint8List(8),
      );
      expect(list.toString(), contains('8 bytes'));
    });
  });

  // -------------------------------------------------------------------------
  // QueryUpdate
  // -------------------------------------------------------------------------
  group('QueryUpdate', () {
    test('construction stores deletes and inserts', () {
      final deletes = emptyFixedRowList();
      final inserts = emptyFixedRowList(size: 8);
      final qu = QueryUpdate(deletes: deletes, inserts: inserts);
      expect(qu.deletes, same(deletes));
      expect(qu.inserts, same(inserts));
    });

    test('writeBsatn / readBsatn round-trip (empty)', () {
      final original = emptyQueryUpdate();
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, QueryUpdate.readBsatn);
      expect(decoded.deletes.rowsData, original.deletes.rowsData);
      expect(decoded.inserts.rowsData, original.inserts.rowsData);
    });

    test('writeBsatn / readBsatn round-trip with data', () {
      final original = QueryUpdate(
        deletes: fixedRowList(4, [
          [1, 0, 0, 0],
        ]),
        inserts: fixedRowList(4, [
          [2, 0, 0, 0],
          [3, 0, 0, 0],
        ]),
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, QueryUpdate.readBsatn);

      final deletedRows = decoded.deletes.extractRows();
      expect(deletedRows.length, 1);
      expect(deletedRows[0], Uint8List.fromList([1, 0, 0, 0]));

      final insertedRows = decoded.inserts.extractRows();
      expect(insertedRows.length, 2);
      expect(insertedRows[0], Uint8List.fromList([2, 0, 0, 0]));
      expect(insertedRows[1], Uint8List.fromList([3, 0, 0, 0]));
    });

    test('toString', () {
      final qu = emptyQueryUpdate();
      expect(qu.toString(), contains('QueryUpdate'));
    });
  });

  // -------------------------------------------------------------------------
  // CompressableQueryUpdate
  // -------------------------------------------------------------------------
  group('CompressableQueryUpdate', () {
    // --- Uncompressed (tag 0) ---
    test('decode uncompressed (tag 0) returns UncompressedQueryUpdate', () {
      final qu = emptyQueryUpdate();
      final enc = BsatnEncoder();
      enc.writeSumTag(0);
      qu.writeBsatn(enc);
      final bytes = enc.toBytes();

      final decoded = decode(bytes, CompressableQueryUpdate.readBsatn);
      expect(decoded, isA<UncompressedQueryUpdate>());
    });

    test('UncompressedQueryUpdate resolve returns the wrapped update', () {
      final qu = emptyQueryUpdate();
      final cqu = UncompressedQueryUpdate(qu);
      expect(cqu.resolve(), same(qu));
    });

    // --- Brotli (tag 1) throws on resolve ---
    test('decode Brotli (tag 1) returns BrotliQueryUpdate', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(1);
      enc.writeBytes(Uint8List.fromList([0x01, 0x02])); // fake compressed bytes
      final bytes = enc.toBytes();

      final decoded = decode(bytes, CompressableQueryUpdate.readBsatn);
      expect(decoded, isA<BrotliQueryUpdate>());
    });

    test('BrotliQueryUpdate resolve throws UnsupportedError', () {
      final cqu = BrotliQueryUpdate(Uint8List.fromList([0x00]));
      expect(() => cqu.resolve(), throwsA(isA<UnsupportedError>()));
    });

    // --- Gzip (tag 2) decompresses correctly ---
    test('decode Gzip (tag 2) returns GzipQueryUpdate', () {
      // Build a real QueryUpdate, encode it, then gzip it.
      final qu = emptyQueryUpdate();
      final rawBytes = encode((e) => qu.writeBsatn(e));
      final compressed = Uint8List.fromList(gzip.encode(rawBytes));

      final enc = BsatnEncoder();
      enc.writeSumTag(2);
      enc.writeBytes(compressed);
      final bytes = enc.toBytes();

      final decoded = decode(bytes, CompressableQueryUpdate.readBsatn);
      expect(decoded, isA<GzipQueryUpdate>());
    });

    test('GzipQueryUpdate resolve decompresses and returns QueryUpdate', () {
      final qu = emptyQueryUpdate();
      final rawBytes = encode((e) => qu.writeBsatn(e));
      final compressed = Uint8List.fromList(gzip.encode(rawBytes));

      final gzipUpdate = GzipQueryUpdate(compressed);
      final resolved = gzipUpdate.resolve();
      // Verify it round-tripped correctly.
      expect(
        resolved.deletes.rowsData,
        Uint8List.fromList(qu.deletes.rowsData),
      );
      expect(
        resolved.inserts.rowsData,
        Uint8List.fromList(qu.inserts.rowsData),
      );
    });

    test('unknown CompressableQueryUpdate tag throws BsatnDecodeException', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(99);
      final bytes = enc.toBytes();
      expect(
        () => decode(bytes, CompressableQueryUpdate.readBsatn),
        throwsA(isA<BsatnDecodeException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // TableUpdate
  // -------------------------------------------------------------------------
  group('TableUpdate', () {
    test('construction stores all fields', () {
      final tu = emptyTableUpdate(tableId: 5, tableName: 'users');
      expect(tu.tableId, 5);
      expect(tu.tableName, 'users');
      expect(tu.numRows, 0);
      expect(tu.updates, isEmpty);
    });

    test('writeBsatn / readBsatn round-trip (empty updates)', () {
      final original = emptyTableUpdate(tableId: 3, tableName: 'orders');
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, TableUpdate.readBsatn);
      expect(decoded.tableId, 3);
      expect(decoded.tableName, 'orders');
      expect(decoded.numRows, 0);
      expect(decoded.updates, isEmpty);
    });

    test('writeBsatn / readBsatn round-trip with multiple updates', () {
      final qu1 = emptyQueryUpdate();
      final qu2 = emptyQueryUpdate();
      final original = TableUpdate(
        tableId: 10,
        tableName: 'items',
        numRows: 2,
        updates: [
          UncompressedQueryUpdate(qu1),
          UncompressedQueryUpdate(qu2),
        ],
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, TableUpdate.readBsatn);
      expect(decoded.tableId, 10);
      expect(decoded.tableName, 'items');
      expect(decoded.numRows, 2);
      expect(decoded.updates.length, 2);
      expect(decoded.updates[0], isA<UncompressedQueryUpdate>());
      expect(decoded.updates[1], isA<UncompressedQueryUpdate>());
    });

    test('writeBsatn / readBsatn preserves Brotli update bytes', () {
      final fakeCompressed = Uint8List.fromList([0xAA, 0xBB]);
      final original = TableUpdate(
        tableId: 1,
        tableName: 't',
        numRows: 0,
        updates: [BrotliQueryUpdate(fakeCompressed)],
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, TableUpdate.readBsatn);
      expect(decoded.updates[0], isA<BrotliQueryUpdate>());
      expect(
        (decoded.updates[0] as BrotliQueryUpdate).compressedData,
        fakeCompressed,
      );
    });

    test('writeBsatn / readBsatn preserves Gzip update bytes', () {
      final qu = emptyQueryUpdate();
      final rawBytes = encode((e) => qu.writeBsatn(e));
      final compressed = Uint8List.fromList(gzip.encode(rawBytes));

      final original = TableUpdate(
        tableId: 1,
        tableName: 't',
        numRows: 0,
        updates: [GzipQueryUpdate(compressed)],
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, TableUpdate.readBsatn);
      expect(decoded.updates[0], isA<GzipQueryUpdate>());
      expect(
        (decoded.updates[0] as GzipQueryUpdate).compressedData,
        compressed,
      );
    });

    test('resolveUpdates resolves all uncompressed updates', () {
      final qu1 = emptyQueryUpdate();
      final qu2 = emptyQueryUpdate();
      final tu = TableUpdate(
        tableId: 1,
        tableName: 't',
        numRows: 0,
        updates: [UncompressedQueryUpdate(qu1), UncompressedQueryUpdate(qu2)],
      );
      final resolved = tu.resolveUpdates();
      expect(resolved.length, 2);
    });

    test('toString', () {
      final tu = emptyTableUpdate(tableId: 7, tableName: 'foo');
      expect(tu.toString(), contains('foo'));
      expect(tu.toString(), contains('7'));
    });
  });

  // -------------------------------------------------------------------------
  // DatabaseUpdate
  // -------------------------------------------------------------------------
  group('DatabaseUpdate', () {
    test('construction stores tables', () {
      final du = DatabaseUpdate(tables: [emptyTableUpdate()]);
      expect(du.tables.length, 1);
    });

    test('writeBsatn / readBsatn round-trip (empty tables)', () {
      final original = DatabaseUpdate(tables: []);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, DatabaseUpdate.readBsatn);
      expect(decoded.tables, isEmpty);
    });

    test('writeBsatn / readBsatn round-trip with multiple tables', () {
      final original = DatabaseUpdate(tables: [
        emptyTableUpdate(tableId: 1, tableName: 'a'),
        emptyTableUpdate(tableId: 2, tableName: 'b'),
      ]);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, DatabaseUpdate.readBsatn);
      expect(decoded.tables.length, 2);
      expect(decoded.tables[0].tableId, 1);
      expect(decoded.tables[0].tableName, 'a');
      expect(decoded.tables[1].tableId, 2);
      expect(decoded.tables[1].tableName, 'b');
    });

    test('toString', () {
      final du = DatabaseUpdate(tables: [emptyTableUpdate(), emptyTableUpdate()]);
      expect(du.toString(), contains('2'));
    });
  });

  // -------------------------------------------------------------------------
  // UpdateStatus
  // -------------------------------------------------------------------------
  group('UpdateStatus', () {
    test('decode Committed (tag 0)', () {
      final dbUpdate = emptyDatabaseUpdate();
      final enc = BsatnEncoder();
      enc.writeSumTag(0);
      dbUpdate.writeBsatn(enc);
      final bytes = enc.toBytes();

      final decoded = decode(bytes, UpdateStatus.readBsatn);
      expect(decoded, isA<Committed>());
      expect((decoded as Committed).databaseUpdate.tables.length, 1);
    });

    test('Committed toString', () {
      final c = Committed(emptyDatabaseUpdate());
      expect(c.toString(), startsWith('Committed('));
    });

    test('decode Failed (tag 1)', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(1);
      enc.writeString('something went wrong');
      final bytes = enc.toBytes();

      final decoded = decode(bytes, UpdateStatus.readBsatn);
      expect(decoded, isA<Failed>());
      expect((decoded as Failed).errorMessage, 'something went wrong');
    });

    test('Failed toString', () {
      final f = Failed('oops');
      expect(f.toString(), contains('oops'));
    });

    test('decode OutOfEnergy (tag 2)', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(2);
      final bytes = enc.toBytes();

      final decoded = decode(bytes, UpdateStatus.readBsatn);
      expect(decoded, isA<OutOfEnergy>());
    });

    test('OutOfEnergy toString', () {
      expect(const OutOfEnergy().toString(), 'OutOfEnergy()');
    });

    test('unknown UpdateStatus tag throws BsatnDecodeException', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(5);
      final bytes = enc.toBytes();
      expect(
        () => decode(bytes, UpdateStatus.readBsatn),
        throwsA(isA<BsatnDecodeException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // SubscribeRows
  // -------------------------------------------------------------------------
  group('SubscribeRows', () {
    test('construction stores all fields', () {
      final tableRows = emptyTableUpdate(tableId: 1, tableName: 'users');
      const sr = SubscribeRows(
        tableId: 1,
        tableName: 'users',
        tableRows: TableUpdate(
          tableId: 1,
          tableName: 'users',
          numRows: 0,
          updates: [],
        ),
      );
      expect(sr.tableId, 1);
      expect(sr.tableName, 'users');
    });

    test('writeBsatn / readBsatn round-trip', () {
      final original = SubscribeRows(
        tableId: 42,
        tableName: 'products',
        tableRows: emptyTableUpdate(tableId: 42, tableName: 'products'),
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, SubscribeRows.readBsatn);
      expect(decoded.tableId, 42);
      expect(decoded.tableName, 'products');
      expect(decoded.tableRows.tableId, 42);
      expect(decoded.tableRows.tableName, 'products');
    });

    test('writeBsatn / readBsatn round-trip with updates', () {
      final qu = emptyQueryUpdate();
      final tableRows = TableUpdate(
        tableId: 5,
        tableName: 'events',
        numRows: 1,
        updates: [UncompressedQueryUpdate(qu)],
      );
      final original = SubscribeRows(
        tableId: 5,
        tableName: 'events',
        tableRows: tableRows,
      );
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, SubscribeRows.readBsatn);
      expect(decoded.tableRows.updates.length, 1);
      expect(decoded.tableRows.numRows, 1);
    });

    test('toString', () {
      final sr = SubscribeRows(
        tableId: 1,
        tableName: 'tbl',
        tableRows: emptyTableUpdate(),
      );
      expect(sr.toString(), contains('tbl'));
      expect(sr.toString(), contains('1'));
    });
  });

  // -------------------------------------------------------------------------
  // OneOffTable
  // -------------------------------------------------------------------------
  group('OneOffTable', () {
    test('construction stores tableName and rowList', () {
      final rowList = emptyFixedRowList();
      final ot = OneOffTable(tableName: 'results', rowList: rowList);
      expect(ot.tableName, 'results');
      expect(ot.rowList, same(rowList));
    });

    test('rows getter extracts rows from rowList', () {
      final data = Uint8List.fromList([1, 0, 2, 0]); // two 2-byte rows
      final rowList = BsatnRowList(
        sizeHint: const FixedSizeHint(2),
        rowsData: data,
      );
      final ot = OneOffTable(tableName: 'r', rowList: rowList);
      expect(ot.rows.length, 2);
      expect(ot.rows[0], Uint8List.fromList([1, 0]));
      expect(ot.rows[1], Uint8List.fromList([2, 0]));
    });

    test('rows getter returns empty for empty rowsData', () {
      final ot = OneOffTable(tableName: 'r', rowList: emptyFixedRowList());
      expect(ot.rows, isEmpty);
    });

    test('writeBsatn / readBsatn round-trip (empty)', () {
      final original = OneOffTable(tableName: 'empty', rowList: emptyFixedRowList());
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, OneOffTable.readBsatn);
      expect(decoded.tableName, 'empty');
      expect(decoded.rows, isEmpty);
    });

    test('writeBsatn / readBsatn round-trip with rows', () {
      final data = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
      final rowList = BsatnRowList(
        sizeHint: const FixedSizeHint(2),
        rowsData: data,
      );
      final original = OneOffTable(tableName: 'data', rowList: rowList);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, OneOffTable.readBsatn);

      expect(decoded.tableName, 'data');
      expect(decoded.rows.length, 2);
      expect(decoded.rows[0], Uint8List.fromList([0xAA, 0xBB]));
      expect(decoded.rows[1], Uint8List.fromList([0xCC, 0xDD]));
    });

    test('writeBsatn / readBsatn with RowOffsetsHint', () {
      final data = Uint8List.fromList([10, 20, 30, 40, 50]);
      final rowList = BsatnRowList(
        sizeHint: RowOffsetsHint([0, 2]),
        rowsData: data,
      );
      final original = OneOffTable(tableName: 'off', rowList: rowList);
      final bytes = encode((e) => original.writeBsatn(e));
      final decoded = decode(bytes, OneOffTable.readBsatn);

      expect(decoded.tableName, 'off');
      expect(decoded.rows.length, 2);
      expect(decoded.rows[0], Uint8List.fromList([10, 20]));
      expect(decoded.rows[1], Uint8List.fromList([30, 40, 50]));
    });

    test('toString', () {
      final ot = OneOffTable(tableName: 'foo', rowList: emptyFixedRowList());
      expect(ot.toString(), contains('foo'));
    });
  });

  // -------------------------------------------------------------------------
  // ProcedureStatus
  // -------------------------------------------------------------------------
  group('ProcedureStatus', () {
    test('decode ProcedureCommitted (tag 0)', () {
      final dbUpdate = emptyDatabaseUpdate();
      final enc = BsatnEncoder();
      enc.writeSumTag(0);
      dbUpdate.writeBsatn(enc);
      final bytes = enc.toBytes();

      final decoded = decode(bytes, ProcedureStatus.readBsatn);
      expect(decoded, isA<ProcedureCommitted>());
      expect(
        (decoded as ProcedureCommitted).databaseUpdate.tables.length,
        1,
      );
    });

    test('ProcedureCommitted toString', () {
      final pc = ProcedureCommitted(emptyDatabaseUpdate());
      expect(pc.toString(), startsWith('ProcedureCommitted('));
    });

    test('decode ProcedureFailed (tag 1)', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(1);
      enc.writeString('reducer panicked');
      final bytes = enc.toBytes();

      final decoded = decode(bytes, ProcedureStatus.readBsatn);
      expect(decoded, isA<ProcedureFailed>());
      expect((decoded as ProcedureFailed).errorMessage, 'reducer panicked');
    });

    test('ProcedureFailed toString', () {
      final pf = ProcedureFailed('boom');
      expect(pf.toString(), contains('boom'));
    });

    test('unknown ProcedureStatus tag throws BsatnDecodeException', () {
      final enc = BsatnEncoder();
      enc.writeSumTag(7);
      final bytes = enc.toBytes();
      expect(
        () => decode(bytes, ProcedureStatus.readBsatn),
        throwsA(isA<BsatnDecodeException>()),
      );
    });
  });
}

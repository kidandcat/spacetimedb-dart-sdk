import 'dart:io';
import 'dart:typed_data';

import '../bsatn/bsatn.dart';

/// Energy quanta consumed by an operation (U128, 16 LE bytes).
class EnergyQuanta {
  final U128 quanta;

  const EnergyQuanta(this.quanta);

  /// Creates zero energy quanta.
  factory EnergyQuanta.zero() => EnergyQuanta(U128.zero());

  void writeBsatn(BsatnEncoder encoder) => encoder.writeU128(quanta);

  static EnergyQuanta readBsatn(BsatnDecoder decoder) =>
      EnergyQuanta(decoder.readU128());

  @override
  String toString() => 'EnergyQuanta($quanta)';
}

/// Information about the reducer call that triggered a transaction.
class ReducerCallInfo {
  final String reducerName;
  final int reducerId;
  final Uint8List args;
  final int requestId;

  const ReducerCallInfo({
    required this.reducerName,
    required this.reducerId,
    required this.args,
    required this.requestId,
  });

  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeString(reducerName);
    encoder.writeU32(reducerId);
    encoder.writeBytes(args);
    encoder.writeU32(requestId);
  }

  static ReducerCallInfo readBsatn(BsatnDecoder decoder) {
    final reducerName = decoder.readString();
    final reducerId = decoder.readU32();
    final args = decoder.readBytes();
    final requestId = decoder.readU32();
    return ReducerCallInfo(
      reducerName: reducerName,
      reducerId: reducerId,
      args: args,
      requestId: requestId,
    );
  }

  @override
  String toString() =>
      'ReducerCallInfo(name: $reducerName, id: $reducerId, requestId: $requestId)';
}

/// Hint for how to split a contiguous byte buffer into individual rows.
sealed class RowSizeHint {
  const RowSizeHint();

  static RowSizeHint readBsatn(BsatnDecoder decoder) {
    final tag = decoder.readSumTag();
    switch (tag) {
      case 0:
        final size = decoder.readU16();
        return FixedSizeHint(size);
      case 1:
        final count = decoder.readArrayHeader();
        final offsets = <int>[];
        for (var i = 0; i < count; i++) {
          offsets.add(decoder.readU64());
        }
        return RowOffsetsHint(offsets);
      default:
        throw BsatnDecodeException('Unknown RowSizeHint tag: $tag');
    }
  }

  void writeBsatn(BsatnEncoder encoder);
}

/// All rows have the same fixed byte size.
class FixedSizeHint extends RowSizeHint {
  final int size;
  const FixedSizeHint(this.size);

  @override
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeSumTag(0);
    encoder.writeU16(size);
  }

  @override
  String toString() => 'FixedSizeHint($size)';
}

/// Each row has a byte offset into the contiguous row data buffer.
class RowOffsetsHint extends RowSizeHint {
  final List<int> offsets;
  const RowOffsetsHint(this.offsets);

  @override
  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeSumTag(1);
    encoder.writeArrayHeader(offsets.length);
    for (final offset in offsets) {
      encoder.writeU64(offset);
    }
  }

  @override
  String toString() => 'RowOffsetsHint(${offsets.length} rows)';
}

/// A contiguous byte buffer of BSATN-encoded rows, along with a hint
/// describing how to split it into individual rows.
class BsatnRowList {
  final RowSizeHint sizeHint;
  final Uint8List rowsData;

  const BsatnRowList({required this.sizeHint, required this.rowsData});

  /// Extracts individual row byte arrays from the contiguous buffer.
  List<Uint8List> extractRows() {
    if (rowsData.isEmpty) return [];

    switch (sizeHint) {
      case FixedSizeHint(size: final size):
        if (size == 0) return [];
        final count = rowsData.length ~/ size;
        return [
          for (var i = 0; i < count; i++)
            Uint8List.sublistView(rowsData, i * size, (i + 1) * size),
        ];
      case RowOffsetsHint(offsets: final offsets):
        final rows = <Uint8List>[];
        for (var i = 0; i < offsets.length; i++) {
          final start = offsets[i];
          final end =
              (i + 1 < offsets.length) ? offsets[i + 1] : rowsData.length;
          rows.add(Uint8List.sublistView(rowsData, start, end));
        }
        return rows;
    }
  }

  void writeBsatn(BsatnEncoder encoder) {
    sizeHint.writeBsatn(encoder);
    encoder.writeBytes(rowsData);
  }

  static BsatnRowList readBsatn(BsatnDecoder decoder) {
    final sizeHint = RowSizeHint.readBsatn(decoder);
    final rowsData = decoder.readBytes();
    return BsatnRowList(sizeHint: sizeHint, rowsData: rowsData);
  }

  @override
  String toString() =>
      'BsatnRowList(hint: $sizeHint, ${rowsData.length} bytes)';
}

/// The result of a query: a set of deleted rows and a set of inserted rows.
class QueryUpdate {
  final BsatnRowList deletes;
  final BsatnRowList inserts;

  const QueryUpdate({required this.deletes, required this.inserts});

  void writeBsatn(BsatnEncoder encoder) {
    deletes.writeBsatn(encoder);
    inserts.writeBsatn(encoder);
  }

  static QueryUpdate readBsatn(BsatnDecoder decoder) {
    final deletes = BsatnRowList.readBsatn(decoder);
    final inserts = BsatnRowList.readBsatn(decoder);
    return QueryUpdate(deletes: deletes, inserts: inserts);
  }

  @override
  String toString() => 'QueryUpdate(deletes: $deletes, inserts: $inserts)';
}

/// A query update that may be compressed.
///
/// Sum type with three variants:
/// - tag 0: Uncompressed [QueryUpdate]
/// - tag 1: Brotli-compressed BSATN bytes
/// - tag 2: Gzip-compressed BSATN bytes
sealed class CompressableQueryUpdate {
  const CompressableQueryUpdate();

  /// Resolves the update by decompressing if needed and returning the
  /// underlying [QueryUpdate].
  QueryUpdate resolve();

  static CompressableQueryUpdate readBsatn(BsatnDecoder decoder) {
    final tag = decoder.readSumTag();
    switch (tag) {
      case 0:
        final update = QueryUpdate.readBsatn(decoder);
        return UncompressedQueryUpdate(update);
      case 1:
        final compressed = decoder.readBytes();
        return BrotliQueryUpdate(compressed);
      case 2:
        final compressed = decoder.readBytes();
        return GzipQueryUpdate(compressed);
      default:
        throw BsatnDecodeException(
          'Unknown CompressableQueryUpdate tag: $tag',
        );
    }
  }
}

/// An uncompressed query update.
class UncompressedQueryUpdate extends CompressableQueryUpdate {
  final QueryUpdate update;
  const UncompressedQueryUpdate(this.update);

  @override
  QueryUpdate resolve() => update;
}

/// A Brotli-compressed query update.
///
/// Brotli decompression is not currently supported. Attempting to resolve
/// this variant will throw an [UnsupportedError].
class BrotliQueryUpdate extends CompressableQueryUpdate {
  final Uint8List compressedData;
  const BrotliQueryUpdate(this.compressedData);

  @override
  QueryUpdate resolve() {
    throw UnsupportedError(
      'Brotli decompression is not supported. '
      'Configure the server to use compression=none or gzip.',
    );
  }
}

/// A Gzip-compressed query update.
class GzipQueryUpdate extends CompressableQueryUpdate {
  final Uint8List compressedData;
  const GzipQueryUpdate(this.compressedData);

  @override
  QueryUpdate resolve() {
    final decompressed =
        Uint8List.fromList(gzip.decode(compressedData));
    final decoder = BsatnDecoder(decompressed);
    return QueryUpdate.readBsatn(decoder);
  }
}

/// Updates for a single table within a database update.
class TableUpdate {
  final int tableId;
  final String tableName;
  final int numRows;
  final List<CompressableQueryUpdate> updates;

  const TableUpdate({
    required this.tableId,
    required this.tableName,
    required this.numRows,
    required this.updates,
  });

  /// Returns all resolved [QueryUpdate]s by decompressing any compressed
  /// variants.
  List<QueryUpdate> resolveUpdates() =>
      updates.map((u) => u.resolve()).toList();

  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeU32(tableId);
    encoder.writeString(tableName);
    encoder.writeU64(numRows);
    encoder.writeArrayHeader(updates.length);
    for (final update in updates) {
      if (update is UncompressedQueryUpdate) {
        encoder.writeSumTag(0);
        update.update.writeBsatn(encoder);
      } else if (update is BrotliQueryUpdate) {
        encoder.writeSumTag(1);
        encoder.writeBytes(update.compressedData);
      } else if (update is GzipQueryUpdate) {
        encoder.writeSumTag(2);
        encoder.writeBytes(update.compressedData);
      }
    }
  }

  static TableUpdate readBsatn(BsatnDecoder decoder) {
    final tableId = decoder.readU32();
    final tableName = decoder.readString();
    final numRows = decoder.readU64();
    final count = decoder.readArrayHeader();
    final updates = <CompressableQueryUpdate>[];
    for (var i = 0; i < count; i++) {
      updates.add(CompressableQueryUpdate.readBsatn(decoder));
    }
    return TableUpdate(
      tableId: tableId,
      tableName: tableName,
      numRows: numRows,
      updates: updates,
    );
  }

  @override
  String toString() =>
      'TableUpdate(id: $tableId, name: $tableName, numRows: $numRows, '
      '${updates.length} updates)';
}

/// A batch of table updates representing a database state change.
class DatabaseUpdate {
  final List<TableUpdate> tables;

  const DatabaseUpdate({required this.tables});

  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeArrayHeader(tables.length);
    for (final table in tables) {
      table.writeBsatn(encoder);
    }
  }

  static DatabaseUpdate readBsatn(BsatnDecoder decoder) {
    final count = decoder.readArrayHeader();
    final tables = <TableUpdate>[];
    for (var i = 0; i < count; i++) {
      tables.add(TableUpdate.readBsatn(decoder));
    }
    return DatabaseUpdate(tables: tables);
  }

  @override
  String toString() => 'DatabaseUpdate(${tables.length} tables)';
}

/// The status of a transaction: committed, failed, or out of energy.
sealed class UpdateStatus {
  const UpdateStatus();

  static UpdateStatus readBsatn(BsatnDecoder decoder) {
    final tag = decoder.readSumTag();
    switch (tag) {
      case 0:
        final update = DatabaseUpdate.readBsatn(decoder);
        return Committed(update);
      case 1:
        final errorMessage = decoder.readString();
        return Failed(errorMessage);
      case 2:
        return const OutOfEnergy();
      default:
        throw BsatnDecodeException('Unknown UpdateStatus tag: $tag');
    }
  }
}

/// Transaction was committed successfully with the given database changes.
class Committed extends UpdateStatus {
  final DatabaseUpdate databaseUpdate;
  const Committed(this.databaseUpdate);

  @override
  String toString() => 'Committed($databaseUpdate)';
}

/// Transaction failed with the given error message.
class Failed extends UpdateStatus {
  final String errorMessage;
  const Failed(this.errorMessage);

  @override
  String toString() => 'Failed($errorMessage)';
}

/// Transaction failed because the caller ran out of energy.
class OutOfEnergy extends UpdateStatus {
  const OutOfEnergy();

  @override
  String toString() => 'OutOfEnergy()';
}

/// Rows for a specific subscription query, including table metadata.
class SubscribeRows {
  final int tableId;
  final String tableName;
  final TableUpdate tableRows;

  const SubscribeRows({
    required this.tableId,
    required this.tableName,
    required this.tableRows,
  });

  static SubscribeRows readBsatn(BsatnDecoder decoder) {
    final tableId = decoder.readU32();
    final tableName = decoder.readString();
    final tableRows = TableUpdate.readBsatn(decoder);
    return SubscribeRows(
      tableId: tableId,
      tableName: tableName,
      tableRows: tableRows,
    );
  }

  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeU32(tableId);
    encoder.writeString(tableName);
    tableRows.writeBsatn(encoder);
  }

  @override
  String toString() =>
      'SubscribeRows(tableId: $tableId, tableName: $tableName)';
}

/// A table result from a one-off query.
class OneOffTable {
  final String tableName;
  final List<Uint8List> rows;

  const OneOffTable({required this.tableName, required this.rows});

  static OneOffTable readBsatn(BsatnDecoder decoder) {
    final tableName = decoder.readString();
    final rowCount = decoder.readArrayHeader();
    final rows = <Uint8List>[];
    for (var i = 0; i < rowCount; i++) {
      rows.add(decoder.readBytes());
    }
    return OneOffTable(tableName: tableName, rows: rows);
  }

  void writeBsatn(BsatnEncoder encoder) {
    encoder.writeString(tableName);
    encoder.writeArrayHeader(rows.length);
    for (final row in rows) {
      encoder.writeBytes(row);
    }
  }

  @override
  String toString() => 'OneOffTable(name: $tableName, ${rows.length} rows)';
}

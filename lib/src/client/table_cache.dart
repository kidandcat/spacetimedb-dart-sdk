import 'dart:typed_data';

import '../bsatn/bsatn.dart';

/// Callback invoked when a row is inserted into a table.
typedef RowInsertCallback<T> = void Function(T row);

/// Callback invoked when a row is updated (old value replaced by new value).
typedef RowUpdateCallback<T> = void Function(T oldRow, T newRow);

/// Callback invoked when a row is deleted from a table.
typedef RowDeleteCallback<T> = void Function(T row);

/// Function that decodes a row of type [T] from a BSATN decoder.
typedef RowDecoder<T> = T Function(BsatnDecoder decoder);

/// Function that extracts a primary key of type [K] from a row of type [T].
typedef PkExtractor<T, K> = K Function(T row);

/// A typed, in-memory cache for a single SpacetimeDB table.
///
/// Stores rows indexed by primary key and provides insert/update/delete
/// callbacks so UI or game logic can react to remote changes.
///
/// When no [PkExtractor] is provided, rows are keyed by their [Object.hashCode].
/// This fallback only works correctly when the row type has a stable hashCode
/// implementation that depends on its field values.
class TableCache<T> {
  /// The SpacetimeDB table name this cache is bound to.
  final String tableName;

  final RowDecoder<T> _decoder;
  final PkExtractor<T, dynamic>? _pkExtractor;

  /// Rows indexed by primary key (or by row hashCode if no PK extractor).
  final Map<dynamic, T> _rows = {};

  final List<RowInsertCallback<T>> _insertCallbacks = [];
  final List<RowUpdateCallback<T>> _updateCallbacks = [];
  final List<RowDeleteCallback<T>> _deleteCallbacks = [];

  /// Creates a table cache for the given [tableName].
  ///
  /// [decoder] converts raw BSATN bytes into a row of type [T].
  /// [pkExtractor] extracts the primary key used for indexing; if omitted,
  /// [Object.hashCode] is used as a fallback key.
  TableCache({
    required this.tableName,
    required RowDecoder<T> decoder,
    PkExtractor<T, dynamic>? pkExtractor,
  })  : _decoder = decoder,
        _pkExtractor = pkExtractor;

  /// All currently cached rows.
  Iterable<T> get rows => _rows.values;

  /// The number of cached rows.
  int get count => _rows.length;

  /// Whether the cache contains any rows.
  bool get isEmpty => _rows.isEmpty;

  /// Whether the cache contains at least one row.
  bool get isNotEmpty => _rows.isNotEmpty;

  /// Finds a row by its primary key, or returns `null` if not present.
  T? findByPk(dynamic pk) => _rows[pk];

  /// Returns all rows matching [test].
  Iterable<T> where(bool Function(T) test) => _rows.values.where(test);

  /// Returns the first row matching [test], or `null` if none match.
  T? firstWhereOrNull(bool Function(T) test) {
    for (final row in _rows.values) {
      if (test(row)) return row;
    }
    return null;
  }

  /// Registers a callback invoked whenever a row is inserted.
  void onInsert(RowInsertCallback<T> callback) =>
      _insertCallbacks.add(callback);

  /// Registers a callback invoked whenever a row is updated.
  void onUpdate(RowUpdateCallback<T> callback) =>
      _updateCallbacks.add(callback);

  /// Registers a callback invoked whenever a row is deleted.
  void onDelete(RowDeleteCallback<T> callback) =>
      _deleteCallbacks.add(callback);

  /// Removes a previously registered insert callback.
  void removeOnInsert(RowInsertCallback<T> callback) =>
      _insertCallbacks.remove(callback);

  /// Removes a previously registered update callback.
  void removeOnUpdate(RowUpdateCallback<T> callback) =>
      _updateCallbacks.remove(callback);

  /// Removes a previously registered delete callback.
  void removeOnDelete(RowDeleteCallback<T> callback) =>
      _deleteCallbacks.remove(callback);

  /// Decodes a single row from raw BSATN [rowBytes].
  T decodeRow(Uint8List rowBytes) {
    final decoder = BsatnDecoder(rowBytes);
    return _decoder(decoder);
  }

  /// Decodes raw BSATN row byte arrays and applies them as changes.
  ///
  /// This handles the type-safe decoding internally, avoiding issues with
  /// generic type erasure when called through a `TableCache<dynamic>` reference.
  void applyRawChanges(List<Uint8List> insertBytes, List<Uint8List> deleteBytes) {
    final inserts = insertBytes.map(decodeRow).toList();
    final deletes = deleteBytes.map(decodeRow).toList();
    applyChanges(inserts, deletes);
  }

  /// Returns the cache key for [row], using the PK extractor when available.
  dynamic _getKey(T row) {
    if (_pkExtractor != null) return _pkExtractor!(row);
    return row.hashCode;
  }

  /// Applies a set of [inserts] and [deletes] from a transaction update.
  ///
  /// Rows that appear in both [deletes] and [inserts] with the same primary key
  /// are treated as updates. Pure inserts and pure deletes fire the appropriate
  /// callbacks.
  void applyChanges(List<T> inserts, List<T> deletes) {
    // Index deletions by PK so we can detect updates.
    final deletedByPk = <dynamic, T>{};
    for (final row in deletes) {
      deletedByPk[_getKey(row)] = row;
    }

    // Track which deleted PKs were matched by an insert (i.e. updates).
    final matchedPks = <dynamic>{};

    for (final row in inserts) {
      final pk = _getKey(row);
      matchedPks.add(pk);
      final oldRow = deletedByPk[pk];
      if (oldRow != null) {
        // UPDATE: a delete + insert with the same PK.
        _rows[pk] = row;
        for (final cb in _updateCallbacks) {
          cb(oldRow, row);
        }
      } else {
        // Pure INSERT.
        _rows[pk] = row;
        for (final cb in _insertCallbacks) {
          cb(row);
        }
      }
    }

    // Process remaining deletes that were not matched by an insert.
    for (final entry in deletedByPk.entries) {
      if (!matchedPks.contains(entry.key)) {
        _rows.remove(entry.key);
        for (final cb in _deleteCallbacks) {
          cb(entry.value);
        }
      }
    }
  }

  /// Populates the cache from an initial subscription snapshot.
  ///
  /// Unlike [applyChanges], this does **not** fire insert callbacks because
  /// the rows represent existing server state rather than new mutations.
  void populateInitial(List<T> rows) {
    for (final row in rows) {
      _rows[_getKey(row)] = row;
    }
  }

  /// Removes all cached rows.
  void clear() => _rows.clear();
}

// Schema parser for SpacetimeDB module definitions.
//
// Fetches and parses the JSON schema from a SpacetimeDB server into typed
// Dart model classes that the code generator can consume.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Parsed module schema containing all type definitions, tables, and reducers.
class ModuleSchema {
  final List<AlgebraicTypeDef> typespace;
  final List<TableDef> tables;
  final List<ReducerDef> reducers;

  ModuleSchema({
    required this.typespace,
    required this.tables,
    required this.reducers,
  });

  /// Fetches and parses a module schema from the SpacetimeDB HTTP API.
  static Future<ModuleSchema> fetch(String host, String database) async {
    final uri = Uri.parse('$host/v1/database/$database/schema?version=9');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch schema: ${response.statusCode} ${response.body}',
      );
    }
    return ModuleSchema.fromJson(jsonDecode(response.body));
  }

  /// Parses a module schema from a JSON map.
  factory ModuleSchema.fromJson(Map<String, dynamic> json) {
    final typespaceJson = json['typespace']?['types'] as List? ?? [];
    final typespace = typespaceJson
        .map((t) => AlgebraicTypeDef.fromJson(t as Map<String, dynamic>))
        .toList();

    final tablesJson = json['tables'] as List? ?? [];
    final tables = tablesJson
        .map((t) => TableDef.fromJson(t as Map<String, dynamic>))
        .toList();

    final reducersJson = json['reducers'] as List? ?? [];
    final reducers = reducersJson
        .map((r) => ReducerDef.fromJson(r as Map<String, dynamic>))
        .toList();

    return ModuleSchema(
      typespace: typespace,
      tables: tables,
      reducers: reducers,
    );
  }

  /// Resolves a [RefType] to its concrete [AlgebraicType] by looking it up
  /// in the typespace. Follows chains of refs until a non-ref is found.
  AlgebraicType resolveType(AlgebraicType type) {
    var current = type;
    final visited = <int>{};
    while (current is RefType) {
      final ref = current.ref;
      if (visited.contains(ref)) {
        throw StateError('Circular type reference detected at index $ref');
      }
      visited.add(ref);
      if (ref < 0 || ref >= typespace.length) {
        throw RangeError('Type reference $ref is out of bounds '
            '(typespace has ${typespace.length} entries)');
      }
      current = typespace[ref].type;
    }
    return current;
  }

  /// Returns the name assigned to a typespace entry at [index], if any.
  ///
  /// Names come from tables (via productTypeRef) or from the typespace itself
  /// when types are named by convention.
  String? typeNameAt(int index) {
    // Check if any table uses this type ref.
    for (final table in tables) {
      if (table.productTypeRef == index) {
        return table.name;
      }
    }
    return null;
  }
}

/// A single entry in the typespace array, wrapping an [AlgebraicType].
class AlgebraicTypeDef {
  final AlgebraicType type;

  AlgebraicTypeDef({required this.type});

  factory AlgebraicTypeDef.fromJson(Map<String, dynamic> json) {
    return AlgebraicTypeDef(type: AlgebraicType.fromJson(json));
  }
}

/// Recursive algebraic type representation from the SpacetimeDB schema.
sealed class AlgebraicType {
  const AlgebraicType();

  /// Parses an [AlgebraicType] from its JSON representation.
  ///
  /// The JSON is a single-key object where the key identifies the type kind:
  /// `{"Bool": {}}`, `{"U32": {}}`, `{"String": {}}`, `{"Ref": 5}`,
  /// `{"Product": {"elements": [...]}}`, `{"Sum": {"variants": [...]}}`, etc.
  factory AlgebraicType.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('Bool')) return const BoolType();
    if (json.containsKey('U8')) return const U8Type();
    if (json.containsKey('U16')) return const U16Type();
    if (json.containsKey('U32')) return const U32Type();
    if (json.containsKey('U64')) return const U64Type();
    if (json.containsKey('U128')) return const U128AlgType();
    if (json.containsKey('U256')) return const U256AlgType();
    if (json.containsKey('I8')) return const I8Type();
    if (json.containsKey('I16')) return const I16Type();
    if (json.containsKey('I32')) return const I32Type();
    if (json.containsKey('I64')) return const I64Type();
    if (json.containsKey('I128')) return const I128AlgType();
    if (json.containsKey('I256')) return const I256AlgType();
    if (json.containsKey('F32')) return const F32Type();
    if (json.containsKey('F64')) return const F64Type();
    if (json.containsKey('String')) return const StringType();

    if (json.containsKey('Array')) {
      final arrayValue = json['Array'] as Map<String, dynamic>;
      // Support both formats:
      // New (real server): {"Array": {"String": []}} - element type directly
      // Old (legacy):      {"Array": {"elem_ty": {"String": {}}}} - nested under elem_ty
      final elemJson = arrayValue.containsKey('elem_ty')
          ? arrayValue['elem_ty'] as Map<String, dynamic>
          : arrayValue;
      final elemTy = AlgebraicType.fromJson(elemJson);
      return ArrayType(elementType: elemTy);
    }

    if (json.containsKey('Map')) {
      final mapJson = json['Map'] as Map<String, dynamic>;
      final keyTy =
          AlgebraicType.fromJson(mapJson['key_ty'] as Map<String, dynamic>);
      final valueTy =
          AlgebraicType.fromJson(mapJson['ty'] as Map<String, dynamic>);
      return MapType(keyType: keyTy, valueType: valueTy);
    }

    if (json.containsKey('Ref')) {
      return RefType(ref: json['Ref'] as int);
    }

    if (json.containsKey('Product')) {
      final productJson = json['Product'] as Map<String, dynamic>;
      final elementsJson = productJson['elements'] as List? ?? [];
      final elements = elementsJson
          .map((e) => ColumnDef.fromJson(e as Map<String, dynamic>))
          .toList();
      return _classifyProduct(ProductType(elements: elements));
    }

    if (json.containsKey('Sum')) {
      final sumJson = json['Sum'] as Map<String, dynamic>;
      final variantsJson = sumJson['variants'] as List? ?? [];
      final variants = variantsJson
          .map((v) => SumVariant.fromJson(v as Map<String, dynamic>))
          .toList();
      return _classifySum(SumType(variants: variants));
    }

    throw FormatException('Unknown AlgebraicType: ${json.keys.join(', ')}');
  }

  /// Detects special product types (Identity, ConnectionId, Timestamp)
  /// based on their field names.
  static AlgebraicType _classifyProduct(ProductType product) {
    if (product.elements.length == 1) {
      final fieldName = product.elements.first.name;
      if (fieldName == '__identity_bytes' || fieldName == '__identity__') {
        return const IdentityType();
      }
      if (fieldName == '__connection_id__') {
        return const ConnectionIdType();
      }
      if (fieldName == '__timestamp_micros_since_unix_epoch__') {
        return const TimestampType();
      }
    }
    return product;
  }

  /// Detects `Option<T>` from a Sum type where variant 0 is "some" and
  /// variant 1 is "none" (case-insensitive).
  static AlgebraicType _classifySum(SumType sum) {
    if (sum.variants.length == 2) {
      final v0Name = sum.variants[0].name?.toLowerCase();
      final v1Name = sum.variants[1].name?.toLowerCase();
      if (v0Name == 'some' && v1Name == 'none') {
        return OptionType(innerType: sum.variants[0].algebraicType);
      }
    }
    return sum;
  }
}

/// Boolean type.
class BoolType extends AlgebraicType {
  const BoolType();
}

/// Unsigned 8-bit integer type.
class U8Type extends AlgebraicType {
  const U8Type();
}

/// Unsigned 16-bit integer type.
class U16Type extends AlgebraicType {
  const U16Type();
}

/// Unsigned 32-bit integer type.
class U32Type extends AlgebraicType {
  const U32Type();
}

/// Unsigned 64-bit integer type.
class U64Type extends AlgebraicType {
  const U64Type();
}

/// Unsigned 128-bit integer type.
class U128AlgType extends AlgebraicType {
  const U128AlgType();
}

/// Unsigned 256-bit integer type.
class U256AlgType extends AlgebraicType {
  const U256AlgType();
}

/// Signed 8-bit integer type.
class I8Type extends AlgebraicType {
  const I8Type();
}

/// Signed 16-bit integer type.
class I16Type extends AlgebraicType {
  const I16Type();
}

/// Signed 32-bit integer type.
class I32Type extends AlgebraicType {
  const I32Type();
}

/// Signed 64-bit integer type.
class I64Type extends AlgebraicType {
  const I64Type();
}

/// Signed 128-bit integer type.
class I128AlgType extends AlgebraicType {
  const I128AlgType();
}

/// Signed 256-bit integer type.
class I256AlgType extends AlgebraicType {
  const I256AlgType();
}

/// 32-bit floating point type.
class F32Type extends AlgebraicType {
  const F32Type();
}

/// 64-bit floating point type.
class F64Type extends AlgebraicType {
  const F64Type();
}

/// UTF-8 string type.
class StringType extends AlgebraicType {
  const StringType();
}

/// Homogeneous array type.
class ArrayType extends AlgebraicType {
  final AlgebraicType elementType;
  const ArrayType({required this.elementType});
}

/// Key-value map type.
class MapType extends AlgebraicType {
  final AlgebraicType keyType;
  final AlgebraicType valueType;
  const MapType({required this.keyType, required this.valueType});
}

/// Product (struct) type with named or positional fields.
class ProductType extends AlgebraicType {
  final List<ColumnDef> elements;
  const ProductType({required this.elements});
}

/// Sum (tagged union) type with named variants.
class SumType extends AlgebraicType {
  final List<SumVariant> variants;
  const SumType({required this.variants});

  /// Returns true if this sum type represents a simple enum, i.e. all
  /// variants have empty product payloads (no data fields).
  bool get isSimpleEnum {
    for (final variant in variants) {
      final ty = variant.algebraicType;
      if (ty is ProductType && ty.elements.isEmpty) continue;
      return false;
    }
    return true;
  }
}

/// Reference to a type in the typespace by index.
class RefType extends AlgebraicType {
  final int ref;
  const RefType({required this.ref});
}

/// `Option<T>` represented as nullable T in Dart.
class OptionType extends AlgebraicType {
  final AlgebraicType innerType;
  const OptionType({required this.innerType});
}

/// SpacetimeDB Identity special type.
class IdentityType extends AlgebraicType {
  const IdentityType();
}

/// SpacetimeDB ConnectionId special type.
class ConnectionIdType extends AlgebraicType {
  const ConnectionIdType();
}

/// SpacetimeDB Timestamp special type.
class TimestampType extends AlgebraicType {
  const TimestampType();
}

/// Extracts the value from `{"some": "value"}` or `{"none": []}` Option format.
T? _parseOption<T>(dynamic json, T Function(dynamic) parse) {
  if (json == null) return null;
  if (json is Map<String, dynamic>) {
    if (json.containsKey('some')) return parse(json['some']);
    if (json.containsKey('none')) return null;
  }
  // Fallback: treat as direct value
  return parse(json);
}

String? _parseOptionString(dynamic json) =>
    _parseOption<String>(json, (v) => v as String);

/// Extracts the key from `{"User": []}` style enum tags in JSON.
String _parseEnumTag(dynamic json) {
  if (json is Map<String, dynamic>) {
    return json.keys.first;
  }
  return json.toString();
}

/// A field in a product type (struct field or reducer parameter).
class ColumnDef {
  final String? name;
  final AlgebraicType type;

  const ColumnDef({required this.name, required this.type});

  factory ColumnDef.fromJson(Map<String, dynamic> json) {
    return ColumnDef(
      name: _parseOptionString(json['name']),
      type: AlgebraicType.fromJson(json['algebraic_type'] as Map<String, dynamic>),
    );
  }
}

/// A variant in a sum type.
class SumVariant {
  final String? name;
  final AlgebraicType algebraicType;

  const SumVariant({required this.name, required this.algebraicType});

  factory SumVariant.fromJson(Map<String, dynamic> json) {
    return SumVariant(
      name: _parseOptionString(json['name']),
      algebraicType:
          AlgebraicType.fromJson(json['algebraic_type'] as Map<String, dynamic>),
    );
  }
}

/// Definition of an index on a table.
class IndexDef {
  final String name;
  final String? accessorName;
  final IndexAlgorithm algorithm;

  const IndexDef({
    required this.name,
    required this.accessorName,
    required this.algorithm,
  });

  factory IndexDef.fromJson(Map<String, dynamic> json) {
    return IndexDef(
      name: _parseOptionString(json['name']) ?? '',
      accessorName: _parseOptionString(json['accessor_name']),
      algorithm: IndexAlgorithm.fromJson(
          json['algorithm'] as Map<String, dynamic>),
    );
  }
}

/// Index algorithm (currently only BTree is defined).
class IndexAlgorithm {
  final List<int> columns;

  const IndexAlgorithm({required this.columns});

  factory IndexAlgorithm.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('BTree')) {
      final btree = json['BTree'];
      // BTree value can be a list of column indices directly, or a map with 'columns'
      if (btree is List) {
        return IndexAlgorithm(columns: btree.map((c) => c as int).toList());
      }
      if (btree is Map<String, dynamic>) {
        final cols = (btree['columns'] as List).map((c) => c as int).toList();
        return IndexAlgorithm(columns: cols);
      }
    }
    return const IndexAlgorithm(columns: []);
  }
}

/// Constraint on a table (e.g. unique constraint).
class ConstraintDef {
  final ConstraintKind kind;

  const ConstraintDef({required this.kind});

  factory ConstraintDef.fromJson(Map<String, dynamic> json) {
    // Can be under 'kind' or 'data' depending on schema version
    final kindJson = (json['data'] ?? json['kind']) as Map<String, dynamic>? ?? {};
    return ConstraintDef(kind: ConstraintKind.fromJson(kindJson));
  }
}

/// A constraint kind (currently only Unique is defined).
sealed class ConstraintKind {
  const ConstraintKind();

  factory ConstraintKind.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('Unique')) {
      final unique = json['Unique'] as Map<String, dynamic>;
      final cols = (unique['columns'] as List).map((c) => c as int).toList();
      return UniqueConstraint(columns: cols);
    }
    return const UnknownConstraint();
  }
}

/// A unique constraint on one or more columns.
class UniqueConstraint extends ConstraintKind {
  final List<int> columns;
  const UniqueConstraint({required this.columns});
}

/// Placeholder for unrecognized constraint kinds.
class UnknownConstraint extends ConstraintKind {
  const UnknownConstraint();
}

/// Definition of a SpacetimeDB table.
class TableDef {
  final String name;
  final int productTypeRef;
  final int? primaryKey;
  final List<IndexDef> indexes;
  final List<ConstraintDef> constraints;
  final String? schedule;
  final String tableType;
  final String tableAccess;

  const TableDef({
    required this.name,
    required this.productTypeRef,
    required this.primaryKey,
    required this.indexes,
    required this.constraints,
    required this.schedule,
    required this.tableType,
    required this.tableAccess,
  });

  factory TableDef.fromJson(Map<String, dynamic> json) {
    final indexesJson = json['indexes'] as List? ?? [];
    final constraintsJson = json['constraints'] as List? ?? [];

    // primary_key can be an int or a list of ints
    int? primaryKey;
    final pkRaw = json['primary_key'];
    if (pkRaw is int) {
      primaryKey = pkRaw;
    } else if (pkRaw is List && pkRaw.isNotEmpty) {
      primaryKey = pkRaw[0] as int;
    }

    return TableDef(
      name: json['name'] as String,
      productTypeRef: json['product_type_ref'] as int,
      primaryKey: primaryKey,
      indexes: indexesJson
          .map((i) => IndexDef.fromJson(i as Map<String, dynamic>))
          .toList(),
      constraints: constraintsJson
          .map((c) => ConstraintDef.fromJson(c as Map<String, dynamic>))
          .toList(),
      schedule: _parseOptionString(json['schedule']),
      tableType: _parseEnumTag(json['table_type'] ?? 'User'),
      tableAccess: _parseEnumTag(json['table_access'] ?? 'Private'),
    );
  }
}

/// Definition of a SpacetimeDB reducer.
class ReducerDef {
  final String name;
  final List<ColumnDef> params;
  final String? lifecycle;

  const ReducerDef({
    required this.name,
    required this.params,
    required this.lifecycle,
  });

  factory ReducerDef.fromJson(Map<String, dynamic> json) {
    final paramsJson = json['params'] as Map<String, dynamic>? ?? {};
    final elementsJson = paramsJson['elements'] as List? ?? [];
    final params = elementsJson
        .map((e) => ColumnDef.fromJson(e as Map<String, dynamic>))
        .toList();

    // lifecycle is {"some": {"OnConnect": []}} or {"none": []}
    String? lifecycle;
    final lcRaw = json['lifecycle'];
    if (lcRaw is Map<String, dynamic> && lcRaw.containsKey('some')) {
      final lcValue = lcRaw['some'];
      if (lcValue is Map<String, dynamic>) {
        lifecycle = lcValue.keys.first;
      } else if (lcValue is String) {
        lifecycle = lcValue;
      }
    } else if (lcRaw is String) {
      lifecycle = lcRaw;
    }

    return ReducerDef(
      name: json['name'] as String,
      params: params,
      lifecycle: lifecycle,
    );
  }

  /// Returns true if this is a lifecycle reducer (init, connect, disconnect).
  bool get isLifecycle => lifecycle != null;
}

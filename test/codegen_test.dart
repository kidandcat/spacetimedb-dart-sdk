import 'dart:convert';
import 'dart:io';

import 'package:spacetimedb_sdk/src/codegen/schema.dart';
import 'package:spacetimedb_sdk/src/codegen/generator.dart';
import 'package:test/test.dart';

/// A realistic schema JSON matching the SpacetimeDB v9 format,
/// with tables, reducers, enums, identity, option types, and arrays.
const _testSchemaJson = '''
{
  "typespace": {
    "types": [
      {
        "Product": {
          "elements": [
            {"name": "__identity_bytes", "algebraic_type": {"Array": {"elem_ty": {"U8": {}}}}}
          ]
        }
      },
      {
        "Sum": {
          "variants": [
            {"name": "text", "algebraic_type": {"Product": {"elements": []}}},
            {"name": "voice", "algebraic_type": {"Product": {"elements": []}}}
          ]
        }
      },
      {
        "Product": {
          "elements": [
            {"name": "id", "algebraic_type": {"U64": {}}},
            {"name": "owner_identity", "algebraic_type": {"Ref": 0}},
            {"name": "name", "algebraic_type": {"String": {}}},
            {"name": "icon_url", "algebraic_type": {"Sum": {"variants": [{"name": "some", "algebraic_type": {"String": {}}}, {"name": "none", "algebraic_type": {"Product": {"elements": []}}}]}}},
            {"name": "channel_type", "algebraic_type": {"Ref": 1}},
            {"name": "tags", "algebraic_type": {"Array": {"elem_ty": {"String": {}}}}},
            {"name": "member_count", "algebraic_type": {"U32": {}}}
          ]
        }
      },
      {
        "Product": {
          "elements": [
            {"name": "__identity_bytes", "algebraic_type": {"Array": {"elem_ty": {"U8": {}}}}}
          ]
        }
      },
      {
        "Product": {
          "elements": [
            {"name": "identity", "algebraic_type": {"Ref": 3}},
            {"name": "username", "algebraic_type": {"String": {}}},
            {"name": "display_name", "algebraic_type": {"String": {}}},
            {"name": "online", "algebraic_type": {"Bool": {}}},
            {"name": "bio", "algebraic_type": {"Sum": {"variants": [{"name": "some", "algebraic_type": {"String": {}}}, {"name": "none", "algebraic_type": {"Product": {"elements": []}}}]}}}
          ]
        }
      },
      {
        "Product": {
          "elements": [
            {"name": "id", "algebraic_type": {"U64": {}}},
            {"name": "channel_id", "algebraic_type": {"U64": {}}},
            {"name": "sender", "algebraic_type": {"Ref": 3}},
            {"name": "content", "algebraic_type": {"String": {}}},
            {"name": "timestamp", "algebraic_type": {"Product": {"elements": [{"name": "__timestamp_micros_since_unix_epoch__", "algebraic_type": {"I64": {}}}]}}}
          ]
        }
      }
    ]
  },
  "tables": [
    {
      "name": "server",
      "product_type_ref": 2,
      "primary_key": 0,
      "indexes": [{"name": "by_owner", "accessor_name": "owner_identity", "algorithm": {"BTree": {"columns": [1]}}}],
      "constraints": [{"kind": {"Unique": {"columns": [0]}}}],
      "schedule": null,
      "table_type": "User",
      "table_access": "Public"
    },
    {
      "name": "user",
      "product_type_ref": 4,
      "primary_key": 0,
      "indexes": [],
      "constraints": [],
      "schedule": null,
      "table_type": "User",
      "table_access": "Public"
    },
    {
      "name": "message",
      "product_type_ref": 5,
      "primary_key": 0,
      "indexes": [],
      "constraints": [],
      "schedule": null,
      "table_type": "User",
      "table_access": "Public"
    }
  ],
  "reducers": [
    {
      "name": "create_server",
      "params": {
        "elements": [
          {"name": "name", "algebraic_type": {"String": {}}},
          {"name": "icon_url", "algebraic_type": {"String": {}}}
        ]
      },
      "lifecycle": null
    },
    {
      "name": "send_message",
      "params": {
        "elements": [
          {"name": "channel_id", "algebraic_type": {"U64": {}}},
          {"name": "content", "algebraic_type": {"String": {}}}
        ]
      },
      "lifecycle": null
    },
    {
      "name": "set_name",
      "params": {
        "elements": [
          {"name": "name", "algebraic_type": {"String": {}}}
        ]
      },
      "lifecycle": null
    },
    {
      "name": "__init__",
      "params": {"elements": []},
      "lifecycle": "Init"
    },
    {
      "name": "__identity_connected__",
      "params": {"elements": []},
      "lifecycle": "ClientConnected"
    }
  ]
}
''';

void main() {
  group('ModuleSchema.fromJson', () {
    late ModuleSchema schema;

    setUp(() {
      schema = ModuleSchema.fromJson(jsonDecode(_testSchemaJson));
    });

    test('parses typespace with correct count', () {
      expect(schema.typespace.length, 6);
    });

    test('detects Identity special type at index 0', () {
      expect(schema.typespace[0].type, isA<IdentityType>());
    });

    test('detects simple enum at index 1', () {
      final type = schema.typespace[1].type;
      expect(type, isA<SumType>());
      expect((type as SumType).isSimpleEnum, isTrue);
      expect(type.variants.length, 2);
      expect(type.variants[0].name, 'text');
      expect(type.variants[1].name, 'voice');
    });

    test('parses product type with various field types at index 2', () {
      final type = schema.typespace[2].type;
      expect(type, isA<ProductType>());
      final product = type as ProductType;
      expect(product.elements.length, 7);
      expect(product.elements[0].name, 'id');
      expect(product.elements[0].type, isA<U64Type>());
      expect(product.elements[1].name, 'owner_identity');
      expect(product.elements[1].type, isA<RefType>());
      expect(product.elements[3].name, 'icon_url');
      expect(product.elements[3].type, isA<OptionType>());
      expect(product.elements[5].name, 'tags');
      expect(product.elements[5].type, isA<ArrayType>());
    });

    test('detects Option type from Sum with some/none variants', () {
      final product = schema.typespace[2].type as ProductType;
      final iconUrl = product.elements[3];
      expect(iconUrl.type, isA<OptionType>());
      expect((iconUrl.type as OptionType).innerType, isA<StringType>());
    });

    test('detects Timestamp special type', () {
      final product = schema.typespace[5].type as ProductType;
      final timestamp = product.elements[4];
      expect(timestamp.type, isA<TimestampType>());
    });

    test('parses tables correctly', () {
      expect(schema.tables.length, 3);
      expect(schema.tables[0].name, 'server');
      expect(schema.tables[0].productTypeRef, 2);
      expect(schema.tables[0].primaryKey, 0);
      expect(schema.tables[0].tableAccess, 'Public');
      expect(schema.tables[0].indexes.length, 1);
      expect(schema.tables[0].constraints.length, 1);
    });

    test('parses reducers correctly', () {
      expect(schema.reducers.length, 5);

      final createServer = schema.reducers[0];
      expect(createServer.name, 'create_server');
      expect(createServer.params.length, 2);
      expect(createServer.isLifecycle, isFalse);

      final init = schema.reducers[3];
      expect(init.name, '__init__');
      expect(init.isLifecycle, isTrue);
      expect(init.lifecycle, 'Init');
    });

    test('resolves RefType to concrete types', () {
      final ref0 = schema.resolveType(const RefType(ref: 0));
      expect(ref0, isA<IdentityType>());

      final ref1 = schema.resolveType(const RefType(ref: 1));
      expect(ref1, isA<SumType>());
    });
  });

  group('AlgebraicType.fromJson', () {
    test('parses all primitive types', () {
      expect(AlgebraicType.fromJson({'Bool': {}}), isA<BoolType>());
      expect(AlgebraicType.fromJson({'U8': {}}), isA<U8Type>());
      expect(AlgebraicType.fromJson({'U16': {}}), isA<U16Type>());
      expect(AlgebraicType.fromJson({'U32': {}}), isA<U32Type>());
      expect(AlgebraicType.fromJson({'U64': {}}), isA<U64Type>());
      expect(AlgebraicType.fromJson({'U128': {}}), isA<U128AlgType>());
      expect(AlgebraicType.fromJson({'U256': {}}), isA<U256AlgType>());
      expect(AlgebraicType.fromJson({'I8': {}}), isA<I8Type>());
      expect(AlgebraicType.fromJson({'I16': {}}), isA<I16Type>());
      expect(AlgebraicType.fromJson({'I32': {}}), isA<I32Type>());
      expect(AlgebraicType.fromJson({'I64': {}}), isA<I64Type>());
      expect(AlgebraicType.fromJson({'I128': {}}), isA<I128AlgType>());
      expect(AlgebraicType.fromJson({'I256': {}}), isA<I256AlgType>());
      expect(AlgebraicType.fromJson({'F32': {}}), isA<F32Type>());
      expect(AlgebraicType.fromJson({'F64': {}}), isA<F64Type>());
      expect(AlgebraicType.fromJson({'String': {}}), isA<StringType>());
    });

    test('parses Ref type', () {
      final type = AlgebraicType.fromJson({'Ref': 5});
      expect(type, isA<RefType>());
      expect((type as RefType).ref, 5);
    });

    test('parses Array type', () {
      final type = AlgebraicType.fromJson({
        'Array': {
          'elem_ty': {'String': {}}
        }
      });
      expect(type, isA<ArrayType>());
      expect((type as ArrayType).elementType, isA<StringType>());
    });

    test('parses Map type', () {
      final type = AlgebraicType.fromJson({
        'Map': {
          'key_ty': {'String': {}},
          'ty': {'U32': {}}
        }
      });
      expect(type, isA<MapType>());
      final mapType = type as MapType;
      expect(mapType.keyType, isA<StringType>());
      expect(mapType.valueType, isA<U32Type>());
    });

    test('detects Identity from product with __identity_bytes', () {
      final type = AlgebraicType.fromJson({
        'Product': {
          'elements': [
            {
              'name': '__identity_bytes',
              'algebraic_type': {
                'Array': {
                  'elem_ty': {'U8': {}}
                }
              }
            }
          ]
        }
      });
      expect(type, isA<IdentityType>());
    });

    test('detects Identity from product with __identity__', () {
      final type = AlgebraicType.fromJson({
        'Product': {
          'elements': [
            {
              'name': '__identity__',
              'algebraic_type': {'U256': {}}
            }
          ]
        }
      });
      expect(type, isA<IdentityType>());
    });

    test('detects ConnectionId from product with __connection_id__', () {
      final type = AlgebraicType.fromJson({
        'Product': {
          'elements': [
            {
              'name': '__connection_id__',
              'algebraic_type': {'U128': {}}
            }
          ]
        }
      });
      expect(type, isA<ConnectionIdType>());
    });

    test('detects Timestamp from product with __timestamp_micros_since_unix_epoch__', () {
      final type = AlgebraicType.fromJson({
        'Product': {
          'elements': [
            {
              'name': '__timestamp_micros_since_unix_epoch__',
              'algebraic_type': {'I64': {}}
            }
          ]
        }
      });
      expect(type, isA<TimestampType>());
    });

    test('detects Option from sum with some/none', () {
      final type = AlgebraicType.fromJson({
        'Sum': {
          'variants': [
            {
              'name': 'some',
              'algebraic_type': {'U32': {}}
            },
            {
              'name': 'none',
              'algebraic_type': {
                'Product': {'elements': []}
              }
            }
          ]
        }
      });
      expect(type, isA<OptionType>());
      expect((type as OptionType).innerType, isA<U32Type>());
    });

    test('throws on unknown type', () {
      expect(
        () => AlgebraicType.fromJson({'Unknown': {}}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DartGenerator', () {
    late ModuleSchema schema;
    late String tmpDir;

    setUp(() async {
      schema = ModuleSchema.fromJson(jsonDecode(_testSchemaJson));
      final tmp = await Directory.systemTemp.createTemp('codegen_test_');
      tmpDir = tmp.path;
    });

    tearDown(() async {
      final dir = Directory(tmpDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('generates all expected files', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      // Table type files.
      expect(File('$tmpDir/types/server.dart').existsSync(), isTrue);
      expect(File('$tmpDir/types/user.dart').existsSync(), isTrue);
      expect(File('$tmpDir/types/message.dart').existsSync(), isTrue);

      // Table handle files.
      expect(File('$tmpDir/tables/server_table.dart').existsSync(), isTrue);
      expect(File('$tmpDir/tables/user_table.dart').existsSync(), isTrue);
      expect(File('$tmpDir/tables/message_table.dart').existsSync(), isTrue);

      // Reducers file.
      expect(File('$tmpDir/reducers.dart').existsSync(), isTrue);

      // Barrel export.
      expect(File('$tmpDir/module.dart').existsSync(), isTrue);
    });

    test('generated table type has correct structure', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      final serverCode =
          await File('$tmpDir/types/server.dart').readAsString();

      // Check header.
      expect(
          serverCode, contains('// AUTO-GENERATED BY SPACETIMEDB DART SDK'));

      // Check import.
      expect(serverCode,
          contains("import 'package:spacetimedb_sdk/spacetimedb.dart';"));

      // Check class declaration.
      expect(serverCode, contains('class Server {'));

      // Check fields with correct Dart types.
      expect(serverCode, contains('final int id;'));
      expect(serverCode, contains('final Identity ownerIdentity;'));
      expect(serverCode, contains('final String name;'));
      expect(serverCode, contains('final String? iconUrl;'));
      expect(serverCode, contains('final List<String> tags;'));
      expect(serverCode, contains('final int memberCount;'));

      // Check writeBsatn method.
      expect(serverCode, contains('void writeBsatn(BsatnEncoder encoder)'));
      expect(serverCode, contains('encoder.writeU64(id)'));
      expect(serverCode, contains('ownerIdentity.writeBsatn(encoder)'));
      expect(serverCode, contains('encoder.writeString(name)'));
      expect(serverCode, contains('encoder.writeOptionSome()'));
      expect(serverCode, contains('encoder.writeOptionNone()'));
      expect(serverCode, contains('encoder.writeArrayHeader(tags.length)'));

      // Check readBsatn method.
      expect(serverCode,
          contains('static Server readBsatn(BsatnDecoder decoder)'));
      expect(serverCode, contains('decoder.readU64()'));
      expect(serverCode, contains('Identity.readBsatn(decoder)'));
      expect(serverCode, contains('decoder.readString()'));
      expect(serverCode, contains('decoder.readOption()'));
      expect(serverCode, contains('decoder.readArrayHeader()'));

      // Check equality based on PK (id field).
      expect(serverCode, contains('id == other.id'));
      expect(serverCode, contains('int get hashCode => id.hashCode'));
    });

    test('generated user type handles Identity PK', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      final userCode =
          await File('$tmpDir/types/user.dart').readAsString();

      expect(userCode, contains('class User {'));
      expect(userCode, contains('final Identity identity;'));
      expect(userCode, contains('final String username;'));
      expect(userCode, contains('final String displayName;'));
      expect(userCode, contains('final bool online;'));
      expect(userCode, contains('final String? bio;'));
      expect(userCode, contains('identity == other.identity'));
    });

    test('generated message type handles Timestamp', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      final msgCode =
          await File('$tmpDir/types/message.dart').readAsString();

      expect(msgCode, contains('class Message {'));
      expect(msgCode, contains('final Timestamp timestamp;'));
      expect(msgCode, contains('Timestamp.readBsatn(decoder)'));
      expect(msgCode, contains('timestamp.writeBsatn(encoder)'));
    });

    test('generated table handle has correct API', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      final handleCode =
          await File('$tmpDir/tables/server_table.dart').readAsString();

      expect(handleCode, contains('class ServerTableHandle {'));
      expect(handleCode, contains('final TableCache<Server> _cache;'));
      expect(handleCode, contains("tableName: 'server'"));
      expect(handleCode, contains('decoder: Server.readBsatn'));
      expect(handleCode, contains('pkExtractor: (row) => row.id'));
      expect(handleCode, contains('Iterable<Server> get rows'));
      expect(handleCode, contains('int get count'));
      expect(handleCode, contains('Server? findById(int id)'));
      expect(handleCode, contains('void onInsert('));
      expect(handleCode, contains('void onUpdate('));
      expect(handleCode, contains('void onDelete('));
    });

    test('generated reducers has correct methods', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      final reducersCode =
          await File('$tmpDir/reducers.dart').readAsString();

      // Check class.
      expect(reducersCode, contains('class RemoteReducers {'));

      // Check call methods.
      expect(reducersCode,
          contains('Future<void> createServer(String name, String iconUrl)'));
      expect(reducersCode,
          contains('Future<void> sendMessage(int channelId, String content)'));
      expect(reducersCode,
          contains('Future<void> setName(String name)'));

      // Check encoding in call methods.
      expect(reducersCode, contains("_callReducer('create_server'"));
      expect(reducersCode, contains("_callReducer('send_message'"));
      expect(reducersCode, contains('encoder.writeU64(channelId)'));
      expect(reducersCode, contains('encoder.writeString(content)'));

      // Check callback methods.
      expect(reducersCode, contains('void onCreateServer('));
      expect(reducersCode, contains('void onSendMessage('));
      expect(reducersCode, contains('void onSetName('));

      // Lifecycle reducers should NOT be included.
      expect(reducersCode, isNot(contains('__init__')));
      expect(reducersCode, isNot(contains('__identity_connected__')));
    });

    test('generated enum has correct structure', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      // The enum at index 1 (channel_type) should be generated.
      final enumFiles = Directory('$tmpDir/types')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      // Find the enum file (should be named after the field that references it).
      final enumFile = enumFiles.firstWhere(
        (f) => f.readAsStringSync().contains('enum '),
        orElse: () => throw StateError('No enum file found'),
      );
      final enumCode = enumFile.readAsStringSync();

      expect(enumCode, contains('// AUTO-GENERATED BY SPACETIMEDB DART SDK'));
      expect(enumCode, contains('text(0)'));
      expect(enumCode, contains('voice(1)'));
      expect(enumCode, contains('final int tag;'));
      expect(enumCode, contains('void writeBsatn(BsatnEncoder encoder)'));
      expect(enumCode, contains('encoder.writeSumTag(tag)'));
      expect(enumCode, contains('static'));
      expect(enumCode, contains('readBsatn(BsatnDecoder decoder)'));
      expect(enumCode, contains('decoder.readSumTag()'));
    });

    test('generated barrel export references all files', () async {
      final generator = DartGenerator(schema: schema, outputDir: tmpDir);
      await generator.generate();

      final barrelCode =
          await File('$tmpDir/module.dart').readAsString();

      expect(barrelCode, contains("export 'types/server.dart'"));
      expect(barrelCode, contains("export 'types/user.dart'"));
      expect(barrelCode, contains("export 'types/message.dart'"));
      expect(barrelCode, contains("export 'tables/server_table.dart'"));
      expect(barrelCode, contains("export 'tables/user_table.dart'"));
      expect(barrelCode, contains("export 'tables/message_table.dart'"));
      expect(barrelCode, contains("export 'reducers.dart'"));
    });

    test('dart type mapping is correct', () {
      final generator = DartGenerator(schema: schema, outputDir: '.');
      // Call _resolveTypeNames via generate's internal setup, but we can
      // test dartType directly for non-ref types.
      expect(generator.dartType(const BoolType()), 'bool');
      expect(generator.dartType(const U8Type()), 'int');
      expect(generator.dartType(const U16Type()), 'int');
      expect(generator.dartType(const U32Type()), 'int');
      expect(generator.dartType(const U64Type()), 'int');
      expect(generator.dartType(const U128AlgType()), 'U128');
      expect(generator.dartType(const U256AlgType()), 'U256');
      expect(generator.dartType(const I8Type()), 'int');
      expect(generator.dartType(const I16Type()), 'int');
      expect(generator.dartType(const I32Type()), 'int');
      expect(generator.dartType(const I64Type()), 'int');
      expect(generator.dartType(const I128AlgType()), 'I128');
      expect(generator.dartType(const I256AlgType()), 'I256');
      expect(generator.dartType(const F32Type()), 'double');
      expect(generator.dartType(const F64Type()), 'double');
      expect(generator.dartType(const StringType()), 'String');
      expect(generator.dartType(const IdentityType()), 'Identity');
      expect(generator.dartType(const ConnectionIdType()), 'ConnectionId');
      expect(generator.dartType(const TimestampType()), 'Timestamp');
      expect(
          generator
              .dartType(const ArrayType(elementType: StringType())),
          'List<String>');
      expect(
          generator.dartType(const MapType(
              keyType: StringType(), valueType: U32Type())),
          'Map<String, int>');
      expect(
          generator
              .dartType(const OptionType(innerType: StringType())),
          'String?');
    });
  });
}

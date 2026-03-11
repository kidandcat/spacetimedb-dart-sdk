import 'dart:convert';
import 'dart:io';

import 'package:spacetimedb_sdk/src/codegen/schema.dart';
import 'package:spacetimedb_sdk/src/codegen/generator.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helper: build a minimal schema JSON with the given typespace + tables +
// reducers and parse it into a [ModuleSchema].
// ---------------------------------------------------------------------------
ModuleSchema _makeSchema(Map<String, dynamic> json) =>
    ModuleSchema.fromJson(json);

// ---------------------------------------------------------------------------
// Shared temp-dir management
// ---------------------------------------------------------------------------
late Directory _tmp;

Future<String> _makeTmpDir() async {
  _tmp = await Directory.systemTemp.createTemp('gen_test_');
  return _tmp.path;
}

Future<void> _cleanTmpDir() async {
  if (await _tmp.exists()) await _tmp.delete(recursive: true);
}

void main() {
  // =========================================================================
  // 1. Tagged unions (complex sum types – variants with non-empty payloads)
  // =========================================================================
  group('tagged union (complex sum type)', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    // Schema: one table whose "payload" field is a tagged union where each
    // variant carries a non-empty product payload.
    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: the tagged union
          {
            'Sum': {
              'variants': [
                {
                  'name': 'text_msg',
                  'algebraic_type': {
                    'Product': {
                      'elements': [
                        {'name': 'body', 'algebraic_type': {'String': {}}}
                      ]
                    }
                  }
                },
                {
                  'name': 'image_msg',
                  'algebraic_type': {
                    'Product': {
                      'elements': [
                        {'name': 'url', 'algebraic_type': {'String': {}}},
                        {'name': 'width', 'algebraic_type': {'U32': {}}}
                      ]
                    }
                  }
                },
              ]
            }
          },
          // index 1: table product type
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {'name': 'payload', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'event',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('generates a sealed class for the tagged union', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      // The tagged union file should be named after the field: payload.dart
      final unionFile = File('$outDir/types/payload.dart');
      expect(unionFile.existsSync(), isTrue,
          reason: 'payload.dart should exist for the tagged union');

      final code = await unionFile.readAsString();
      expect(code, contains('sealed class Payload {'));
      expect(code, contains('class PayloadTextMsg extends Payload {'));
      expect(code, contains('class PayloadImageMsg extends Payload {'));
    });

    test('tagged union sealed class has writeBsatn / readBsatn', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/payload.dart').readAsString();
      expect(code, contains('void writeBsatn(BsatnEncoder encoder);'));
      expect(code, contains('static Payload readBsatn(BsatnDecoder decoder)'));
      expect(code, contains('decoder.readSumTag()'));
    });

    test('tagged union variant with fields has _readPayload factory', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/payload.dart').readAsString();
      expect(code,
          contains('static PayloadTextMsg _readPayload(BsatnDecoder decoder)'));
      expect(code,
          contains('static PayloadImageMsg _readPayload(BsatnDecoder decoder)'));
      expect(code, contains("final String body;"));
      expect(code, contains("final String url;"));
      expect(code, contains("final int width;"));
    });

    test('tagged union variant writeBsatn writes tag then payload', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/payload.dart').readAsString();
      expect(code, contains('encoder.writeSumTag(0)'));
      expect(code, contains('encoder.writeSumTag(1)'));
      expect(code, contains('encoder.writeString(body)'));
      expect(code, contains('encoder.writeString(url)'));
      expect(code, contains('encoder.writeU32(width)'));
    });

    test('barrel export includes tagged union file', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final barrel = await File('$outDir/module.dart').readAsString();
      expect(barrel, contains("export 'types/payload.dart'"));
    });
  });

  // =========================================================================
  // 2. Tagged union with empty variants (fallback const constructor)
  // =========================================================================
  group('tagged union with empty variant', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: mixed tagged union – one empty, one non-empty variant
          {
            'Sum': {
              'variants': [
                {
                  'name': 'empty_v',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
                {
                  'name': 'rich_v',
                  'algebraic_type': {
                    'Product': {
                      'elements': [
                        {'name': 'value', 'algebraic_type': {'I32': {}}}
                      ]
                    }
                  }
                },
              ]
            }
          },
          // index 1: table product type
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                {'name': 'kind', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'thing',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('empty variant uses const constructor', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/kind.dart').readAsString();
      // Empty variant should have const constructor and no _readPayload.
      expect(code, contains('const KindEmptyV();'));
      expect(code, contains('return const KindEmptyV();'));
      // Rich variant with payload should have _readPayload.
      expect(code,
          contains('static KindRichV _readPayload(BsatnDecoder decoder)'));
    });
  });

  // =========================================================================
  // 3. Tagged union with non-product single-value payload
  // =========================================================================
  group('tagged union with non-product payload', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: tagged union whose variant payload is a bare String (not Product)
          {
            'Sum': {
              'variants': [
                {
                  'name': 'text',
                  'algebraic_type': {'String': {}}
                },
              ]
            }
          },
          // index 1: table product type
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                {'name': 'msg', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'note',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('single non-product payload variant has value field', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/msg.dart').readAsString();
      expect(code, contains('final String value;'));
      expect(code, contains('const MsgText(this.value);'));
      expect(code, contains('static MsgText _readPayload(BsatnDecoder decoder)'));
      expect(code, contains('decoder.readString()'));
      expect(code, contains('encoder.writeString(value)'));
    });
  });

  // =========================================================================
  // 4. Custom product type (standalone struct referenced from table field)
  // =========================================================================
  group('custom product type (standalone struct)', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    // Schema: a "point" struct referenced from a table field.
    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: standalone struct (not a table type)
          {
            'Product': {
              'elements': [
                {'name': 'x', 'algebraic_type': {'F64': {}}},
                {'name': 'y', 'algebraic_type': {'F64': {}}},
              ]
            }
          },
          // index 1: table product type referencing the struct
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {'name': 'position', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'entity',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('generates a separate class file for the standalone struct', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      // Named after the field that references it: position.
      final structFile = File('$outDir/types/position.dart');
      expect(structFile.existsSync(), isTrue,
          reason: 'position.dart should exist for the custom struct');

      final code = await structFile.readAsString();
      expect(code, contains('class Position {'));
      expect(code, contains('final double x;'));
      expect(code, contains('final double y;'));
    });

    test('custom struct has writeBsatn / readBsatn', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/position.dart').readAsString();
      expect(code, contains('void writeBsatn(BsatnEncoder encoder)'));
      expect(code, contains('static Position readBsatn(BsatnDecoder decoder)'));
      expect(code, contains('encoder.writeF64(x)'));
      expect(code, contains('encoder.writeF64(y)'));
      expect(code, contains('decoder.readF64()'));
    });

    test('table file references the struct via readBsatn', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final entityCode =
          await File('$outDir/types/entity.dart').readAsString();
      // The field type should use the resolved struct name.
      expect(entityCode, contains('final Position position;'));
      expect(entityCode, contains('Position.readBsatn(decoder)'));
      expect(entityCode, contains('position.writeBsatn(encoder)'));
    });

    test('custom struct equality uses all fields (no PK)', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/position.dart').readAsString();
      expect(code, contains('x == other.x'));
      expect(code, contains('y == other.y'));
      // hashCode uses Object.hash for two fields.
      expect(code, contains('Object.hash(x, y)'));
    });

    test('barrel export includes the custom struct file', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final barrel = await File('$outDir/module.dart').readAsString();
      expect(barrel, contains("export 'types/position.dart'"));
    });
  });

  // =========================================================================
  // 5. Map type encoding / decoding
  // =========================================================================
  group('Map type encoding and decoding', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {
                  'name': 'scores',
                  'algebraic_type': {
                    'Map': {
                      'key_ty': {'String': {}},
                      'ty': {'U32': {}}
                    }
                  }
                },
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'leaderboard',
          'product_type_ref': 0,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('Map field has correct Dart type Map<String, int>', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/leaderboard.dart').readAsString();
      expect(code, contains('final Map<String, int> scores;'));
    });

    test('Map writeBsatn uses writeArrayHeader + entry loop', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/leaderboard.dart').readAsString();
      expect(code, contains('encoder.writeArrayHeader(scores.length)'));
      expect(code, contains('for (final entry in scores.entries)'));
      expect(code, contains('encoder.writeString(entry.key)'));
      expect(code, contains('encoder.writeU32(entry.value)'));
    });

    test('Map readBsatn uses readArrayHeader + map comprehension', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/leaderboard.dart').readAsString();
      expect(code, contains('decoder.readArrayHeader()'));
      expect(code, contains('decoder.readString()'));
      expect(code, contains('decoder.readU32()'));
    });
  });

  // =========================================================================
  // 6. U128 / U256 / I128 / I256 big integer types
  // =========================================================================
  group('big integer types (U128/U256/I128/I256)', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                {'name': 'big_u128', 'algebraic_type': {'U128': {}}},
                {'name': 'big_u256', 'algebraic_type': {'U256': {}}},
                {'name': 'big_i128', 'algebraic_type': {'I128': {}}},
                {'name': 'big_i256', 'algebraic_type': {'I256': {}}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'bignum',
          'product_type_ref': 0,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('big integer fields use correct Dart types', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/bignum.dart').readAsString();
      expect(code, contains('final U128 bigU128;'));
      expect(code, contains('final U256 bigU256;'));
      expect(code, contains('final I128 bigI128;'));
      expect(code, contains('final I256 bigI256;'));
    });

    test('big integer fields use correct encoder methods', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/bignum.dart').readAsString();
      expect(code, contains('encoder.writeU128(bigU128)'));
      expect(code, contains('encoder.writeU256(bigU256)'));
      expect(code, contains('encoder.writeI128(bigI128)'));
      expect(code, contains('encoder.writeI256(bigI256)'));
    });

    test('big integer fields use correct decoder methods', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/bignum.dart').readAsString();
      expect(code, contains('decoder.readU128()'));
      expect(code, contains('decoder.readU256()'));
      expect(code, contains('decoder.readI128()'));
      expect(code, contains('decoder.readI256()'));
    });
  });

  // =========================================================================
  // 7. F32 / F64 float types
  // =========================================================================
  group('float types (F32/F64)', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                {'name': 'velocity', 'algebraic_type': {'F32': {}}},
                {'name': 'temperature', 'algebraic_type': {'F64': {}}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'sensor',
          'product_type_ref': 0,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('F32/F64 fields use double Dart type', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/sensor.dart').readAsString();
      expect(code, contains('final double velocity;'));
      expect(code, contains('final double temperature;'));
    });

    test('F32/F64 use correct encoder methods', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/sensor.dart').readAsString();
      expect(code, contains('encoder.writeF32(velocity)'));
      expect(code, contains('encoder.writeF64(temperature)'));
    });

    test('F32/F64 use correct decoder methods', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/sensor.dart').readAsString();
      expect(code, contains('decoder.readF32()'));
      expect(code, contains('decoder.readF64()'));
    });
  });

  // =========================================================================
  // 8. Nested Ref to a custom product type (not a special type)
  // =========================================================================
  group('nested Ref to custom product type', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    // Schema: a table whose "address" field references a custom struct.
    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: custom struct (address)
          {
            'Product': {
              'elements': [
                {'name': 'street', 'algebraic_type': {'String': {}}},
                {'name': 'city', 'algebraic_type': {'String': {}}},
                {'name': 'zip', 'algebraic_type': {'U32': {}}},
              ]
            }
          },
          // index 1: table product type
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {'name': 'address', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'customer',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('generates custom struct file for nested ref', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      expect(File('$outDir/types/address.dart').existsSync(), isTrue);
      final code = await File('$outDir/types/address.dart').readAsString();
      expect(code, contains('class Address {'));
      expect(code, contains('final String street;'));
      expect(code, contains('final String city;'));
      expect(code, contains('final int zip;'));
    });

    test('table file uses Address type for nested ref field', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/customer.dart').readAsString();
      expect(code, contains('final Address address;'));
      expect(code, contains('Address.readBsatn(decoder)'));
      expect(code, contains('address.writeBsatn(encoder)'));
    });

    test('table handle file imports custom struct', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/tables/customer_table.dart').readAsString();
      expect(code, contains("import '../types/address.dart';"));
    });
  });

  // =========================================================================
  // 9. Table with no primary key — equality falls back to all fields
  // =========================================================================
  group('table with no primary key', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {
              'elements': [
                {'name': 'name', 'algebraic_type': {'String': {}}},
                {'name': 'score', 'algebraic_type': {'U32': {}}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'score_entry',
          // No primary_key field (null).
          'product_type_ref': 0,
          'primary_key': null,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('equality uses all fields when no PK', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/score_entry.dart').readAsString();
      expect(code, contains('name == other.name'));
      expect(code, contains('score == other.score'));
      // hashCode should NOT be single-field; two fields → Object.hash.
      expect(code, contains('Object.hash(name, score)'));
    });

    test('no findById method when no PK', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final handleCode =
          await File('$outDir/tables/score_entry_table.dart').readAsString();
      // There should be no findBy* method.
      expect(handleCode, isNot(contains('findBy')));
      // pkExtractor should not appear.
      expect(handleCode, isNot(contains('pkExtractor')));
    });
  });

  // =========================================================================
  // 10. Table with a single-field (no PK) – hashCode single field path
  // =========================================================================
  group('table with no PK and single field', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {
              'elements': [
                {'name': 'tag', 'algebraic_type': {'String': {}}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'tag_entry',
          'product_type_ref': 0,
          'primary_key': null,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('single-field no-PK table uses field.hashCode (not Object.hash)',
        () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/tag_entry.dart').readAsString();
      expect(code, contains('int get hashCode => tag.hashCode;'));
      expect(code, isNot(contains('Object.hash')));
    });
  });

  // =========================================================================
  // 11. Enum naming: field name → PascalCase enum name
  // =========================================================================
  group('enum naming from field reference', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    // Reproduces the existing schema structure: a simple Sum (enum) referenced
    // via a field named "channel_type".
    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: simple enum
          {
            'Sum': {
              'variants': [
                {
                  'name': 'public',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
                {
                  'name': 'private',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
              ]
            }
          },
          // index 1: table product type with field named channel_type
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {'name': 'channel_type', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'channel',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('enum file named after field in snake_case', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      // Field is "channel_type" → enum name "ChannelType" → file "channel_type.dart".
      expect(File('$outDir/types/channel_type.dart').existsSync(), isTrue);
    });

    test('enum declaration uses PascalCase of field name', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/channel_type.dart').readAsString();
      expect(code, contains('enum ChannelType {'));
    });

    test('enum variants are camelCase with tag values', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/channel_type.dart').readAsString();
      expect(code, contains('public(0)'));
      expect(code, contains('private(1)'));
    });

    test('enum readBsatn uses decoder.readSumTag()', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/channel_type.dart').readAsString();
      expect(code, contains('decoder.readSumTag()'));
      expect(code, contains('ChannelType.values.firstWhere'));
    });

    test('table file uses ChannelType for the field', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/channel.dart').readAsString();
      expect(code, contains('final ChannelType channelType;'));
    });
  });

  // =========================================================================
  // 12. Multiple tables referencing the same custom type — no duplicate files
  // =========================================================================
  group('multiple tables referencing the same type', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    // Two tables both reference the same enum at index 0.
    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: simple enum shared by two tables
          {
            'Sum': {
              'variants': [
                {
                  'name': 'active',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
                {
                  'name': 'inactive',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
              ]
            }
          },
          // index 1: first table
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {'name': 'status', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
          // index 2: second table (same "status" field referencing same enum)
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {'name': 'status', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'user_account',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        },
        {
          'name': 'device',
          'product_type_ref': 2,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        },
      ],
      'reducers': [],
    });

    test('shared enum file is generated exactly once', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      // The enum is named "Status" from the field name.
      final enumFiles = Directory('$outDir/types')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('status'))
          .toList();

      expect(enumFiles.length, 1,
          reason: 'Shared enum should only be generated once');
    });

    test('both tables reference Status type correctly', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final userCode =
          await File('$outDir/types/user_account.dart').readAsString();
      final deviceCode =
          await File('$outDir/types/device.dart').readAsString();

      expect(userCode, contains('final Status status;'));
      expect(deviceCode, contains('final Status status;'));
    });

    test('barrel export references shared enum exactly once', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final barrel = await File('$outDir/module.dart').readAsString();
      final statusExports =
          RegExp(r"export 'types/status\.dart'").allMatches(barrel);
      expect(statusExports.length, 1,
          reason: "Barrel should export status.dart only once");
    });
  });

  // =========================================================================
  // 13. Reducer with custom type parameter (import from types/ prefix)
  // =========================================================================
  group('reducer with custom type parameter', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    // A reducer that takes a parameter which is a simple enum.
    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: simple enum used as reducer param
          {
            'Sum': {
              'variants': [
                {
                  'name': 'read',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
                {
                  'name': 'write',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
              ]
            }
          },
          // index 1: table (so generator runs without issues)
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'perm',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [
        {
          'name': 'set_permission',
          'params': {
            'elements': [
              {
                'name': 'mode',
                'algebraic_type': {'Ref': 0}
              }
            ]
          },
          'lifecycle': null,
        }
      ],
    });

    test('reducer file imports custom enum with types/ prefix', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final reducersCode =
          await File('$outDir/reducers.dart').readAsString();
      // Reducers live in outputDir root, so imports need "types/" prefix.
      expect(reducersCode, contains("import 'types/mode.dart';"));
    });

    test('reducer method has correct parameter type', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final reducersCode =
          await File('$outDir/reducers.dart').readAsString();
      expect(reducersCode,
          contains('Future<void> setPermission(Mode mode)'));
    });

    test('reducer encodes enum param via writeBsatn', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final reducersCode =
          await File('$outDir/reducers.dart').readAsString();
      expect(reducersCode, contains('mode.writeBsatn(encoder)'));
    });
  });

  // =========================================================================
  // 14. Table with ConnectionId and Timestamp fields
  // =========================================================================
  group('table with ConnectionId and Timestamp fields', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: ConnectionId
          {
            'Product': {
              'elements': [
                {'name': '__connection_id__', 'algebraic_type': {'U128': {}}}
              ]
            }
          },
          // index 1: table product type
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U64': {}}},
                {'name': 'conn', 'algebraic_type': {'Ref': 0}},
                {
                  'name': 'created_at',
                  'algebraic_type': {
                    'Product': {
                      'elements': [
                        {
                          'name': '__timestamp_micros_since_unix_epoch__',
                          'algebraic_type': {'I64': {}}
                        }
                      ]
                    }
                  }
                },
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'session',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('ConnectionId field has correct Dart type', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/session.dart').readAsString();
      expect(code, contains('final ConnectionId conn;'));
    });

    test('ConnectionId uses writeBsatn / readBsatn', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/session.dart').readAsString();
      expect(code, contains('conn.writeBsatn(encoder)'));
      expect(code, contains('ConnectionId.readBsatn(decoder)'));
    });

    test('Timestamp field has correct Dart type and encoding', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/session.dart').readAsString();
      expect(code, contains('final Timestamp createdAt;'));
      expect(code, contains('createdAt.writeBsatn(encoder)'));
      expect(code, contains('Timestamp.readBsatn(decoder)'));
    });
  });

  // =========================================================================
  // 15. Table with empty fields (edge case: toString, hashCode)
  // =========================================================================
  group('table with empty product type', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    // A table that maps to an empty product type (edge case).
    // NOTE: The generator only creates custom-product files for non-empty
    // types. But table types can still be empty (the table row has no fields).
    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {'elements': []}
          },
        ]
      },
      'tables': [
        {
          'name': 'empty_table',
          'product_type_ref': 0,
          'primary_key': null,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('empty table type generates valid class', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/empty_table.dart').readAsString();
      expect(code, contains('class EmptyTable {'));
    });

    test('empty table type hashCode returns 0', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/empty_table.dart').readAsString();
      expect(code, contains('int get hashCode => 0;'));
    });

    test('empty table type toString returns ClassName()', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/empty_table.dart').readAsString();
      expect(code, contains("String toString() => 'EmptyTable()';"));
    });
  });

  // =========================================================================
  // 16. Bool, U8, I8, U16, I16, I32, I64 primitive types
  // =========================================================================
  group('remaining primitive types', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                {'name': 'flag', 'algebraic_type': {'Bool': {}}},
                {'name': 'byte_val', 'algebraic_type': {'U8': {}}},
                {'name': 'signed_byte', 'algebraic_type': {'I8': {}}},
                {'name': 'short_val', 'algebraic_type': {'U16': {}}},
                {'name': 'signed_short', 'algebraic_type': {'I16': {}}},
                {'name': 'int_val', 'algebraic_type': {'I32': {}}},
                {'name': 'long_val', 'algebraic_type': {'I64': {}}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'primitives',
          'product_type_ref': 0,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('all primitive fields map to correct Dart types', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/primitives.dart').readAsString();
      expect(code, contains('final bool flag;'));
      expect(code, contains('final int byteVal;'));
      expect(code, contains('final int signedByte;'));
      expect(code, contains('final int shortVal;'));
      expect(code, contains('final int signedShort;'));
      expect(code, contains('final int intVal;'));
      expect(code, contains('final int longVal;'));
    });

    test('all primitive fields use correct encoder methods', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/primitives.dart').readAsString();
      expect(code, contains('encoder.writeBool(flag)'));
      expect(code, contains('encoder.writeU8(byteVal)'));
      expect(code, contains('encoder.writeI8(signedByte)'));
      expect(code, contains('encoder.writeU16(shortVal)'));
      expect(code, contains('encoder.writeI16(signedShort)'));
      expect(code, contains('encoder.writeI32(intVal)'));
      expect(code, contains('encoder.writeI64(longVal)'));
    });

    test('all primitive fields use correct decoder methods', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/primitives.dart').readAsString();
      expect(code, contains('decoder.readBool()'));
      expect(code, contains('decoder.readU8()'));
      expect(code, contains('decoder.readI8()'));
      expect(code, contains('decoder.readU16()'));
      expect(code, contains('decoder.readI16()'));
      expect(code, contains('decoder.readI32()'));
      expect(code, contains('decoder.readI64()'));
    });
  });

  // =========================================================================
  // 17. Array of custom type (nested encode/decode)
  //
  // Note: _findNameForRef only matches *direct* RefType fields, not refs
  // wrapped inside ArrayType. When an enum is ONLY referenced through an
  // array element, it receives the fallback name "Type<index>". The test
  // schema includes a direct reference (the "default_flag" field) so that
  // the enum is properly named, and then also an array field to exercise
  // the array encode/decode path with a named type.
  // =========================================================================
  group('Array of custom enum type', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: simple enum — named via "default_flag" direct ref field
          {
            'Sum': {
              'variants': [
                {
                  'name': 'a',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
                {
                  'name': 'b',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
              ]
            }
          },
          // index 1: table with a direct ref (to name the enum) and an array
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                // Direct ref field → gives the enum the name "DefaultFlag"
                {'name': 'default_flag', 'algebraic_type': {'Ref': 0}},
                // Array field of the same enum
                {
                  'name': 'extra_flags',
                  'algebraic_type': {
                    'Array': {'Ref': 0}
                  }
                },
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'flag_set',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('direct-ref enum field has correct named Dart type', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/flag_set.dart').readAsString();
      expect(code, contains('final DefaultFlag defaultFlag;'));
    });

    test('array of enum field has List<NamedEnum> Dart type', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/flag_set.dart').readAsString();
      expect(code, contains('final List<DefaultFlag> extraFlags;'));
    });

    test('array of enum encodes via writeArrayHeader + item.writeBsatn',
        () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/flag_set.dart').readAsString();
      expect(code, contains('encoder.writeArrayHeader(extraFlags.length)'));
      expect(code, contains('item.writeBsatn(encoder)'));
    });

    test('array of enum decodes via readArrayHeader + Enum.readBsatn',
        () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/flag_set.dart').readAsString();
      expect(code, contains('decoder.readArrayHeader()'));
      expect(code, contains('DefaultFlag.readBsatn(decoder)'));
    });
  });

  // =========================================================================
  // 17b. Array of unnamed (fallback-named) type
  //
  // When a Sum type is ONLY referenced through an ArrayType field and has no
  // direct RefType field, the generator cannot find a name and falls back to
  // "Type<index>". This test documents and verifies that behavior.
  // =========================================================================
  group('Array of unnamed (fallback) enum type', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: simple enum with NO direct RefType field pointing to it
          {
            'Sum': {
              'variants': [
                {
                  'name': 'on',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
                {
                  'name': 'off',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
              ]
            }
          },
          // index 1: table with ONLY an array ref (no direct ref)
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                {
                  'name': 'bits',
                  'algebraic_type': {
                    'Array': {'Ref': 0}
                  }
                },
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'bit_row',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('fallback-named enum gets Type0 name', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/bit_row.dart').readAsString();
      // The generator uses "Type0" as the fallback name when no direct field ref found.
      expect(code, contains('final List<Type0> bits;'));
    });

    test('fallback-named enum generates a file named type0.dart', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      expect(File('$outDir/types/type0.dart').existsSync(), isTrue);
    });

    test('array encode/decode still uses the fallback type correctly',
        () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code =
          await File('$outDir/types/bit_row.dart').readAsString();
      expect(code, contains('encoder.writeArrayHeader(bits.length)'));
      expect(code, contains('decoder.readArrayHeader()'));
      expect(code, contains('Type0.readBsatn(decoder)'));
    });
  });

  // =========================================================================
  // 18. dartType() for RefType with known and unknown name
  // =========================================================================
  group('dartType() for RefType', () {
    // Use a schema with a Ref that resolves to a known named type and one
    // that resolves to a primitive (unnamed).
    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: simple enum (will be named)
          {
            'Sum': {
              'variants': [
                {
                  'name': 'x',
                  'algebraic_type': {
                    'Product': {'elements': []}
                  }
                },
              ]
            }
          },
          // index 1: table product
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}},
                {'name': 'kind', 'algebraic_type': {'Ref': 0}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'item',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('dartType for RefType with known name returns named type string',
        () async {
      // We need to call generate() first so _typeNames is populated.
      final tmp = await Directory.systemTemp.createTemp('dt_test_');
      try {
        final generator = DartGenerator(schema: schema, outputDir: tmp.path);
        await generator.generate();
        // After generate, RefType(ref: 0) → 'Kind'
        expect(generator.dartType(const RefType(ref: 0)), 'Kind');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  // =========================================================================
  // 19. Generated table handle with Identity PK uses Identity findBy method
  // =========================================================================
  group('table handle with Identity primary key', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          // index 0: Identity
          {
            'Product': {
              'elements': [
                {
                  'name': '__identity_bytes',
                  'algebraic_type': {
                    'Array': {'U8': []}
                  }
                }
              ]
            }
          },
          // index 1: table with Identity as PK
          {
            'Product': {
              'elements': [
                {'name': 'identity', 'algebraic_type': {'Ref': 0}},
                {'name': 'name', 'algebraic_type': {'String': {}}},
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'player',
          'product_type_ref': 1,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [],
    });

    test('table handle has findByIdentity method with Identity param',
        () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final handleCode =
          await File('$outDir/tables/player_table.dart').readAsString();
      expect(handleCode, contains('Player? findByIdentity(Identity identity)'));
      expect(handleCode, contains('pkExtractor: (row) => row.identity'));
    });

    test('table type equality based on Identity PK', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/types/player.dart').readAsString();
      expect(code, contains('identity == other.identity'));
      expect(code, contains('int get hashCode => identity.hashCode'));
    });
  });

  // =========================================================================
  // 20. Reducer with no params generates empty encoder block
  // =========================================================================
  group('reducer with no parameters', () {
    late String outDir;

    setUp(() async => outDir = await _makeTmpDir());
    tearDown(_cleanTmpDir);

    final schema = _makeSchema({
      'typespace': {
        'types': [
          {
            'Product': {
              'elements': [
                {'name': 'id', 'algebraic_type': {'U32': {}}}
              ]
            }
          },
        ]
      },
      'tables': [
        {
          'name': 'counter',
          'product_type_ref': 0,
          'primary_key': 0,
          'indexes': [],
          'constraints': [],
          'schedule': null,
          'table_type': 'User',
          'table_access': 'Public',
        }
      ],
      'reducers': [
        {
          'name': 'reset',
          'params': {'elements': []},
          'lifecycle': null,
        }
      ],
    });

    test('no-param reducer method has empty signature', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/reducers.dart').readAsString();
      expect(code, contains('Future<void> reset()'));
    });

    test('no-param reducer still calls _callReducer', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/reducers.dart').readAsString();
      expect(code, contains("_callReducer('reset'"));
    });

    test('no-param reducer has callback method', () async {
      final generator = DartGenerator(schema: schema, outputDir: outDir);
      await generator.generate();

      final code = await File('$outDir/reducers.dart').readAsString();
      expect(code, contains('void onReset(ReducerCallback callback)'));
    });
  });
}

// CLI tool for generating typed Dart code from a SpacetimeDB module schema.
//
// Usage:
//   dart run spacetimedb_sdk:generate -d my_database -o lib/src/generated
//   dart run spacetimedb_sdk:generate -h http://my-server:3000 -d my_db -o out

import 'dart:io';

import 'package:args/args.dart';
import 'package:spacetimedb_sdk/src/codegen/schema.dart';
import 'package:spacetimedb_sdk/src/codegen/generator.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'host',
      abbr: 'h',
      defaultsTo: 'http://localhost:3000',
      help: 'SpacetimeDB host URL.',
    )
    ..addOption(
      'database',
      abbr: 'd',
      help: 'Database/module name or address.',
      mandatory: true,
    )
    ..addOption(
      'out-dir',
      abbr: 'o',
      help: 'Output directory for generated code.',
      mandatory: true,
    )
    ..addFlag(
      'help',
      negatable: false,
      help: 'Show this help message.',
    );

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln('Usage: dart run spacetimedb_sdk:generate [options]');
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (results['help'] as bool) {
    stdout.writeln('SpacetimeDB Dart SDK Code Generator');
    stdout.writeln();
    stdout.writeln('Fetches a module schema from a SpacetimeDB server and');
    stdout.writeln('generates typed Dart code for tables, reducers, and types.');
    stdout.writeln();
    stdout.writeln('Usage: dart run spacetimedb_sdk:generate [options]');
    stdout.writeln();
    stdout.writeln(parser.usage);
    exit(0);
  }

  final host = results['host'] as String;
  final database = results['database'] as String;
  final outDir = results['out-dir'] as String;

  stdout.writeln('Fetching schema from $host for database "$database"...');

  final ModuleSchema schema;
  try {
    schema = await ModuleSchema.fetch(host, database);
  } catch (e) {
    stderr.writeln('Failed to fetch schema: $e');
    exit(1);
  }

  stdout.writeln('Found ${schema.tables.length} table(s), '
      '${schema.reducers.length} reducer(s), '
      '${schema.typespace.length} type(s) in typespace.');

  stdout.writeln('Generating Dart code to $outDir ...');

  try {
    final generator = DartGenerator(schema: schema, outputDir: outDir);
    await generator.generate();
  } catch (e, st) {
    stderr.writeln('Code generation failed: $e');
    stderr.writeln(st);
    exit(1);
  }

  stdout.writeln('Done! Generated files:');

  final dir = Directory(outDir);
  if (dir.existsSync()) {
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        stdout.writeln('  ${entity.path}');
      }
    }
  }
}

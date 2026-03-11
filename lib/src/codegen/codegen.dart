/// SpacetimeDB Dart SDK code generation library.
///
/// Provides schema parsing and Dart code generation for SpacetimeDB modules.
/// Use [ModuleSchema.fetch] to retrieve a module's schema from a SpacetimeDB
/// server, then pass it to [DartGenerator] to produce typed Dart source files.
library;

export 'generator.dart';
export 'schema.dart';

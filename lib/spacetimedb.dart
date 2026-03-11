/// SpacetimeDB Dart SDK
///
/// A client SDK for connecting to SpacetimeDB databases,
/// subscribing to data changes, and calling reducers.
library;

// BSATN serialization
export 'src/bsatn/types.dart';
export 'src/bsatn/encoder.dart';
export 'src/bsatn/decoder.dart';

// Identity types
export 'src/identity.dart';

// Protocol messages
export 'src/protocol/client_messages.dart';
export 'src/protocol/server_messages.dart';
export 'src/protocol/types.dart';

// Client
export 'src/client/spacetimedb_client.dart';
export 'src/client/table_cache.dart';
export 'src/client/subscription.dart';
export 'src/client/connection.dart';
export 'src/client/reconnect.dart';

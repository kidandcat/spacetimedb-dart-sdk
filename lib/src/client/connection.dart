import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/client_messages.dart';
import '../protocol/server_messages.dart';

/// Low-level WebSocket connection to a SpacetimeDB instance.
///
/// Handles binary framing, protocol negotiation, and message
/// encoding/decoding over the `v1.bsatn.spacetimedb` sub-protocol.
class SpacetimeConnection {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final _messageController = StreamController<ServerMessage>.broadcast();
  final _errorController = StreamController<dynamic>.broadcast();

  bool _closed = false;

  /// Stream of decoded server messages.
  Stream<ServerMessage> get messages => _messageController.stream;

  /// Stream of connection-level errors (decode failures, transport errors,
  /// or the string `'Connection closed'` when the WebSocket closes).
  Stream<dynamic> get errors => _errorController.stream;

  /// Whether the WebSocket is currently open.
  bool get isConnected => _channel != null && !_closed;

  /// Opens a WebSocket connection to the SpacetimeDB server at [uri].
  ///
  /// The [uri] should point to the database subscribe endpoint, e.g.
  /// `http://localhost:3000/v1/database/mydb/subscribe`.
  /// HTTP(S) schemes are automatically converted to WS(S).
  ///
  /// If [token] is provided it is sent as a Bearer authorization header
  /// (where supported by the WebSocket implementation).
  Future<void> connect({
    required Uri uri,
    String? token,
  }) async {
    // Convert http(s) to ws(s).
    var wsUri = uri;
    if (uri.scheme == 'http') {
      wsUri = uri.replace(scheme: 'ws');
    } else if (uri.scheme == 'https') {
      wsUri = uri.replace(scheme: 'wss');
    }

    // Append query parameters.
    final queryParams = Map<String, String>.from(wsUri.queryParameters);
    queryParams['compression'] = 'None';
    // Pass the token as a query parameter for reliable auth across all
    // WebSocket implementations (not all support custom headers).
    if (token != null && token.isNotEmpty) {
      queryParams['token'] = token;
    }
    wsUri = wsUri.replace(queryParameters: queryParams);

    _channel = WebSocketChannel.connect(
      wsUri,
      protocols: ['v1.bsatn.spacetimedb'],
    );

    await _channel!.ready;
    _closed = false;

    _subscription = _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
  }

  /// Sends a [ClientMessage] over the WebSocket as BSATN bytes.
  ///
  /// Throws [StateError] if the connection is not open.
  void send(ClientMessage message) {
    if (!isConnected) {
      throw StateError('Cannot send: WebSocket is not connected');
    }
    _channel!.sink.add(message.toBytes());
  }

  /// Closes the WebSocket connection gracefully.
  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  /// Releases all stream controllers. Call this when the connection will not
  /// be reused.
  void dispose() {
    _closed = true;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _messageController.close();
    _errorController.close();
  }

  // ---------------------------------------------------------------------------
  // Internal WebSocket event handlers
  // ---------------------------------------------------------------------------

  void _onData(dynamic data) {
    try {
      Uint8List bytes;
      if (data is Uint8List) {
        bytes = data;
      } else if (data is List<int>) {
        bytes = Uint8List.fromList(data);
      } else {
        // Skip non-binary frames (e.g. text).
        return;
      }
      final msg = ServerMessage.decode(bytes);
      _messageController.add(msg);
    } catch (e) {
      _errorController.add(e);
    }
  }

  void _onError(dynamic error) {
    _errorController.add(error);
  }

  void _onDone() {
    _closed = true;
    _errorController.add('Connection closed');
  }
}

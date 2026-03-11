/// The lifecycle state of a subscription.
enum SubscriptionState {
  /// The subscribe message has been sent but the server has not yet confirmed.
  pending,

  /// The server has confirmed the subscription and initial rows were applied.
  active,

  /// The subscription has been cleanly ended (unsubscribed).
  ended,

  /// The server reported an error for this subscription.
  error,
}

/// Handle returned when subscribing to one or more SQL queries.
///
/// Provides lifecycle callbacks and state inspection for the subscription.
///
/// ```dart
/// client.subscribe(['SELECT * FROM Player'])
///   .onApplied(() => print('Ready!'))
///   .onError((e) => print('Subscription failed: $e'));
/// ```
class SubscriptionHandle {
  /// The client-assigned request ID for correlation with server responses.
  final int requestId;

  /// The client-assigned query ID for this subscription set.
  final int queryId;

  /// The SQL queries included in this subscription.
  final List<String> queries;

  SubscriptionState _state = SubscriptionState.pending;

  void Function()? _onApplied;
  void Function(String error)? _onError;
  void Function()? _onEnded;

  /// The current lifecycle state.
  SubscriptionState get state => _state;

  /// Whether the subscription is actively receiving updates.
  bool get isActive => _state == SubscriptionState.active;

  /// Whether the subscription has ended (unsubscribed or errored).
  bool get isEnded =>
      _state == SubscriptionState.ended || _state == SubscriptionState.error;

  /// Creates a subscription handle. Typically called internally by the client.
  SubscriptionHandle({
    required this.requestId,
    required this.queryId,
    required this.queries,
  });

  /// Registers a callback invoked when the subscription is applied
  /// (initial rows received from server).
  SubscriptionHandle onApplied(void Function() callback) {
    _onApplied = callback;
    return this;
  }

  /// Registers a callback invoked when the subscription encounters an error.
  SubscriptionHandle onError(void Function(String) callback) {
    _onError = callback;
    return this;
  }

  /// Registers a callback invoked when the subscription is cleanly ended.
  SubscriptionHandle onEnded(void Function() callback) {
    _onEnded = callback;
    return this;
  }

  /// Marks this subscription as applied. Called internally by the client
  /// when a [SubscribeApplied] message is received.
  void markApplied() {
    _state = SubscriptionState.active;
    _onApplied?.call();
  }

  /// Marks this subscription as errored. Called internally by the client
  /// when a [SubscriptionErrorMsg] message is received.
  void markError(String error) {
    _state = SubscriptionState.error;
    _onError?.call(error);
  }

  /// Marks this subscription as ended. Called internally by the client
  /// when an [UnsubscribeAppliedMsg] message is received.
  void markEnded() {
    _state = SubscriptionState.ended;
    _onEnded?.call();
  }
}

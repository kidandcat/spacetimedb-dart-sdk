import 'dart:async';
import 'dart:math';

/// Exponential-backoff reconnection strategy with jitter.
///
/// Computes successive delays using the formula:
///
///     delay = min(initialDelay * multiplier^attempt, maxDelay) + jitter
///
/// Jitter is a random value between 0 and 25 % of the computed delay to
/// prevent thundering-herd effects when many clients reconnect simultaneously.
class ReconnectStrategy {
  /// The delay before the first reconnect attempt.
  final Duration initialDelay;

  /// The maximum delay between reconnect attempts.
  final Duration maxDelay;

  /// The multiplier applied to the delay after each failed attempt.
  final double multiplier;

  /// The maximum number of reconnect attempts. `0` means unlimited.
  final int maxAttempts;

  final Random _random = Random();

  int _attempts = 0;
  Timer? _timer;
  bool _enabled = true;

  ReconnectStrategy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.maxAttempts = 0,
  });

  /// The number of reconnect attempts made since the last successful
  /// connection (or since [reset] was called).
  int get attempts => _attempts;

  /// Whether this strategy is currently enabled.
  bool get isEnabled => _enabled;

  /// The delay that will be used for the next reconnect attempt.
  Duration get nextDelay {
    final baseMs =
        initialDelay.inMilliseconds * pow(multiplier, _attempts).toDouble();
    final cappedMs = baseMs.clamp(0, maxDelay.inMilliseconds).toInt();
    // Add 0-25 % jitter.
    final jitterMs = (_random.nextDouble() * 0.25 * cappedMs).round();
    return Duration(milliseconds: cappedMs + jitterMs);
  }

  /// Whether another reconnect attempt is allowed.
  bool get canRetry =>
      _enabled && (maxAttempts == 0 || _attempts < maxAttempts);

  /// Schedules a reconnect attempt.
  ///
  /// [reconnect] is the async function that performs the actual connection.
  /// On success, the attempt counter is reset. On failure, the strategy
  /// automatically schedules another attempt (if [canRetry] is still true).
  void scheduleReconnect(
    Future<void> Function() reconnect, {
    void Function(int attempt, Duration delay)? onReconnecting,
    void Function()? onReconnected,
    void Function(Object error)? onFailed,
  }) {
    if (!canRetry) {
      onFailed
          ?.call(Exception('Max reconnect attempts ($maxAttempts) reached'));
      return;
    }

    final delay = nextDelay;
    _attempts++;
    onReconnecting?.call(_attempts, delay);

    _timer = Timer(delay, () async {
      try {
        await reconnect();
        _attempts = 0;
        onReconnected?.call();
      } catch (e) {
        onFailed?.call(e);
        // Chain another attempt.
        scheduleReconnect(
          reconnect,
          onReconnecting: onReconnecting,
          onReconnected: onReconnected,
          onFailed: onFailed,
        );
      }
    });
  }

  /// Resets the attempt counter and cancels any pending timer.
  void reset() {
    _attempts = 0;
    _timer?.cancel();
    _timer = null;
  }

  /// Disables reconnection and cancels any pending timer.
  void disable() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Re-enables reconnection (does not reset the attempt counter).
  void enable() {
    _enabled = true;
  }
}

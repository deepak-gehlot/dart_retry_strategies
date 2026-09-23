import 'dart:async';

enum CircuitState { closed, open, halfOpen }

/// Circuit Breaker pattern for preventing cascading failures.
///
/// States:
/// - **Closed** (normal): Requests pass through normally
/// - **Open** (failure threshold reached): Fail fast without executing
/// - **Half-Open** (testing recovery): Allow one request to test if service recovered
///
/// Typical flow:
/// ```
/// Closed --(failures >= threshold)--> Open
/// Open  --(timeout passes)--> Half-Open
/// Half-Open --(success)--> Closed
/// Half-Open --(failure)--> Open
/// ```
///
/// Usage:
/// ```dart
/// final breaker = CircuitBreaker(failureThreshold: 5);
///
/// try {
///   final result = await breaker.execute(() => callThirdPartyAPI());
/// } on CircuitBreakerException {
///   // Circuit is open - fail fast
/// }
/// ```
class CircuitBreaker {
  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;

  /// Number of consecutive failures before opening circuit.
  final int failureThreshold;

  /// Duration to wait before attempting recovery (half-open state).
  final Duration timeout;

  /// Callback when state changes (for monitoring/logging).
  void Function(CircuitState oldState, CircuitState newState)? onStateChange;

  CircuitBreaker({
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 60),
    this.onStateChange,
  }) : assert(failureThreshold > 0, 'failureThreshold must be > 0');

  /// Current circuit state.
  CircuitState get state => _state;

  /// Number of consecutive failures recorded.
  int get failureCount => _failureCount;

  /// Execute a function with circuit breaker protection.
  ///
  /// - If circuit is open and timeout hasn't passed, fails immediately
  /// - If circuit is open and timeout has passed, enters half-open state
  /// - In half-open state, executes the function to test recovery
  /// - Success resets to closed; failure reopens circuit
  Future<T> execute<T>(Future<T> Function() fn) async {
    // Check if we should open the circuit
    if (_state == CircuitState.open) {
      final timeSinceFailure = DateTime.now().difference(_lastFailureTime!);
      if (timeSinceFailure > timeout) {
        _setStateIfChanged(CircuitState.halfOpen);
      } else {
        throw CircuitBreakerException(
          'Circuit is open. Retry after ${timeout.inSeconds}s',
        );
      }
    }

    try {
      final result = await fn();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  void _onSuccess() {
    if (_state == CircuitState.halfOpen) {
      _setStateIfChanged(CircuitState.closed);
      _failureCount = 0;
    }
  }

  void _onFailure() {
    _lastFailureTime = DateTime.now();
    _failureCount++;

    if (_state == CircuitState.halfOpen) {
      _setStateIfChanged(CircuitState.open);
    } else if (_failureCount >= failureThreshold) {
      _setStateIfChanged(CircuitState.open);
    }
  }

  void _setStateIfChanged(CircuitState newState) {
    if (_state != newState) {
      final oldState = _state;
      _state = newState;
      onStateChange?.call(oldState, newState);
    }
  }

  /// Resets circuit to closed state (useful for testing or manual intervention).
  void reset() {
    _setStateIfChanged(CircuitState.closed);
    _failureCount = 0;
    _lastFailureTime = null;
  }

  /// Gets time remaining until half-open attempt (only if open).
  Duration? get timeUntilHalfOpen {
    if (_state != CircuitState.open || _lastFailureTime == null) {
      return null;
    }
    final timeSinceFailure = DateTime.now().difference(_lastFailureTime!);
    final remaining = timeout.inMilliseconds - timeSinceFailure.inMilliseconds;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  @override
  String toString() =>
      'CircuitBreaker(state: $_state, failures: $_failureCount/$failureThreshold)';
}

/// Exception thrown when circuit breaker is open.
class CircuitBreakerException implements Exception {
  final String message;

  CircuitBreakerException(this.message);

  @override
  String toString() => 'CircuitBreakerException: $message';
}

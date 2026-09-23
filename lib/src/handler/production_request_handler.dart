import 'dart:async';
import '../retry/retry_with_backoff.dart';
import '../retry/retry_config.dart';
import '../circuit_breaker/circuit_breaker.dart';
import '../locks/semaphore.dart';
import '../cancellation/cancellation_token.dart';

/// Production-grade HTTP request handler combining all resilience patterns.
///
/// Coordinates:
/// 1. Cancellation tokens for cleanup
/// 2. Concurrency semaphore for connection pool management
/// 3. Circuit breaker for fail-fast on service failures
/// 4. Retry with exponential backoff for transient failures
///
/// Example:
/// ```dart
/// final handler = ProductionRequestHandler();
/// final token = CancellationToken();
///
/// try {
///   final response = await handler.handleRequest(
///     () => http.get(Uri.parse('https://api.example.com/data')),
///     token: token,
///     retryable: true,
///   );
///   print('Success: $response');
/// } on OperationCanceledException {
///   print('Request was cancelled');
/// } catch (e) {
///   print('Request failed: $e');
/// }
///
/// // Later, if user navigates away:
/// token.cancel();
/// ```
class ProductionRequestHandler {
  final RetryConfig retryConfig;
  final CircuitBreaker circuitBreaker;
  final Semaphore concurrencySemaphore;

  /// Optional callback for monitoring retry attempts.
  void Function(int attempt, Duration delay)? onRetry;

  /// Optional callback for circuit breaker state changes.
  void Function(CircuitState oldState, CircuitState newState)?
      onCircuitStateChange;

  /// Creates a production request handler with defaults.
  ///
  /// - Retry: max 3 attempts, 100ms initial delay, 2x backoff, 30s cap
  /// - Circuit Breaker: 5 failure threshold, 60s timeout
  /// - Concurrency: max 10 concurrent requests
  ProductionRequestHandler({
    RetryConfig? retryConfig,
    CircuitBreaker? circuitBreaker,
    int maxConcurrentRequests = 10,
    this.onRetry,
    this.onCircuitStateChange,
  })  : retryConfig = retryConfig ?? RetryConfig(),
        circuitBreaker = circuitBreaker ?? CircuitBreaker(),
        concurrencySemaphore = Semaphore(maxConcurrentRequests) {
    // Wire up optional callbacks
    if (onCircuitStateChange != null) {
      this.circuitBreaker.onStateChange = onCircuitStateChange;
    }
  }

  /// Handles an HTTP request with full resilience stack.
  ///
  /// Execution order:
  /// 1. Check if already cancelled
  /// 2. Enforce concurrency bound (semaphore)
  /// 3. Check service health (circuit breaker)
  /// 4. Retry with backoff if transient failure
  ///
  /// Parameters:
  /// - [fn]: Async function to execute
  /// - [token]: Optional cancellation token for cleanup
  /// - [retryable]: Whether to retry on transient failures
  ///
  /// Throws:
  /// - OperationCanceledException if cancelled
  /// - CircuitBreakerException if circuit is open
  /// - Original exception if non-retryable or retries exhausted
  Future<T> handleRequest<T>(
    Future<T> Function() fn, {
    CancellationToken? token,
    bool retryable = true,
  }) async {
    // Check if already cancelled
    if (token?.isCancelled ?? false) {
      throw OperationCanceledException('Cancelled before execution');
    }

    // Enforce concurrency bound
    return concurrencySemaphore.acquire(() async {
      // Double-check cancellation after acquiring semaphore
      if (token?.isCancelled ?? false) {
        throw OperationCanceledException('Cancelled while waiting for semaphore');
      }

      // Use circuit breaker for fail-fast
      return circuitBreaker.execute(() async {
        if (retryable) {
          // Retry with exponential backoff
          return retryWithBackoff(
            fn,
            config: retryConfig,
            onRetry: onRetry,
          );
        } else {
          // Single attempt
          return fn();
        }
      });
    });
  }

  /// Gets diagnostic info about handler state.
  DiagnosticInfo getDiagnostics() => DiagnosticInfo(
        circuitState: circuitBreaker.state,
        circuitFailureCount: circuitBreaker.failureCount,
        concurrentRequests: concurrencySemaphore.available,
        waitingRequests: concurrencySemaphore.waitingCount,
      );
}

/// Diagnostic information about handler state.
class DiagnosticInfo {
  final CircuitState circuitState;
  final int circuitFailureCount;
  final int concurrentRequests;
  final int waitingRequests;

  DiagnosticInfo({
    required this.circuitState,
    required this.circuitFailureCount,
    required this.concurrentRequests,
    required this.waitingRequests,
  });

  @override
  String toString() => '''DiagnosticInfo(
  circuit: $circuitState (failures: $circuitFailureCount),
  concurrent: $concurrentRequests active,
  waiting: $waitingRequests
)''';
}

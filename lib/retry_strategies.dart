/// Production-grade retry strategies, circuit breakers, locks, and cancellation
/// for resilient Dart and Flutter applications.
///
/// This library provides battle-tested patterns for:
/// - Exponential backoff with jitter
/// - Circuit breaker for fail-fast resilience
/// - Mutex locks for mutual exclusion
/// - Semaphores for bounded concurrency
/// - Cancellation tokens for cleanup
///
/// Start with [ProductionRequestHandler] to get all patterns combined,
/// or use individual components as needed.
library retry_strategies;

// Retry patterns
export 'src/retry/retry_config.dart';
export 'src/retry/retry_with_backoff.dart';
export 'src/retry/error_classifier.dart';

// Circuit breaker
export 'src/circuit_breaker/circuit_breaker.dart';

// Locks
export 'src/locks/mutex_lock.dart';
export 'src/locks/semaphore.dart';

// Cancellation
export 'src/cancellation/cancellation_token.dart';

// Production handler
export 'src/handler/production_request_handler.dart';

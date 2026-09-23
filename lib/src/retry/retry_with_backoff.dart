import 'dart:async';
import 'retry_config.dart';
import 'error_classifier.dart';

/// Retry a function with exponential backoff and jitter.
///
/// Retries [fn] up to [config.maxRetries] times, backing off exponentially
/// with full jitter between attempts.
///
/// Parameters:
/// - [fn]: Async function to retry
/// - [config]: Retry configuration (backoff strategy)
/// - [onRetry]: Optional callback fired before each retry delay
/// - [shouldRetry]: Optional predicate to decide whether to retry given error
///
/// Throws: The last exception if all retries are exhausted
///
/// Example:
/// ```dart
/// final result = await retryWithBackoff(
///   () => http.get(Uri.parse('https://api.example.com/data')),
///   config: RetryConfig(maxRetries: 3),
///   onRetry: (attempt, delay) {
///     print('Attempt $attempt: waiting ${delay.inMilliseconds}ms');
///   },
/// );
/// ```
Future<T> retryWithBackoff<T>(
  Future<T> Function() fn, {
  required RetryConfig config,
  void Function(int attempt, Duration delay)? onRetry,
  bool Function(dynamic error)? shouldRetry,
}) async {
  dynamic lastError;

  for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (e) {
      lastError = e;

      // Check if we should retry this error
      if (shouldRetry != null && !shouldRetry(e)) {
        rethrow;
      }

      // If this was the last attempt, fail
      if (attempt == config.maxRetries) {
        rethrow;
      }

      // Calculate backoff and wait
      final delay = config.getDelay(attempt);
      onRetry?.call(attempt + 1, delay);
      await Future.delayed(delay);
    }
  }

  // Should not reach here, but just in case
  throw lastError ?? StateError('Retry exhausted with no error captured');
}

/// Retry with smart error classification.
///
/// Automatically retries transient errors (timeouts, network issues, 5xx, 429).
/// Immediately fails on permanent errors (4xx except 429).
///
/// Example:
/// ```dart
/// try {
///   final response = await retryWithSmartClassification(
///     () => http.get(url),
///     config: RetryConfig(),
///   );
/// } on PermanentFailureException {
///   // 401, 403, 404 - won't retry
/// }
/// ```
Future<T> retryWithSmartClassification<T>(
  Future<T> Function() fn, {
  required RetryConfig config,
  void Function(int attempt, Duration delay)? onRetry,
}) =>
    retryWithBackoff<T>(
      fn,
      config: config,
      onRetry: onRetry,
      shouldRetry: (error) {
        final errorType = classifyError(error);
        return errorType != ErrorType.permanent;
      },
    );

/// Exception for non-retryable errors.
class PermanentFailureException implements Exception {
  final String message;
  final dynamic originalError;

  PermanentFailureException(this.message, [this.originalError]);

  @override
  String toString() => 'PermanentFailureException: $message';
}

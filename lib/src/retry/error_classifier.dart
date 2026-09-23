import 'dart:async';
import 'dart:io';

/// Classifies errors into transient (retry) or permanent (fail immediately) categories.
enum ErrorType {
  /// Transient error - should retry with backoff (network timeout, 5xx, 429)
  transient,

  /// Permanent error - should not retry (4xx except 429, auth failures)
  permanent,

  /// Timeout error - special transient case
  timeout,
}

/// Classifies an error into transient or permanent category.
///
/// Transient errors (should retry):
/// - TimeoutException
/// - SocketException
/// - HTTP 408 (Request Timeout)
/// - HTTP 429 (Too Many Requests)
/// - HTTP 500+ (Server errors)
///
/// Permanent errors (should NOT retry):
/// - HTTP 400 (Bad Request)
/// - HTTP 401 (Unauthorized)
/// - HTTP 403 (Forbidden)
/// - HTTP 404 (Not Found)
///
/// Default: Transient (conservative - prefer retry over fail)
ErrorType classifyError(dynamic error, [int? statusCode]) {
  // TimeoutException
  if (error is TimeoutException) {
    return ErrorType.timeout;
  }

  // SocketException (network errors)
  if (error is SocketException) {
    return ErrorType.transient;
  }

  // HttpException or any error with statusCode
  if (statusCode != null) {
    return _classifyByStatusCode(statusCode);
  }

  // Extract status code from error message if available
  if (error is Exception) {
    final message = error.toString().toLowerCase();

    // Check for status codes in error message
    if (message.contains('401') || message.contains('unauthorized')) {
      return ErrorType.permanent;
    }
    if (message.contains('403') || message.contains('forbidden')) {
      return ErrorType.permanent;
    }
    if (message.contains('404') || message.contains('not found')) {
      return ErrorType.permanent;
    }
    if (message.contains('429') || message.contains('too many')) {
      return ErrorType.transient;
    }
    if (message.contains('5') && message.contains('error')) {
      return ErrorType.transient;
    }
  }

  // Default: conservative - retry unknown errors
  return ErrorType.transient;
}

/// Classifies HTTP status code into error type.
ErrorType _classifyByStatusCode(int statusCode) {
  // Permanent client errors (4xx) - except 408 and 429
  if (statusCode >= 400 && statusCode < 500) {
    if (statusCode == 408 || statusCode == 429) {
      return ErrorType.transient;
    }
    return ErrorType.permanent;
  }

  // Server errors (5xx) are transient
  if (statusCode >= 500) {
    return ErrorType.transient;
  }

  // Success codes are not errors
  if (statusCode >= 200 && statusCode < 300) {
    return ErrorType.transient; // Not an error
  }

  // Redirects (3xx) - generally should be handled by HTTP client
  if (statusCode >= 300 && statusCode < 400) {
    return ErrorType.transient;
  }

  // Unknown status codes - be conservative
  return ErrorType.transient;
}

/// Checks if an error is retryable based on classification.
bool isRetryable(dynamic error, [int? statusCode]) =>
    classifyError(error, statusCode) != ErrorType.permanent;

/// Checks if an error is a permanent failure (non-retryable).
bool isPermanent(dynamic error, [int? statusCode]) =>
    classifyError(error, statusCode) == ErrorType.permanent;

/// Error classification lookup table for reference.
const errorClassificationTable = {
  // HTTP Status Codes
  'GET': 'Always retryable (idempotent)',
  'HEAD': 'Always retryable (idempotent)',
  'PUT': 'Usually retryable (idempotent if same body)',
  'DELETE': 'Usually retryable (idempotent)',
  'POST': 'Only if idempotency key present',
  'PATCH': 'Only if idempotency key present',
  // Status Codes
  '400 Bad Request': 'Permanent (client error)',
  '401 Unauthorized': 'Permanent (auth failure)',
  '403 Forbidden': 'Permanent (permission denied)',
  '404 Not Found': 'Permanent (resource missing)',
  '408 Request Timeout': 'Transient (retry with backoff)',
  '429 Too Many Requests': 'Transient (retry with exponential backoff)',
  '500 Internal Server Error': 'Transient (server error)',
  '502 Bad Gateway': 'Transient (gateway error)',
  '503 Service Unavailable': 'Transient (service down)',
  '504 Gateway Timeout': 'Transient (gateway timeout)',
  // Exceptions
  'TimeoutException': 'Transient (network timeout)',
  'SocketException': 'Transient (network error)',
  'FormatException': 'Permanent (response malformed)',
};

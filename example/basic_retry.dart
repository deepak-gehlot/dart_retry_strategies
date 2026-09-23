import 'dart:io';
import 'package:retry_strategies/retry_strategies.dart';

/// Basic example: Retry a failing operation with exponential backoff.
/// 
/// Simulates network failures that succeed on retry.
Future<void> main() async {
  print('=== Basic Retry Example ===\n');

  int attemptCount = 0;

  try {
    print('Starting request...');
    final result = await retryWithBackoff(
      () async {
        attemptCount++;
        print('Attempt $attemptCount');

        // Simulate transient failures
        if (attemptCount < 3) {
          throw SocketException('Network error');
        }

        return 'Success! Data received.';
      },
      config: RetryConfig(
        maxRetries: 3,
        initialDelay: Duration(milliseconds: 100),
        backoffMultiplier: 2.0,
      ),
      onRetry: (attempt, delay) {
        print('  → Retry $attempt after ${delay.inMilliseconds}ms');
      },
    );

    print('\n✓ Result: $result');
    print('Completed in $attemptCount attempts');
  } catch (e) {
    print('\n✗ Failed: $e');
  }
}

/// Expected output:
/// ```
/// === Basic Retry Example ===
///
/// Starting request...
/// Attempt 1
///   → Retry 1 after XXms
/// Attempt 2
///   → Retry 2 after XXms
/// Attempt 3
///
/// ✓ Result: Success! Data received.
/// Completed in 3 attempts
/// ```

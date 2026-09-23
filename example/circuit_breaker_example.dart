import 'dart:math';
import 'package:retry_strategies/retry_strategies.dart';

/// Circuit Breaker Example: Fail fast when service is down.
///
/// Demonstrates:
/// - Closed state (normal operation)
/// - Open state (service failing, reject requests)
/// - Half-Open state (testing recovery)
Future<void> main() async {
  print('=== Circuit Breaker Example ===\n');

  final breaker = CircuitBreaker(
    failureThreshold: 3,
    timeout: Duration(seconds: 2),
  );

  // Monitor state changes
  breaker.onStateChange = (oldState, newState) {
    print('🔄 Circuit: $oldState → $newState');
  };

  int callCount = 0;

  for (int i = 0; i < 10; i++) {
    try {
      print('\nCall $i...');

      await breaker.execute(() async {
        callCount++;

        // First 5 calls fail (simulate service down)
        if (callCount <= 5) {
          print('  Simulated failure #$callCount');
          throw Exception('Service error');
        }

        // After 5 calls, succeed (service recovers)
        print('  Success!');
        return 'OK';
      });
    } on CircuitBreakerException catch (e) {
      print('  ❌ ${e.message}');
    } catch (e) {
      print('  ✗ Error: $e');
    }

    // Small delay between calls to observe state transitions
    await Future.delayed(Duration(milliseconds: 600));
  }

  print('\n\nFinal state: ${breaker.state}');
  print('Failure count: ${breaker.failureCount}');
}

/// Expected flow:
/// ```
/// Call 0...
///   Simulated failure #1
/// 🔄 Circuit: closed → closed  (1st failure)
///
/// Call 1...
///   Simulated failure #2
/// 🔄 Circuit: closed → closed  (2nd failure)
///
/// Call 2...
///   Simulated failure #3
/// 🔄 Circuit: closed → open    (threshold reached!)
///
/// Call 3...
///   ❌ Circuit is open. Retry after 2s
///
/// [wait 2 seconds]
///
/// Call 4...
/// 🔄 Circuit: open → halfOpen  (test recovery)
///   Simulated failure #4
/// 🔄 Circuit: halfOpen → open  (still failing)
///
/// [wait 2 seconds]
///
/// Call 5...
/// 🔄 Circuit: open → halfOpen  (test recovery again)
///   Success!
/// 🔄 Circuit: halfOpen → closed (recovered!)
///
/// Call 6...
///   Success!
/// ```

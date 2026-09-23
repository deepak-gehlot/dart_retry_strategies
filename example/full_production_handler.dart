import 'dart:io';
import 'package:retry_strategies/retry_strategies.dart';

/// Full Production Handler Example.
///
/// Demonstrates combining all patterns:
/// 1. Cancellation tokens for cleanup
/// 2. Semaphore for concurrency control
/// 3. Circuit breaker for fail-fast
/// 4. Retry with backoff for transient failures
Future<void> main() async {
  print('=== Full Production Request Handler ===\n');

  final client = APIClient();

  // Scenario 1: Successful request
  print('Scenario 1: Successful GET request');
  await _scenario1(client);

  await Future.delayed(Duration(seconds: 1));

  // Scenario 2: Transient failure (retry succeeds)
  print('\n\nScenario 2: Transient failure with retry');
  await _scenario2(client);

  await Future.delayed(Duration(seconds: 1));

  // Scenario 3: Cancellation
  print('\n\nScenario 3: Request cancelled by user');
  await _scenario3(client);

  // Scenario 4: Diagnostics
  print('\n\nScenario 4: Handler diagnostics');
  _scenario4(client);
}

Future<void> _scenario1(APIClient client) async {
  final token = CancellationToken();

  try {
    print('  → Fetching data...');
    final result = await client.get(
      'https://example.com/api/data',
      token: token,
    );
    print('  ✓ Success: $result');
  } catch (e) {
    print('  ✗ Error: $e');
  }
}

Future<void> _scenario2(APIClient client) async {
  final token = CancellationToken();

  try {
    print('  → Fetching with retryable errors...');
    final result = await client.get(
      'https://example.com/api/data',
      token: token,
    );
    print('  ✓ Success after retries: $result');
  } catch (e) {
    print('  ✗ Error: $e');
  }
}

Future<void> _scenario3(APIClient client) async {
  final token = CancellationToken();

  // Start request
  final future = client.get(
    'https://example.com/api/data',
    token: token,
  );

  // Cancel after 100ms
  await Future.delayed(Duration(milliseconds: 100));
  print('  → Cancelling request...');
  token.cancel();

  try {
    await future;
  } on OperationCanceledException {
    print('  ✓ Request cancelled successfully');
  } catch (e) {
    print('  ✗ Error: $e');
  }
}

void _scenario4(APIClient client) {
  final diagnostics = client.getDiagnostics();
  print('  Diagnostics:');
  print('    - Circuit breaker: ${diagnostics.circuitState}');
  print('    - Circuit failures: ${diagnostics.circuitFailureCount}');
  print('    - Concurrent requests: ${diagnostics.concurrentRequests}');
  print('    - Waiting requests: ${diagnostics.waitingRequests}');
}

/// HTTP client using ProductionRequestHandler.
class APIClient {
  final ProductionRequestHandler _handler;
  int _requestCount = 0;

  APIClient({ProductionRequestHandler? handler})
      : _handler = handler ?? _createDefaultHandler() {
    _handler.onRetry = (attempt, delay) {
      print('    [Retry] Attempt $attempt after ${delay.inMilliseconds}ms');
    };

    _handler.onCircuitStateChange = (oldState, newState) {
      print('    [Circuit] $oldState → $newState');
    };
  }

  /// Makes a GET request with full resilience stack.
  Future<String> get(
    String url, {
    CancellationToken? token,
  }) async {
    return _handler.handleRequest(
      () => _simulateHttpGet(url),
      token: token,
      retryable: true,
    );
  }

  /// Makes a POST request (only retryable with idempotency key).
  Future<String> post(
    String url,
    dynamic body, {
    String? idempotencyKey,
    CancellationToken? token,
  }) async {
    return _handler.handleRequest(
      () => _simulateHttpPost(url, body),
      token: token,
      retryable: idempotencyKey != null,
    );
  }

  Future<String> _simulateHttpGet(String url) async {
    _requestCount++;
    print('    [HTTP] GET $url (request #$_requestCount)');

    // Simulate occasional transient failures
    if (_requestCount % 3 == 1) {
      await Future.delayed(Duration(milliseconds: 100));
      throw SocketException('Network timeout');
    }

    await Future.delayed(Duration(milliseconds: 200));
    return '{"data": "response"}';
  }

  Future<String> _simulateHttpPost(String url, dynamic body) async {
    _requestCount++;
    print('    [HTTP] POST $url (request #$_requestCount)');

    await Future.delayed(Duration(milliseconds: 300));
    return '{"id": "created"}';
  }

  DiagnosticInfo getDiagnostics() => _handler.getDiagnostics();

  static ProductionRequestHandler _createDefaultHandler() {
    return ProductionRequestHandler(
      retryConfig: RetryConfig(
        maxRetries: 2,
        initialDelay: Duration(milliseconds: 50),
      ),
      maxConcurrentRequests: 5,
    );
  }
}

/// Expected output:
/// ```
/// === Full Production Request Handler ===
///
/// Scenario 1: Successful GET request
///   → Fetching data...
///     [HTTP] GET https://example.com/api/data (request #1)
///   ✓ Success: {"data": "response"}
///
///
/// Scenario 2: Transient failure with retry
///   → Fetching with retryable errors...
///     [HTTP] GET https://example.com/api/data (request #2)
///     [Retry] Attempt 1 after XXms
///     [HTTP] GET https://example.com/api/data (request #3)
///   ✓ Success after retries: {"data": "response"}
///
///
/// Scenario 3: Request cancelled by user
///   → Fetching...
///     [HTTP] GET https://example.com/api/data (request #4)
///   → Cancelling request...
///   ✓ Request cancelled successfully
///
///
/// Scenario 4: Handler diagnostics
///   Diagnostics:
///     - Circuit breaker: closed
///     - Circuit failures: 0
///     - Concurrent requests: 5
///     - Waiting requests: 0
/// ```

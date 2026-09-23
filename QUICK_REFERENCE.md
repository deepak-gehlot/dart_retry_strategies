# Dart Retry Strategies - Quick Reference

## Installation

```yaml
dependencies:
  retry_strategies:
    path: ./
```

---

## 1. Basic Retry

```dart
import 'package:retry_strategies/retry_strategies.dart';

final result = await retryWithBackoff(
  () => fetchData(),
  config: RetryConfig(maxRetries: 3),
);
```

**Defaults**: 100ms initial, 2.0x backoff, 30s cap, 3 retries

---

## 2. Smart Retry (Auto Error Classification)

```dart
final result = await retryWithSmartClassification(
  () => http.get(url),
  config: RetryConfig(),
);
// Skips retry for 401, 403, 404
// Retries 5xx, timeouts, network errors
```

---

## 3. Circuit Breaker

```dart
final breaker = CircuitBreaker(
  failureThreshold: 5,
  timeout: Duration(seconds: 60),
);

try {
  await breaker.execute(() => callThirdPartyAPI());
} on CircuitBreakerException {
  // Circuit is open - fail fast
}
```

---

## 4. Mutex Lock (Token Refresh)

```dart
final tokenLock = MutexLock();

Future<String> getValidToken() async {
  return tokenLock.acquire(() async {
    if (tokenIsExpired) {
      await refreshTokenFromServer();
    }
    return currentToken;
  });
}
```

---

## 5. Semaphore (Bounded Concurrency)

```dart
final uploadSemaphore = Semaphore(3); // Max 3 concurrent

for (final file in files) {
  uploadSemaphore.acquire(() => uploadFile(file));
}
```

---

## 6. Cancellation Token

```dart
final token = CancellationToken();

// Start request
final future = handler.handleRequest(
  () => fetchData(),
  token: token,
);

// Cancel on user action
token.cancel();

try {
  await future;
} on OperationCanceledException {
  // Request was cancelled
}
```

---

## 7. Production Handler (Everything)

```dart
final handler = ProductionRequestHandler(
  retryConfig: RetryConfig(),
  maxConcurrentRequests: 10,
);

final token = CancellationToken();

try {
  final response = await handler.handleRequest(
    () => http.get(url),
    token: token,
    retryable: true,
  );
} on OperationCanceledException {
  // Cancelled
} on CircuitBreakerException {
  // Circuit open
} catch (e) {
  // Failed after retries
}
```

---

## Error Classification

| Error | Retry? |
|-------|--------|
| TimeoutException | ✅ |
| SocketException | ✅ |
| 408, 429 | ✅ |
| 5xx | ✅ |
| 400, 401, 403, 404 | ❌ |
| FormatException | ❌ |

---

## Common Patterns

### Pattern: Token Refresh Race Prevention
```dart
final tokenLock = MutexLock();
// 5 concurrent requests → 1 token refresh
```

### Pattern: Graceful Cancellation on Navigation
```dart
@override void dispose() {
  _pageCancelToken.cancel();
  super.dispose();
}
```

### Pattern: Bounded Upload Uploads
```dart
final semaphore = Semaphore(3);
// 100 files queued, 3 uploading at any time
```

### Pattern: Fail Fast on Service Down
```dart
final breaker = CircuitBreaker(failureThreshold: 5);
// After 5 failures, reject requests immediately
// Test recovery after 60s
```

---

## Configuration Examples

### Aggressive Retry (Frontend)
```dart
RetryConfig(
  maxRetries: 3,
  initialDelay: Duration(milliseconds: 50),
  backoffMultiplier: 2.0,
  maxDelay: Duration(seconds: 10),
)
```

### Conservative Retry (Backend)
```dart
RetryConfig(
  maxRetries: 5,
  initialDelay: Duration(milliseconds: 500),
  backoffMultiplier: 1.5,
  maxDelay: Duration(minutes: 1),
)
```

### Strict Circuit Breaker
```dart
CircuitBreaker(
  failureThreshold: 3,  // Open after 3 failures
  timeout: Duration(seconds: 30),  // Test recovery quickly
)
```

### Loose Circuit Breaker
```dart
CircuitBreaker(
  failureThreshold: 10,  // Tolerate more failures
  timeout: Duration(minutes: 5),  // Give service time
)
```

---

## Monitoring

```dart
handler.onRetry = (attempt, delay) {
  logger.info('Retry $attempt after ${delay.inMilliseconds}ms');
};

handler.onCircuitStateChange = (old, new) {
  logger.warn('Circuit: $old → $new');
};

final diag = handler.getDiagnostics();
print(diag);  // See current state
```

---

## Testing

```dart
test('Retry succeeds after failures', () async {
  int count = 0;
  
  final result = await retryWithBackoff(
    () {
      count++;
      if (count < 3) throw SocketException('Fail');
      return 'Success';
    },
    config: RetryConfig(maxRetries: 3),
  );
  
  expect(result, 'Success');
  expect(count, 3);
});
```

---

## API Summary

| Component | Key Methods |
|-----------|-------------|
| **RetryConfig** | `getDelay(attempt)`, `copyWith()` |
| **retryWithBackoff** | `retryWithBackoff(fn, config, onRetry, shouldRetry)` |
| **CircuitBreaker** | `execute(fn)`, `reset()`, `getDiagnostics()` |
| **MutexLock** | `acquire(fn)` |
| **Semaphore** | `acquire(fn)` |
| **CancellationToken** | `cancel()`, `onCancel()`, `throwIfCancelled()` |
| **ProductionRequestHandler** | `handleRequest(fn, token, retryable)`, `getDiagnostics()` |

---

## Performance Quick Facts

- **Retry backoff calc**: <1ms
- **Circuit breaker check**: <0.05ms
- **Mutex acquire** (uncontended): ~0.1ms
- **Semaphore acquire** (uncontended): ~0.05ms
- **Cancellation check**: <0.05ms
- **Memory per handler**: ~500 bytes + queue state

---

## Common Mistakes

❌ Retry POST without idempotency key
❌ Use same delay for all retries (no backoff)
❌ Retry forever (infinite loop)
❌ Retry 4xx errors (401, 403, 404)
❌ Allow unbounded concurrent requests
❌ Ignore cancellation tokens (orphaned requests)

✅ Use idempotency keys for POST
✅ Exponential backoff with jitter
✅ Set maxRetries limit
✅ Classify errors (transient vs permanent)
✅ Bound concurrency with semaphore
✅ Implement cancellation tokens

---

## Real-World Scenarios

### Scenario 1: Payment Processing
```dart
// Only retry if idempotent
await handler.handleRequest(
  () => chargeCard(
    headers: {'Idempotency-Key': orderId},
  ),
  retryable: true,  // Safe with key
);
```

### Scenario 2: Mobile Offline Sync
```dart
// Aggressive retry for user action
final config = RetryConfig(maxRetries: 3, initialDelay: Duration(ms: 50));
await retryWithBackoff(
  () => syncData(),
  config: config,
);
```

### Scenario 3: Third-Party API Integration
```dart
// Fail fast on service down
final breaker = CircuitBreaker(failureThreshold: 5);
await breaker.execute(() => callThirdPartyAPI());
```

### Scenario 4: Mobile Uploads
```dart
// Prevent pool exhaustion
final semaphore = Semaphore(3);
for (final file in filesToUpload) {
  semaphore.acquire(() => uploadFile(file));
}
```

### Scenario 5: Page Navigation
```dart
// Cancel pending requests
@override void dispose() {
  _pageCancelToken.cancel();
  super.dispose();
}
```

---

**More details**: See README.md and ANALYSIS.md

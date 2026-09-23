import 'package:retry_strategies/retry_strategies.dart';

/// Token Refresh with Mutex Lock Example.
///
/// Demonstrates preventing token refresh race condition.
/// Multiple concurrent requests all need a valid token.
/// Without lock: all 5 requests call refresh (wasteful, wrong).
/// With lock: 1st acquires, refreshes; others wait; all get same token.
Future<void> main() async {
  print('=== Token Refresh with Mutex Lock ===\n');

  final authManager = AuthManager();

  print('Simulating 5 concurrent token requests...\n');

  // Simulate 5 concurrent requests all calling getValidToken()
  final futures = [
    authManager.getValidToken(),
    authManager.getValidToken(),
    authManager.getValidToken(),
    authManager.getValidToken(),
    authManager.getValidToken(),
  ];

  final tokens = await Future.wait(futures);

  print('\nCollected tokens:');
  for (int i = 0; i < tokens.length; i++) {
    print('  Request ${i + 1}: ${tokens[i]}');
  }

  final uniqueTokens = tokens.toSet();
  print('\nUnique tokens: ${uniqueTokens.length}');

  if (uniqueTokens.length == 1) {
    print('✓ Success! All requests got the same token (1 refresh happened)');
  } else {
    print('✗ Failed! Multiple unique tokens (${uniqueTokens.length} refreshes)');
  }
}

/// Simulated auth manager with token refresh.
class AuthManager {
  String? _token;
  DateTime? _expiresAt;
  final MutexLock _refreshLock = MutexLock();
  int _refreshCount = 0;

  /// Gets a valid token, refreshing if necessary.
  /// Only one refresh happens concurrently, regardless of call count.
  Future<String> getValidToken() async {
    return _refreshLock.acquire(() async {
      // Check again inside lock (double-checked locking pattern)
      if (_token != null && DateTime.now().isBefore(_expiresAt!)) {
        print('  → Got cached token: $_token');
        return _token!;
      }

      // Refresh
      print('  → Refreshing token (this request acquired lock)...');
      await Future.delayed(Duration(milliseconds: 500));

      _refreshCount++;
      _token = 'token_${DateTime.now().millisecondsSinceEpoch}';
      _expiresAt = DateTime.now().add(Duration(hours: 1));

      print('  → Token refreshed: $_token (#$_refreshCount refresh)');
      return _token!;
    });
  }
}

/// Expected output:
/// ```
/// === Token Refresh with Mutex Lock ===
///
/// Simulating 5 concurrent token requests...
///
///   → Refreshing token (this request acquired lock)...
///   → Waiting for lock...
///   → Waiting for lock...
///   → Waiting for lock...
///   → Waiting for lock...
///   → Token refreshed: token_1726234567890 (#1 refresh)
///   → Got cached token: token_1726234567890
///   → Got cached token: token_1726234567890
///   → Got cached token: token_1726234567890
///   → Got cached token: token_1726234567890
///
/// Collected tokens:
///   Request 1: token_1726234567890
///   Request 2: token_1726234567890
///   Request 3: token_1726234567890
///   Request 4: token_1726234567890
///   Request 5: token_1726234567890
///
/// Unique tokens: 1
/// ✓ Success! All requests got the same token (1 refresh happened)
/// ```

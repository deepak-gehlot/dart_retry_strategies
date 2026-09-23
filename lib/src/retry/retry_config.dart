import 'dart:math';

/// Configuration for exponential backoff retry strategy.
///
/// Implements full jitter exponential backoff as recommended by AWS:
/// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
class RetryConfig {
  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Initial delay before first retry.
  ///
  /// Typical: 100ms for user-facing operations, 500ms for background tasks.
  final Duration initialDelay;

  /// Multiplier for exponential growth of delays.
  ///
  /// Each retry delay = previous × backoffMultiplier
  /// Typical: 2.0 for exponential, 1.5 for gentler progression.
  final double backoffMultiplier;

  /// Maximum delay cap to prevent infinite growth.
  ///
  /// Typical: 30s to avoid excessive waits.
  final Duration maxDelay;

  /// Random number generator for jitter (for testing/seeding).
  final Random random;

  RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 100),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    Random? random,
  })  : random = random ?? Random(),
        assert(maxRetries >= 0, 'maxRetries must be >= 0'),
        assert(backoffMultiplier > 1.0, 'backoffMultiplier must be > 1.0'),
        assert(
          initialDelay.inMilliseconds > 0,
          'initialDelay must be positive',
        ),
        assert(maxDelay.inMilliseconds > 0, 'maxDelay must be positive');

  /// Calculates delay for a given retry attempt using exponential backoff + full jitter.
  ///
  /// Formula:
  /// 1. exponential = initialDelay × (backoffMultiplier ^ attempt)
  /// 2. capped = min(exponential, maxDelay)
  /// 3. jittered = random(0, capped)
  ///
  /// Full jitter prevents thundering herd by randomizing entire delay range,
  /// not just adding noise to the exponential value.
  ///
  /// Example progression with defaults:
  /// - Attempt 0: 0-100ms
  /// - Attempt 1: 0-200ms
  /// - Attempt 2: 0-400ms
  /// - Attempt 3: 0-800ms
  /// - Attempt 4+: 0-30s (capped)
  Duration getDelay(int attempt) {
    assert(attempt >= 0, 'attempt must be >= 0');

    // Exponential growth: initial × multiplier^attempt
    final exponentialMs = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attempt).toDouble();

    // Cap at maxDelay
    final cappedMs =
        exponentialMs.clamp(0, maxDelay.inMilliseconds.toDouble()).toInt();

    // Full jitter: random value in [0, capped]
    final jitterMs = random.nextInt(cappedMs + 1);

    return Duration(milliseconds: jitterMs);
  }

  /// Creates a copy with modified fields.
  RetryConfig copyWith({
    int? maxRetries,
    Duration? initialDelay,
    double? backoffMultiplier,
    Duration? maxDelay,
    Random? random,
  }) =>
      RetryConfig(
        maxRetries: maxRetries ?? this.maxRetries,
        initialDelay: initialDelay ?? this.initialDelay,
        backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
        maxDelay: maxDelay ?? this.maxDelay,
        random: random ?? this.random,
      );

  @override
  String toString() =>
      'RetryConfig(maxRetries: $maxRetries, initialDelay: $initialDelay, '
      'backoffMultiplier: $backoffMultiplier, maxDelay: $maxDelay)';
}

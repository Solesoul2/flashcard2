// lib/services/sr_calculator.dart
import 'dart:math' show max;

/// Represents the result of an SR calculation for a single review.
class SRResult {
  final double easinessFactor; // The new easiness factor (EF).
  final int interval;         // The new interval in days until the next review.
  final int repetitions;      // The new count of consecutive correct repetitions.

  const SRResult({
    required this.easinessFactor,
    required this.interval,
    required this.repetitions,
  });

  @override
  String toString() {
    return 'SRResult(ef: $easinessFactor, interval: $interval, repetitions: $repetitions)';
  }
}

/// Calculates the next spaced repetition state based on the SM-2 algorithm principles.
class SRCalculator {
  // Minimum allowed easiness factor.
  static const double _minEasinessFactor = 1.3;

  /// Calculates the next SR state.
  ///
  /// Parameters:
  ///   [quality]: The user's rating of how well they remembered the item (0-5).
  ///              0=worst, 5=best. Typically, < 3 means incorrect.
  ///   [previousEasinessFactor]: The easiness factor from the *previous* review.
  ///   [previousInterval]: The interval (in days) used *before* the current review.
  ///   [previousRepetitions]: The number of consecutive correct reviews *before* the current review.
  ///
  /// Returns: An [SRResult] containing the new easiness factor, interval, and repetitions count.
  static SRResult calculate({
    required int quality, // User rating (0-5)
    required double previousEasinessFactor,
    required int previousInterval,
    required int previousRepetitions,
  }) {
    // 1. Input Validation
    if (quality < 0 || quality > 5) {
      throw ArgumentError('Quality rating must be between 0 and 5.');
    }
    if (previousEasinessFactor < _minEasinessFactor) {
        // Although EF shouldn't normally drop below min, handle defensively
        previousEasinessFactor = _minEasinessFactor;
    }
    if (previousInterval < 0 || previousRepetitions < 0) {
        throw ArgumentError('Previous interval and repetitions cannot be negative.');
    }


    // 2. Calculate New Easiness Factor (EF)
    // Formula: EF' = EF + [0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)]
    // Where q is the quality rating (0-5).
    double newEasinessFactor = previousEasinessFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    // Clamp EF to the minimum value.
    newEasinessFactor = max(_minEasinessFactor, newEasinessFactor);


    // 3. Determine New Repetitions Count and Interval
    int newRepetitions;
    int newInterval;

    if (quality < 3) {
      // Incorrect response (quality 0, 1, or 2)
      newRepetitions = 0; // Reset consecutive correct repetitions.
      newInterval = 1;    // Schedule for review again tomorrow (or 0 for same day).
                          // Using 1 day is common.
    } else {
      // Correct response (quality 3, 4, or 5)
      newRepetitions = previousRepetitions + 1;

      // Calculate interval based on repetitions count and EF.
      if (newRepetitions == 1) {
        newInterval = 1; // First correct repetition.
      } else if (newRepetitions == 2) {
        newInterval = 6; // Second correct repetition.
      } else {
        // Subsequent correct repetitions.
        // Formula: I(n) = I(n-1) * EF
        // Ensure interval doesn't grow excessively large too quickly? (Optional cap)
        newInterval = (previousInterval * newEasinessFactor).round();
      }
    }

    // --- Optional Interval Cap ---
    // const int maxInterval = 365 * 5; // e.g., Max 5 years
    // newInterval = min(newInterval, maxInterval);
    // --- End Optional Cap ---


    // 4. Return Result
    return SRResult(
      easinessFactor: newEasinessFactor,
      interval: newInterval,
      repetitions: newRepetitions,
    );
  }
}
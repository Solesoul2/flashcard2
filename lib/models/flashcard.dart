// lib/models/flashcard.dart
import 'package:flutter/foundation.dart'; // Required for immutable and ValueGetter

// Represents a single, immutable flashcard with question, answer, and SR data.
@immutable
class Flashcard {
  final int? id; // Unique identifier from the database; null if not yet saved.
  final String question; // The prompt or question side of the card.
  final String answer; // The answer or response side of the card.
  final int? folderId; // Foreign key linking to the 'folders' table; null if uncategorized.

  // Spaced Repetition Fields
  final double easinessFactor; // How easy the card is (e.g., starts at 2.5).
  final int interval;         // Current interval between reviews (days).
  final int repetitions;      // Number of times reviewed correctly in a row.
  final DateTime? lastReviewed; // Timestamp of the last review.
  final DateTime? nextReview;   // Timestamp for the next scheduled review.

  // New field to store the quality (0-5) of the *last* review submitted
  final int? lastRatingQuality;

  // Constructor with required fields and optional/defaulted SR/rating fields.
  const Flashcard({
    this.id,
    required this.question,
    required this.answer,
    this.folderId,
    // Assign defaults for SR fields if not provided
    this.easinessFactor = 2.5,
    this.interval = 0,
    this.repetitions = 0,
    this.lastReviewed,
    this.nextReview,
    // New field is nullable, defaults to null
    this.lastRatingQuality,
  });

  // Converts a Flashcard object into a Map for database operations.
  // Keys correspond to column names defined in DatabaseHelper.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question': question,
      'answer': answer,
      'folderId': folderId,
      // Use DatabaseHelper consts if accessible, otherwise string literals must match DB
      'easinessFactor': easinessFactor,
      'interval': interval,
      'repetitions': repetitions,
      // Convert DateTime? to ISO 8601 String? for database storage
      'lastReviewed': lastReviewed?.toIso8601String(),
      'nextReview': nextReview?.toIso8601String(),
      // Add new field to map
      'lastRatingQuality': lastRatingQuality,
    };
  }

  // Creates a Flashcard object from a Map (e.g., from the database).
  factory Flashcard.fromMap(Map<String, dynamic> map) {
    // Helper function to safely parse DateTime from String?
    DateTime? _parseDateTime(String? dateString) {
      if (dateString == null || dateString.isEmpty) {
        return null;
      }
      try {
        return DateTime.parse(dateString);
      } catch (e) {
        print("Error parsing date string '$dateString': $e");
        return null; // Return null if parsing fails
      }
    }

    // Helper function to safely parse double (handling potential int from DB)
    double _parseDouble(dynamic value, double defaultValue) {
       if (value is double) return value;
       if (value is int) return value.toDouble();
       if (value is String) return double.tryParse(value) ?? defaultValue;
       return defaultValue;
    }

    // Helper function to safely parse int
    int _parseInt(dynamic value, int defaultValue) {
       if (value is int) return value;
       if (value is double) return value.toInt(); // Handle potential double
       if (value is String) return int.tryParse(value) ?? defaultValue;
       return defaultValue;
    }


    return Flashcard(
      // Ensure correct type casting and handle potential nulls from DB.
      id: map['id'] as int?,
      question: map['question'] as String? ?? '', // Default to empty string if null
      answer: map['answer'] as String? ?? '',   // Default to empty string if null
      folderId: map['folderId'] as int?,

      // Parse SR fields safely, providing defaults
      // Use DatabaseHelper consts if accessible, otherwise strings must match DB
      easinessFactor: _parseDouble(map['easinessFactor'], 2.5),
      interval: _parseInt(map['interval'], 0),
      repetitions: _parseInt(map['repetitions'], 0),
      lastReviewed: _parseDateTime(map['lastReviewed'] as String?),
      nextReview: _parseDateTime(map['nextReview'] as String?),

      // Parse the new field (nullable int)
      lastRatingQuality: map['lastRatingQuality'] as int?,
    );
  }

  // Creates a copy of this Flashcard instance with potentially updated fields.
  // Useful for updating state without direct mutation.
  Flashcard copyWith({
    int? id,
    String? question,
    String? answer,
    // Use ValueGetter to distinguish between setting folderId to null and not changing it
    ValueGetter<int?>? folderId,
    // SR fields
    double? easinessFactor,
    int? interval,
    int? repetitions,
    ValueGetter<DateTime?>? lastReviewed, // Use ValueGetter for nullable DateTime
    ValueGetter<DateTime?>? nextReview,   // Use ValueGetter for nullable DateTime
    // Add new field, using ValueGetter for nullability distinction
    ValueGetter<int?>? lastRatingQuality,
  }) {
    return Flashcard(
      // If a new value is provided, use it; otherwise, keep the existing value.
      id: id ?? this.id,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      folderId: folderId != null ? folderId() : this.folderId,
      // Apply updates for SR fields
      easinessFactor: easinessFactor ?? this.easinessFactor,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      lastReviewed: lastReviewed != null ? lastReviewed() : this.lastReviewed,
      nextReview: nextReview != null ? nextReview() : this.nextReview,
      // Apply update for the new field
      lastRatingQuality: lastRatingQuality != null ? lastRatingQuality() : this.lastRatingQuality,
    );
  }

  // Override toString for better debug output.
  @override
  String toString() {
    return 'Flashcard(id: $id, question: "$question", answer: "$answer", folderId: $folderId, '
           'ef: $easinessFactor, int: $interval, reps: $repetitions, '
           'last: ${lastReviewed?.toIso8601String()}, next: ${nextReview?.toIso8601String()}, '
           'lastQuality: $lastRatingQuality)'; // Added lastRatingQuality
  }

  // Override equality operator (==) for comparing Flashcard instances.
  @override
  bool operator ==(Object other) {
    // Check if the instances are identical.
    if (identical(this, other)) return true;

    // Check if the other object is a Flashcard and if all fields match.
    return other is Flashcard &&
      other.id == id &&
      other.question == question &&
      other.answer == answer &&
      other.folderId == folderId &&
      // Compare SR fields
      other.easinessFactor == easinessFactor &&
      other.interval == interval &&
      other.repetitions == repetitions &&
      other.lastReviewed == lastReviewed &&
      other.nextReview == nextReview &&
      // Compare new field
      other.lastRatingQuality == lastRatingQuality;
  }

  // Override hashCode to be consistent with the == operator.
  @override
  int get hashCode {
    // Combine hash codes of all fields.
    return id.hashCode ^
      question.hashCode ^
      answer.hashCode ^
      folderId.hashCode ^
      // Combine hash codes of SR fields
      easinessFactor.hashCode ^
      interval.hashCode ^
      repetitions.hashCode ^
      lastReviewed.hashCode ^
      nextReview.hashCode ^
      // Combine hash code of new field
      lastRatingQuality.hashCode;
  }
}
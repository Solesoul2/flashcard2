// lib/services/persistence_service.dart
import 'dart:convert'; // For JSON encoding/decoding
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for persisting simple UI state, specifically the
/// checked state of checklist items within flashcard answers.
/// Uses SharedPreferences for storage.
/// Dependencies (SharedPreferences) are injected via the constructor.
class PersistenceService {
  // SharedPreferences instance - now provided via constructor
  final SharedPreferences _prefs;

  // A prefix used for keys in SharedPreferences to avoid collisions.
  static const String _checklistStatePrefix = 'checklist_state_';

  // Constructor accepts a SharedPreferences instance.
  PersistenceService(this._prefs);

  // Static factory method to create an instance with the real SharedPreferences.
  // Your app code (like providers) will use this.
  static Future<PersistenceService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PersistenceService(prefs);
  }
  // NOTE: You will need to update how DatabaseHelper gets this service.
  // We will handle that when we update DatabaseHelper.

  // Generates a unique storage key for a given flashcard ID.
  // Made public for potential use in testing setup if needed, but primarily internal.
  // Consider if this truly needs to be public. For now, keeping it for clarity.
  // Alternatively, keep it private and test indirectly. Let's make it private again.
  String _getChecklistStateKey(int flashcardId) {
    return '$_checklistStatePrefix$flashcardId';
  }

  /// Saves the state of a checklist for a given flashcard ID.
  ///
  /// [flashcardId]: The ID of the flashcard. If null, ignored.
  /// [state]: Map<int, bool> of original index to checked state.
  Future<void> saveChecklistState(int? flashcardId, Map<int, bool> state) async {
    if (flashcardId == null) {
      print("Warning: Attempted to save checklist state for a flashcard without an ID.");
      return;
    }
    try {
      // Use the injected _prefs instance directly
      final Map<String, bool> stringKeyMap =
          state.map((key, value) => MapEntry(key.toString(), value));
      final String jsonState = json.encode(stringKeyMap);
      await _prefs.setString(_getChecklistStateKey(flashcardId), jsonState);
    } catch (e) {
      print("Error saving checklist state for card ID $flashcardId: $e");
    }
  }

  /// Loads the checklist state for a given flashcard ID.
  ///
  /// [flashcardId]: The ID of the flashcard. If null, returns empty map.
  /// Returns a Map<int, bool>. Returns empty map if no state found or error.
  Future<Map<int, bool>> loadChecklistState(int? flashcardId) async {
    if (flashcardId == null) {
      print("Warning: Attempted to load checklist state for a flashcard without an ID.");
      return {};
    }
    try {
      // Use the injected _prefs instance directly
      final String? jsonState = _prefs.getString(_getChecklistStateKey(flashcardId));

      if (jsonState != null && jsonState.isNotEmpty) {
        final Map<String, dynamic> decodedMap = json.decode(jsonState);
        final Map<int, bool> state = {};
        decodedMap.forEach((key, value) {
          final int? index = int.tryParse(key);
          if (index != null && value is bool) {
            state[index] = value;
          } else {
            print("Warning: Skipping invalid item during checklist state load for card ID $flashcardId. Key: $key, Value: $value");
          }
        });
        return state;
      }
    } catch (e) {
      print("Error loading checklist state for card ID $flashcardId: $e");
    }
    return {};
  }

  /// Clears the saved checklist state for a specific flashcard ID.
  Future<void> clearChecklistState(int? flashcardId) async {
    if (flashcardId == null) return;
    try {
      // Use the injected _prefs instance directly
      await _prefs.remove(_getChecklistStateKey(flashcardId));
      print("Cleared checklist state for card ID $flashcardId.");
    } catch (e) {
      print("Error clearing checklist state for card ID $flashcardId: $e");
    }
  }
}
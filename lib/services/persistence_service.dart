// lib/services/persistence_service.dart
import 'dart:convert'; // For JSON encoding/decoding
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for persisting simple UI state, including checklist states
/// and study mode settings. Uses SharedPreferences for storage.
class PersistenceService {
  final SharedPreferences _prefs;

  // Keys for persisted data
  static const String _checklistStatePrefix = 'checklist_state_';
  static const String _studySettingPrefix = 'study_setting_';
  static const String _setting1Key = '${_studySettingPrefix}hide_unmarked_text_with_checkboxes'; // Req 1 setting
  static const String _setting2Key = '${_studySettingPrefix}show_previously_checked_items'; // Req 2 setting

  // Constructor accepts a SharedPreferences instance.
  PersistenceService(this._prefs);

  // Static factory method to create an instance with the real SharedPreferences.
  static Future<PersistenceService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PersistenceService(prefs);
  }

  // --- Checklist State Persistence ---

  String _getChecklistStateKey(int flashcardId) {
    return '$_checklistStatePrefix$flashcardId';
  }

  /// Saves the state of a checklist for a given flashcard ID.
  Future<void> saveChecklistState(int? flashcardId, Map<int, bool> state) async {
    if (flashcardId == null) {
      print("Warning: Attempted to save checklist state for a flashcard without an ID.");
      return;
    }
    try {
      final Map<String, bool> stringKeyMap =
          state.map((key, value) => MapEntry(key.toString(), value));
      final String jsonState = json.encode(stringKeyMap);
      await _prefs.setString(_getChecklistStateKey(flashcardId), jsonState);
    } catch (e) {
      print("Error saving checklist state for card ID $flashcardId: $e");
    }
  }

  /// Loads the checklist state for a given flashcard ID.
  Future<Map<int, bool>> loadChecklistState(int? flashcardId) async {
    if (flashcardId == null) {
      print("Warning: Attempted to load checklist state for a flashcard without an ID.");
      return {};
    }
    try {
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
      await _prefs.remove(_getChecklistStateKey(flashcardId));
      print("Cleared checklist state for card ID $flashcardId.");
    } catch (e) {
      print("Error clearing checklist state for card ID $flashcardId: $e");
    }
  }

  // --- Study Settings Persistence ---

  /// Saves the state of the study settings.
  /// [setting1Active]: Corresponds to Req 1 (hide unmarked text followed by checkboxes).
  /// [setting2Active]: Corresponds to Req 2 (show previously checked items).
  Future<void> saveStudySettings({required bool setting1Active, required bool setting2Active}) async {
    try {
      await _prefs.setBool(_setting1Key, setting1Active);
      await _prefs.setBool(_setting2Key, setting2Active);
      print("Saved study settings: Req1 Active=$setting1Active, Req2 Active=$setting2Active");
    } catch (e) {
      print("Error saving study settings: $e");
      // Optionally rethrow or handle the error
    }
  }

  /// Loads the state of the study settings.
  /// Returns a map containing the loaded settings. Defaults to `true` if a setting is not found.
  Future<Map<String, bool>> loadStudySettings() async {
    try {
      // Load settings, defaulting to true if not found (initial state)
      final bool setting1 = _prefs.getBool(_setting1Key) ?? true; // Default Req 1 to active
      final bool setting2 = _prefs.getBool(_setting2Key) ?? true; // Default Req 2 to active

      print("Loaded study settings: Req1 Active=$setting1, Req2 Active=$setting2");
      return {
        'setting1Active': setting1,
        'setting2Active': setting2,
      };
    } catch (e) {
      print("Error loading study settings: $e");
      // Return default values on error
      return {
        'setting1Active': true,
        'setting2Active': true,
      };
    }
  }
}
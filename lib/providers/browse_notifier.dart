// lib/providers/browse_notifier.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import models and services/providers
import '../models/flashcard.dart';
import '../models/folder.dart';
import '../providers/service_providers.dart'; // Access DatabaseHelper provider
import '../services/database_helper.dart'; // Import for explicit type usage if needed

/// Notifier responsible for loading the list of flashcards for a specific folder
/// to be used in the BrowsePage.
// Base class is FamilyAsyncNotifier (asynchronous)
class BrowseNotifier extends FamilyAsyncNotifier<List<Flashcard>, Folder> {

  // The build method fetches the initial list of flashcards for the given folder.
  @override
  Future<List<Flashcard>> build(Folder arg /* folder */) async {
    final folder = arg; // The folder context passed via the family provider
    final folderId = folder.id; // Explicitly get the ID

    // print("[BrowseNotifier ASYNC] Build STARTING for Folder: '${folder.name}' (ID: $folderId)");

    try {
      // Obtain the DatabaseHelper instance asynchronously.
      final dbHelper = await ref.watch(databaseHelperProvider.future);

      // Fetch all flashcards associated with the folder's ID.
      final cards = await dbHelper.getFlashcards(folderId: folderId);

      // print("[BrowseNotifier ASYNC] Loaded ${cards.length} cards for Folder ID: $folderId");

      return cards;

    } catch (e, stackTrace) {
      // print("[BrowseNotifier ASYNC] ERROR loading cards for Folder ID: $folderId - $e\n$stackTrace");
      throw Exception('Failed to load cards for folder "${folder.name}": $e');
    }
  }

  // --- Optional: Add delete functionality later if needed ---
  Future<void> deleteCard(int cardId) async {
    final folder = arg; // Get the folder context passed to build
    final currentState = state.valueOrNull;
    if (currentState == null) return; // Cannot delete if state isn't loaded

    final dbHelper = await ref.read(databaseHelperProvider.future);

    try {
      final affectedRows = await dbHelper.deleteFlashcard(cardId);

      if (affectedRows > 0) {
        print("[BrowseNotifier ASYNC]: Deleted card ID $cardId.");
        state = AsyncData(
          currentState.where((card) => card.id != cardId).toList()
        );
      } else {
         print("[BrowseNotifier ASYNC]: Card ID $cardId not found for deletion.");
      }

    } catch (e, stackTrace) { // Capture stackTrace
       print("[BrowseNotifier ASYNC]: Error deleting card ID $cardId: $e");
       state = AsyncError(e, stackTrace); // Set error state
    }
  }
}

// Provider Definition - REMOVED .autoDispose for diagnostics
final browseProvider =
    AsyncNotifierProvider.family<BrowseNotifier, List<Flashcard>, Folder>(
  () => BrowseNotifier(),
);